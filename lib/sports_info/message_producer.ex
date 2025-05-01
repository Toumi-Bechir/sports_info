defmodule SportsInfo.MessageProducer do
  use GenStage

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
    GenStage.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def add_message(event_id, message) do
    IO.puts("MessageProducer: Adding message for event #{event_id}: ")#{inspect(message)}
    GenStage.cast(__MODULE__, {:add_message, event_id, message})
  end

  def init(:ok) do
    {:producer, {:queue.new(), 0}}
  end

  def handle_cast({:add_message, event_id, message}, {queue, demand}) do
    new_queue = :queue.in({event_id, message}, queue)
    dispatch_events(new_queue, demand, [])
  end

  def handle_demand(incoming_demand, {queue, demand}) do
    dispatch_events(queue, incoming_demand + demand, [])
  end

  defp dispatch_events(queue, demand, events) do
    case {demand, :queue.out(queue)} do
      {0, _} ->
        {:noreply, events, {queue, demand}}
      {_, {:empty, _queue}} ->
        {:noreply, events, {queue, demand}}
      {d, {{:value, event}, new_queue}} ->
        dispatch_events(new_queue, d - 1, [event | events])
    end
  end
end