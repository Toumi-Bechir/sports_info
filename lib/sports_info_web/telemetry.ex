defmodule SportsInfoWeb.Telemetry do
  @moduledoc """
  Telemetry module for Phoenix-specific metrics.
  """

  use Supervisor
  import Telemetry.Metrics

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

  # Start the telemetry supervisor
  def start_link(_opts \\ []) do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    children = [
      # Telemetry poller to periodically emit metrics
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # Define metrics to be emitted
  def metrics do
    [
      # Phoenix Metrics
      last_value("phoenix.endpoint.stop.duration", unit: {:native, :millisecond}),
      last_value("phoenix.router_dispatch.stop.duration", unit: {:native, :millisecond}),

      # VM Metrics
      last_value("vm.memory.total", unit: {:byte, :megabyte}),
      last_value("vm.total_run_queue_lengths.total"),
      last_value("vm.total_run_queue_lengths.cpu"),
      last_value("vm.total_run_queue_lengths.io")
    ]
  end

  # Define periodic measurements to be emitted by the telemetry poller
  defp periodic_measurements do
    [
      # VM metrics
      {__MODULE__, :dispatch_vm_metrics, []}
    ]
  end

  # Dispatch VM metrics periodically
  def dispatch_vm_metrics do
    :telemetry.execute([:vm, :memory], %{total: :erlang.memory(:total)}, %{})
    :telemetry.execute([:vm, :total_run_queue_lengths], %{
      total: :erlang.statistics(:total_run_queue_lengths),
      cpu: :erlang.statistics(:run_queue),
      io: :erlang.statistics(:total_run_queue_lengths) - :erlang.statistics(:run_queue)
    }, %{})
  end
end