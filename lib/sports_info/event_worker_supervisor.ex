defmodule SportsInfo.EventWorkerSupervisor do
    use DynamicSupervisor
  
    # Number of shards (must match SportsInfo.EventWorker)
    @num_shards 16
  
    # Define the child specification
    def child_spec(_opts) do
      %{
        id: __MODULE__,
        start: {__MODULE__, :start_link, [[]]},
        type: :supervisor,
        restart: :permanent,
        shutdown: 500
      }
    end
  
    # Start the DynamicSupervisor
    def start_link(_arg \\ []) do
      DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
    end
  
    # Initialize the DynamicSupervisor
    @impl true
    def init(:ok) do
      DynamicSupervisor.init(strategy: :one_for_one)
    end
  
    # Start a new EventWorker for a specific shard
    def start_worker(shard) do
      spec = {SportsInfo.EventWorker, shard}
      DynamicSupervisor.start_child(__MODULE__, spec)
    end
  
    # Public API to check if all workers are started
    def workers_ready? do
      case :ets.lookup(:event_worker_status, :started_count) do
        [{:started_count, count}] -> count == @num_shards
        [] -> false
      end
    end
  end