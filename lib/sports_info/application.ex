defmodule SportsInfo.Application do
  @moduledoc false
  use Application

  @num_shards 16

  @impl true
  def start(_type, _args) do
    :pg.start_link()

    children = [
      SportsInfoWeb.Endpoint,
      SportsInfoWeb.Telemetry,
      {Phoenix.PubSub, name: SportsInfo.PubSub},
      {Registry, keys: :unique, name: SportsInfo.WebSocketRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: SportsInfo.WebSocketSupervisor},
      SportsInfo.MessageProducer,
      {DynamicSupervisor, strategy: :one_for_one, name: SportsInfo.MessageConsumerSupervisor},
      {DynamicSupervisor, strategy: :one_for_one, name: SportsInfo.EventWorkerSupervisor},
      #SportsInfo.TokenFetcher
    ]

    opts = [strategy: :one_for_one, name: SportsInfo.Supervisor]
    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        start_websocket_clients()
        start_message_consumers()
        start_event_workers()
        {:ok, pid}
      error ->
        error
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    SportsInfoWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp start_websocket_clients do
    sports = ["soccer", "basket", "tennis", "baseball", "amfootball", "hockey", "volleyball"]
    Enum.each(sports, fn sport ->
      case SportsInfo.WebSocketSupervisor.start_websocket_client(sport) do
        {:ok, _pid} -> :ok
        {:error, reason} -> raise "Failed to start WebSocketClient for sport #{sport}: #{inspect(reason)}"
      end
    end)
  end

  defp start_message_consumers do
    num_consumers = 10
    Enum.each(1..num_consumers, fn _ ->
      case DynamicSupervisor.start_child(SportsInfo.MessageConsumerSupervisor, SportsInfo.MessageConsumer) do
        {:ok, _pid} -> :ok
        {:error, reason} -> raise "Failed to start MessageConsumer: #{inspect(reason)}"
      end
    end)
  end

  defp start_event_workers do
    {:ok, pid} = :pg.start_link(SportsInfo.EventWorkerGroup)

    Enum.each(0..(@num_shards - 1), fn shard ->
      case SportsInfo.EventWorkerSupervisor.start_worker(shard) do
        {:ok, _pid} ->
          IO.puts("EventWorker for shard #{shard} started successfully")
          :ok
        {:error, {:already_started, pid}} ->
          IO.puts("EventWorker for shard #{shard} already started with PID #{inspect(pid)}")
          :ok
        {:error, reason} ->
          raise "Failed to start EventWorker for shard #{shard}: #{inspect(reason)}"
      end
    end)
  end
end