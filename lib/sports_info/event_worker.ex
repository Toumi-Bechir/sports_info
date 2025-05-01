defmodule SportsInfo.EventWorker do
  use GenServer
  alias Phoenix.PubSub

  @pubsub_topic "sports:events"
  @num_shards 16
  @batch_interval 50
  @cleanup_interval :timer.minutes(5)
  @stale_threshold :timer.hours(1)

  def start_link(shard) do
    GenServer.start_link(__MODULE__, shard, name: via_tuple(shard))
  end

  def process_message(event_id, message) do
    shard = shard_for_event(event_id)
    case :pg.get_members(SportsInfo.EventWorkerGroup, shard) do
      [] ->
        SportsInfo.EventWorkerSupervisor.start_worker(shard)
        GenServer.cast(via_tuple(shard), {:process_message, event_id, message})
      pids ->
        pid = Enum.random(pids)
        GenServer.cast(pid, {:process_message, event_id, message})
    end
  end

  def get_events(shard, sport \\ nil) do
    case :pg.get_members(SportsInfo.EventWorkerGroup, shard) do
      [] ->
        SportsInfo.EventWorkerSupervisor.start_worker(shard)
        GenServer.call(via_tuple(shard), {:get_events, sport})
      [pid | _] ->
        GenServer.call(pid, {:get_events, sport})
    end
  end

  def get_event(shard, event_id) do
    case :pg.get_members(SportsInfo.EventWorkerGroup, shard) do
      [] ->
        SportsInfo.EventWorkerSupervisor.start_worker(shard)
        GenServer.call(via_tuple(shard), {:get_event, event_id})
      [pid | _] ->
        GenServer.call(pid, {:get_event, event_id})
    end
  end

  def init(shard) do
    :pg.join(SportsInfo.EventWorkerGroup, shard, self())
    ets_tables = %{}
    schedule_batch_broadcast()
    schedule_cleanup()
    {:ok, %{shard: shard, ets_tables: ets_tables, updates: %{}, pending_updates: %{}, last_updated: %{}, initialized: %{}}}
  end

  def handle_cast({:process_message, event_id, message}, state) do
    start_time = System.monotonic_time()
    %{shard: shard, ets_tables: ets_tables, updates: updates, pending_updates: pending_updates, last_updated: last_updated, initialized: initialized} = state

    sport = case message do
      %{"mt" => "avl", "evts" => events} ->
        event = Enum.find(events, fn e -> e["id"] == event_id end)
        if event, do: Map.get(event, "sport", "unknown"), else: "unknown"
      %{"mt" => "updt"} ->
        Map.get(message, "sport", "unknown")
      _ ->
        "unknown"
    end

    #IO.puts("EventWorker: Processing message for event #{event_id} with sport #{sport}")

    ets_table = ensure_ets_table(sport, shard, ets_tables)

    case message do
      %{"mt" => "avl"} ->
        event = Enum.find(message["evts"], fn e -> e["id"] == event_id end)
        if event do
          updated_event = Map.put(event, "sport", sport)
          #IO.puts("EventWorker: Storing avl event #{event_id} in ETS for sport #{sport}")
          :ets.insert(ets_table, {event_id, updated_event})

          new_initialized = Map.put(initialized, {sport, event_id}, true)

          new_pending_updates = case Map.get(pending_updates, {sport, event_id}) do
            nil ->
              pending_updates
            pending_message ->
              merged_event = Map.merge(updated_event, pending_message)
              #IO.puts("EventWorker: Applying pending update for event #{event_id} in sport #{sport}")
              :ets.insert(ets_table, {event_id, merged_event})
              Map.delete(pending_updates, {sport, event_id})
          end

          new_updates = Map.put(updates, {sport, event_id}, updated_event)

          current_time = System.monotonic_time(:millisecond)
          updated_last_updated = Map.put(last_updated, {sport, event_id}, current_time)

          new_state = %{
            state |
            ets_tables: Map.put(ets_tables, sport, ets_table),
            updates: new_updates,
            pending_updates: new_pending_updates,
            last_updated: updated_last_updated,
            initialized: new_initialized
          }
          {:noreply, new_state}
        else
          #IO.puts("EventWorker: Event #{event_id} not found in avl message")
          {:noreply, state}
        end

      %{"mt" => "updt"} ->
        sport = find_event_sport(ets_tables, event_id) || sport

        ets_table = ensure_ets_table(sport, shard, ets_tables)

        case :ets.lookup(ets_table, event_id) do
          [{^event_id, existing_event}] ->
            updated_event = Map.merge(existing_event, message)
                           |> Map.put("sport", sport)
                           |> ensure_cmp_name(existing_event)
            #IO.puts("EventWorker: Updating event #{event_id} in ETS for sport #{sport}")
            :ets.insert(ets_table, {event_id, updated_event})

            current_time = System.monotonic_time(:millisecond)
            updated_last_updated = Map.put(last_updated, {sport, event_id}, current_time)

            new_updates = Map.put(updates, {sport, event_id}, updated_event)

            new_state = %{
              state |
              ets_tables: Map.put(ets_tables, sport, ets_table),
              updates: new_updates,
              last_updated: updated_last_updated
            }
            {:noreply, new_state}
          [] ->
            #IO.puts("EventWorker: Buffering updt message for event #{event_id} in sport #{sport} (no prior avl message)")
            new_pending_updates = Map.put(pending_updates, {sport, event_id}, message)

            current_time = System.monotonic_time(:millisecond)
            updated_last_updated = Map.put(last_updated, {sport, event_id}, current_time)

            new_state = %{
              state |
              ets_tables: Map.put(ets_tables, sport, ets_table),
              pending_updates: new_pending_updates,
              last_updated: updated_last_updated
            }
            {:noreply, new_state}
        end
    end
  end

  def handle_info(:broadcast_batch, state) do
    start_time = System.monotonic_time()
    %{updates: updates, initialized: initialized} = state

    #IO.puts("EventWorker: Broadcasting batch with #{map_size(updates)} updates")
    Enum.each(updates, fn {{sport, event_id}, event} ->
      if Map.get(initialized, {sport, event_id}, false) do
        topic = "#{@pubsub_topic}:#{sport}"
        #IO.puts("EventWorker: Broadcasting update for event #{event_id} to topic #{topic}")
        PubSub.broadcast(SportsInfo.PubSub, topic, {:event_update, event_id, event})
      else
        #IO.puts("EventWorker: Skipping broadcast for event #{event_id} in sport #{sport} (not yet initialized)")
      end
    end)

    duration = System.monotonic_time() - start_time
    :telemetry.execute([:sports_info, :batch_broadcast], %{duration: duration}, %{count: map_size(updates)})

    schedule_batch_broadcast()
    {:noreply, %{state | updates: %{}}}
  end

  def handle_info(:cleanup, state) do
    %{ets_tables: ets_tables, last_updated: last_updated} = state
    current_time = System.monotonic_time(:millisecond)

    stale_entries = Enum.filter(last_updated, fn {_, timestamp} ->
      current_time - timestamp > @stale_threshold
    end)

    Enum.each(stale_entries, fn {{sport, event_id}, _} ->
      ets_table = Map.get(ets_tables, sport)
      if ets_table do
        #IO.puts("EventWorker: Cleaning up stale event #{event_id} for sport #{sport}")
        :ets.delete(ets_table, event_id)
      end
    end)

    updated_last_updated = Map.drop(last_updated, Enum.map(stale_entries, fn {key, _} -> key end))

    schedule_cleanup()
    {:noreply, %{state | last_updated: updated_last_updated}}
  end

  def handle_call({:get_events, sport}, _from, state) do
    %{ets_tables: ets_tables} = state
    events = if sport do
      ets_table = Map.get(ets_tables, sport, nil)
      if ets_table do
        events = :ets.tab2list(ets_table) |> Enum.map(fn {_, event} -> event end)
        #IO.puts("EventWorker: Retrieving #{length(events)} events for sport #{sport}")
        events
      else
        #IO.puts("EventWorker: No ETS table for sport #{sport}")
        []
      end
    else
      ets_tables
      |> Map.values()
      |> Enum.flat_map(fn ets_table ->
        :ets.tab2list(ets_table) |> Enum.map(fn {_, event} -> event end)
      end)
    end
    {:reply, events, state}
  end

  def handle_call({:get_event, event_id}, _from, state) do
    %{ets_tables: ets_tables} = state
    event = Enum.reduce_while(ets_tables, nil, fn {sport, ets_table}, acc ->
      case :ets.lookup(ets_table, event_id) do
        [{^event_id, event}] ->
          #IO.puts("EventWorker: Retrieved event #{event_id} for sport #{sport}")
          {:halt, event}
        [] ->
          {:cont, acc}
      end
    end)
    {:reply, event, state}
  end

  def terminate(_reason, state) do
    %{shard: shard, ets_tables: ets_tables} = state
    IO.puts("EventWorker for shard #{shard} terminating, leaving process group")
    :pg.leave(SportsInfo.EventWorkerGroup, shard, self())

    Enum.each(ets_tables, fn {sport, table} ->
      IO.puts("EventWorker: Deleting ETS table for sport #{sport}: #{table}")
      :ets.delete(table)
    end)

    :ok
  end

  defp via_tuple(shard) do
    {:global, {:event_worker, shard}}
  end

  defp shard_for_event(event_id) do
    :erlang.phash2(event_id, @num_shards)
  end

  defp schedule_batch_broadcast do
    Process.send_after(self(), :broadcast_batch, @batch_interval)
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end

  defp ensure_ets_table(sport, shard, ets_tables) do
    case Map.get(ets_tables, sport) do
      nil ->
        table_name = :"events_shard_#{shard}_#{sport}"
        case :ets.whereis(table_name) do
          :undefined ->
            table = :ets.new(table_name, [:set, :public, :named_table, :compressed, read_concurrency: true, write_concurrency: true])
            #IO.puts("EventWorker: Created new ETS table #{table_name} for sport #{sport}")
            table
          table ->
            :ets.setopts(table, {:heir, self(), nil})
            #IO.puts("EventWorker: Reusing existing ETS table #{table_name} for sport #{sport}")
            table
        end
      table ->
        table
    end
  end

  defp ensure_cmp_name(updated_event, existing_event) do
    case Map.get(updated_event, "cmp_name") do
      nil ->
        cmp_name = Map.get(existing_event, "cmp_name", "Unknown League")
        Map.put(updated_event, "cmp_name", cmp_name)
      _ ->
        updated_event
    end
  end

  defp find_event_sport(ets_tables, event_id) do
    Enum.reduce_while(ets_tables, nil, fn {sport, ets_table}, acc ->
      case :ets.lookup(ets_table, event_id) do
        [{^event_id, _event}] ->
          {:halt, sport}
        [] ->
          {:cont, acc}
      end
    end)
  end
end