defmodule SportsInfo.MessageConsumer do
  use GenStage

  def child_spec(_opts) do
    %{
      id: {__MODULE__, :erlang.unique_integer()},
      start: {__MODULE__, :start_link, [[]]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  def start_link(_opts \\ []) do
    GenStage.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    {:consumer, :ok, subscribe_to: [{SportsInfo.MessageProducer, max_demand: 50, min_demand: 10}]}
  end

  def handle_events(events, _from, state) do
    Enum.each(events, fn {event_id, message} ->
      #IO.puts("MessageConsumer: Processing message for event #{event_id}: ")#{inspect(message)}
      SportsInfo.EventWorker.process_message(event_id, message)
    end)
    {:noreply, [], state}
  end
end