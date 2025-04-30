defmodule SportsInfo.MessageProducer do
    use GenStage
  
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
  
    # Start the producer
    def start_link(_opts \\ []) do
      GenStage.start_link(__MODULE__, :ok, name: __MODULE__)
    end
  
    # Add a message to the producer's queue, but wait for workers to be ready
    def add_message(event_id, message) do
      # Wait until all EventWorker processes are ready
      unless SportsInfo.EventWorkerSupervisor.workers_ready?() do
        IO.puts("MessageProducer waiting for EventWorker processes to start before adding message for event #{event_id}...")
        Process.sleep(100)
        add_message(event_id, message)
      else
        GenStage.cast(__MODULE__, {:add_message, event_id, message})
      end
    end
  
    # Server Callbacks
  
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