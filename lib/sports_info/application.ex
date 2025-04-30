defmodule SportsInfo.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    # Start the :pg process group system
    :pg.start_link()

    children = [
      {SportsInfo.Telemetry, []},
      {Phoenix.PubSub, [name: SportsInfo.PubSub]},
      {SportsInfo.EventWorkerSupervisor, []},
      #{SportsInfo.TokenFetcher, []},
      {SportsInfo.WebSocketRegistry, []},
      {SportsInfo.WebSocketSupervisor, []},
      {SportsInfo.MessageProducer, []},
      {SportsInfo.MessageConsumer, []},
      {SportsInfo.MessageConsumer, []},
      {SportsInfoWeb.Endpoint, []}
    ]

    opts = [strategy: :one_for_one, name: SportsInfo.Supervisor]
    {:ok, supervisor} = Supervisor.start_link(children, opts)

    # Start EventWorker processes synchronously
    start_event_workers()

    {:ok, supervisor}
  end

  def config_change(changed, _new, removed) do
    SportsInfoWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Start all EventWorker processes synchronously
  defp start_event_workers do
    # Create an ETS table to track started workers
    if :ets.info(:event_worker_status) != :undefined do
      :ets.delete(:event_worker_status)
    end
    :ets.new(:event_worker_status, [:set, :public, :named_table])
    :ets.insert(:event_worker_status, {:started_count, 0})

    Enum.each(0..15, fn shard ->
      case SportsInfo.EventWorkerSupervisor.start_worker(shard) do
        {:ok, _pid} ->
          :ets.update_counter(:event_worker_status, :started_count, {2, 1})
          IO.puts("Successfully started EventWorker for shard #{shard}")
        {:error, reason} ->
          IO.puts("Failed to start EventWorker for shard #{shard}: #{inspect(reason)}")
          raise "Failed to start EventWorker for shard #{shard}: #{inspect(reason)}"
      end
    end)

    IO.puts("All EventWorker processes started")
  end
end