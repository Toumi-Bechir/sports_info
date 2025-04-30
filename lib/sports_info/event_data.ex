defmodule SportsInfo.EventData do
    @num_shards 16
  
    # Retrieve all events across all shards, optionally filtered by sport
    def get_all_events(sport \\ nil) do
      # Wait until all EventWorker processes are ready
      wait_for_workers()
  
      0..(@num_shards - 1)
      |> Enum.flat_map(fn shard ->
        SportsInfo.EventWorker.get_events(shard, sport)
      end)
    end
  
    # Retrieve a specific event by ID
    def get_event(event_id) do
      # Wait until all EventWorker processes are ready
      wait_for_workers()
  
      shard = :erlang.phash2(event_id, @num_shards)
      SportsInfo.EventWorker.get_event(shard, event_id)
    end
  
    # Wait until all EventWorker processes are ready
    defp wait_for_workers do
      unless SportsInfo.EventWorkerSupervisor.workers_ready?() do
        IO.puts("Waiting for EventWorker processes to start...")
        Process.sleep(100)
        wait_for_workers()
      end
    end
  end