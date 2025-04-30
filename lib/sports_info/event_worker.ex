defmodule SportsInfo.EventWorker do
    use GenServer
    alias Phoenix.PubSub
  
    # Constants
    @pubsub_topic "sports:events"  # Base topic for broadcasting event updates
    @num_shards 16  # Number of shards for distributing events
    @batch_interval 100  # Batch updates every 100ms
    @cleanup_interval :timer.minutes(5)  # Run cleanup every 5 minutes
    @stale_threshold :timer.hours(1)  # Consider events stale after 1 hour of inactivity
  
    # Client API
  
    # Start an EventWorker for a specific shard
    def start_link(shard) do
      IO.puts("Starting EventWorker for shard #{shard}...")
      result = GenServer.start_link(__MODULE__, shard, name: via_tuple(shard))
      case result do
        {:ok, pid} ->
          IO.puts("EventWorker for shard #{shard} started successfully with pid #{inspect(pid)}")
          result
        {:error, reason} ->
          IO.puts("Failed to start EventWorker for shard #{shard}: #{inspect(reason)}")
          result
      end
    end
  
    # Process a WebSocket message for a specific event
    def process_message(event_id, message) do
      shard = shard_for_event(event_id)
      group = {SportsInfo.EventWorkerGroup, shard}
      case :pg.get_members(group) do
        [] ->
          # This should not happen since workers are started synchronously
          IO.puts("No EventWorker found for group #{inspect(group)} during process_message. This should not happen!")
          :error
        pids ->
          pid = Enum.random(pids)
          GenServer.cast(pid, {:process_message, event_id, message})
      end
    end
  
    # Retrieve all events managed by a specific shard, optionally filtered by sport, with retries
    def get_events(shard, sport \\ nil, retries \\ 3) do
      try do
        group = {SportsInfo.EventWorkerGroup, shard}
        case :pg.get_members(group) do
          [] ->
            IO.puts("No EventWorker found for group #{inspect(group)} during get_events. This should not happen!")
            []
          [pid | _] ->
            GenServer.call(pid, {:get_events, sport})
        end
      catch
        :exit, _reason when retries > 0 ->
          IO.puts("Failed to call EventWorker for shard #{shard}, retrying (#{retries} attempts left)...")
          Process.sleep(1_000)
          get_events(shard, sport, retries - 1)
        :exit, reason ->
          IO.puts("Failed to call EventWorker for shard #{shard} after retries: #{inspect(reason)}")
          []
      end
    end
  
    # Retrieve a specific event from a shard, with retries
    def get_event(shard, event_id, retries \\ 3) do
      try do
        group = {SportsInfo.EventWorkerGroup, shard}
        case :pg.get_members(group) do
          [] ->
            IO.puts("No EventWorker found for group #{inspect(group)} during get_event. This should not happen!")
            nil
          [pid | _] ->
            GenServer.call(pid, {:get_event, event_id})
        end
      catch
        :exit, _reason when retries > 0 ->
          IO.puts("Failed to call EventWorker for shard #{shard}, retrying (#{retries} attempts left)...")
          Process.sleep(1_000)
          get_event(shard, event_id, retries - 1)
        :exit, reason ->
          IO.puts("Failed to call EventWorker for shard #{shard} after retries: #{inspect(reason)}")
          nil
      end
    end
  
    # Server Callbacks
  
    # Initialize the EventWorker with ETS tables for each sport
    def init(shard) do
      try do
        # Use a namespaced group name compatible with pre-OTP 26.0
        group = {SportsInfo.EventWorkerGroup, shard}
        IO.puts("Joining :pg process group #{inspect(group)}...")
        :pg.join(group, self())
        IO.puts("EventWorker for shard #{shard} started and registered as #{inspect(via_tuple(shard))}")
        ets_tables = %{}
        schedule_batch_broadcast()
        schedule_cleanup()
        {:ok, %{shard: shard, ets_tables: ets_tables, updates: %{}, last_updated: %{}}}
      catch
        type, reason ->
          IO.puts("Failed to initialize EventWorker for shard #{shard} with #{type}: #{inspect(reason)}")
          stacktrace = System.stacktrace()
          IO.puts("Stacktrace: #{inspect(stacktrace)}")
          {:stop, reason}
      end
    end
  
    # Handle incoming messages (avl or updt) and store them in the appropriate ETS table
    def handle_cast({:process_message, event_id, message}, state) do
      try do
        start_time = System.monotonic_time()
        %{shard: shard, ets_tables: ets_tables, updates: pending_updates, last_updated: last_updated} = state
  
        # Determine the sport from the message
        sport = Map.get(message, "sport", "unknown")
        # Get or create the ETS table for this sport
        ets_table = ensure_ets_table(sport, shard, ets_tables)
  
        # Process the message
        case message do
          %{"mt" => "avl"} ->
            event = Enum.find(message["evts"], fn e -> e["id"] == event_id end)
            if event do
              :ets.insert(ets_table, {event_id, event})
            end
  
          %{"mt" => "updt"} ->
            case :ets.lookup(ets_table, event_id) do
              [{^event_id, existing_event}] ->
                updated_event = Map.merge(existing_event, message)
                :ets.insert(ets_table, {event_id, updated_event})
              [] ->
                :ets.insert(ets_table, {event_id, message})
            end
        end
  
        # Update the last_updated timestamp for this event
        current_time = System.monotonic_time(:millisecond)
        updated_last_updated = Map.put(last_updated, {sport, event_id}, current_time)
  
        # Emit telemetry event
        duration = System.monotonic_time() - start_time
        :telemetry.execute([:sports_info, :message_processed], %{duration: duration}, %{event_id: event_id})
  
        # Retrieve the updated event and add it to pending updates
        updated_event = :ets.lookup(ets_table, event_id) |> List.first() |> elem(1)
        new_pending_updates = Map.put(pending_updates, {sport, event_id}, updated_event)
  
        new_state = %{
          state |
          ets_tables: Map.put(ets_tables, sport, ets_table),
          updates: new_pending_updates,
          last_updated: updated_last_updated
        }
        {:noreply, new_state}
      catch
        type, reason ->
          IO.puts("EventWorker for shard #{state.shard} crashed while processing message for event #{event_id} with #{type}: #{inspect(reason)}")
          stacktrace = System.stacktrace()
          IO.puts("Stacktrace: #{inspect(stacktrace)}")
          {:noreply, state}  # Continue running to avoid crashing the process
      end
    end
  
    # Handle periodic batch broadcast
    def handle_info(:broadcast_batch, state) do
      start_time = System.monotonic_time()
      %{updates: pending_updates} = state
  
      # Broadcast updates using sport-specific topics
      Enum.each(pending_updates, fn {{sport, event_id}, event} ->
        topic = "#{@pubsub_topic}:#{sport}"
        PubSub.broadcast(SportsInfo.PubSub, topic, {:event_update, event_id, event})
      end)
  
      # Emit telemetry event
      duration = System.monotonic_time() - start_time
      :telemetry.execute([:sports_info, :batch_broadcast], %{duration: duration}, %{count: map_size(pending_updates)})
  
      schedule_batch_broadcast()
      {:noreply, %{state | updates: %{}}}
    end
  
    # Handle periodic cleanup of stale events
    def handle_info(:cleanup, state) do
      %{ets_tables: ets_tables, last_updated: last_updated} = state
      current_time = System.monotonic_time(:millisecond)
  
      # Identify and remove stale events
      stale_entries = Enum.filter(last_updated, fn {_, timestamp} ->
        current_time - timestamp > @stale_threshold
      end)
  
      Enum.each(stale_entries, fn {{sport, event_id}, _} ->
        ets_table = Map.get(ets_tables, sport)
        if ets_table do
          :ets.delete(ets_table, event_id)
        end
      end)
  
      # Update last_updated by removing stale entries
      updated_last_updated = Map.drop(last_updated, Enum.map(stale_entries, fn {key, _} -> key end))
  
      schedule_cleanup()
      {:noreply, %{state | last_updated: updated_last_updated}}
    end
  
    # Return all events in this shard, optionally filtered by sport
    def handle_call({:get_events, sport}, _from, state) do
      %{ets_tables: ets_tables} = state
      events = if sport do
        ets_table = Map.get(ets_tables, sport, nil)
        if ets_table do
          :ets.tab2list(ets_table) |> Enum.map(fn {_, event} -> event end)
        else
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
  
    # Return a specific event from this shard
    def handle_call({:get_event, event_id}, _from, state) do
      %{ets_tables: ets_tables} = state
      # Search for the event across all sport-specific ETS tables
      event = Enum.reduce_while(ets_tables, nil, fn {sport, ets_table}, acc ->
        case :ets.lookup(ets_table, event_id) do
          [{^event_id, event}] -> {:halt, event}
          [] -> {:cont, acc}
        end
      end)
      {:reply, event, state}
    end
  
    # Helper Functions
  
    # Construct the registry tuple for naming the EventWorker process
    defp via_tuple(shard) do
      {:global, {:event_worker, shard}}
    end
  
    # Calculate the shard for an event based on its ID
    defp shard_for_event(event_id) do
      :erlang.phash2(event_id, @num_shards)
    end
  
    # Schedule the next batch broadcast
    defp schedule_batch_broadcast do
      Process.send_after(self(), :broadcast_batch, @batch_interval)
    end
  
    # Schedule the next cleanup
    defp schedule_cleanup do
      Process.send_after(self(), :cleanup, @cleanup_interval)
    end
  
    # Ensure an ETS table exists for the given sport
    defp ensure_ets_table(sport, shard, ets_tables) do
      case Map.get(ets_tables, sport) do
        nil ->
          # Create a new ETS table for this sport with optimized settings
          table_name = :"events_shard_#{shard}_#{sport}"
          ets_table = :ets.new(table_name, [:set, :public, :named_table, :compressed, read_concurrency: true, write_concurrency: true])
          ets_table
        table ->
          table
      end
    end
  end