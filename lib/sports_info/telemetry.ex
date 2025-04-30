defmodule SportsInfo.Telemetry do
    use GenServer
  
    # Define the child specification
    def child_spec(_opts) do
      %{
        id: __MODULE__,
        start: {__MODULE__, :start_link, [[]]},
        type: :worker,
        restart: :permanent,
        shutdown: 500
      }
    end
  
    def start_link(_opts \\ []) do
      GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
    end
  
    def init(:ok) do
      events = [
        [:sports_info, :message_processed],
        [:sports_info, :batch_broadcast],
        [:sports_info, :system_health]
      ]
  
      :telemetry.attach_many("sports-info-metrics", events, &handle_event/4, nil)
      schedule_system_health_check()
      {:ok, %{}}
    end
  
    def handle_event([:sports_info, :message_processed], measurements, metadata, _config) do
      IO.inspect("Message Processed: #{inspect(metadata.event_id)} in #{measurements.duration} microseconds")
    end
  
    def handle_event([:sports_info, :batch_broadcast], measurements, metadata, _config) do
      IO.inspect("Batch Broadcast: #{metadata.count} updates in #{measurements.duration} microseconds")
    end
  
    def handle_event([:sports_info, :system_health], measurements, _metadata, _config) do
      # Format the ets_tables list into a string
      ets_tables_str = measurements.ets_tables
                       |> Enum.map(fn {table, size, memory} ->
                         "#{inspect(table)}: #{size} entries, #{memory} words"
                       end)
                       |> Enum.join("\n")
      IO.puts("System Health - Memory: #{measurements.memory_mb} MB\nETS Tables:\n#{ets_tables_str}")
    end
  
    defp schedule_system_health_check do
      Process.send_after(self(), :system_health_check, :timer.seconds(30))
    end
  
    def handle_info(:system_health_check, state) do
      memory_bytes = :erlang.memory(:total)
      memory_mb = memory_bytes / (1024 * 1024)
  
      ets_tables = :ets.all()
      ets_info = Enum.map(ets_tables, fn table ->
        info = :ets.info(table)
        {table, Keyword.get(info, :size, 0), Keyword.get(info, :memory, 0)}
      end)
  
      :telemetry.execute([:sports_info, :system_health], %{
        memory_mb: memory_mb,
        ets_tables: ets_info
      }, %{})
  
      schedule_system_health_check()
      {:noreply, state}
    end
  end