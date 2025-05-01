defmodule SportsInfo.WebSocketSupervisor do
    use DynamicSupervisor
  
    # List of sports supported by Goalserve (from documentation)
    @sports ["soccer", "basket", "tennis", "baseball", "amfootball", "hockey", "volleyball"]
  
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
      # Initialize the supervisor
      result = DynamicSupervisor.init(strategy: :one_for_one)
      # Start the WebSocket clients in a separate task to avoid blocking init/1
      Task.start(fn ->
        Enum.each(@sports, &start_websocket_client/1)
      end)
      result
    end
  
    # Start a WebSocket client for a specific sport
    def start_websocket_client(sport) do
      spec = {SportsInfo.WebSocketClient, sport}
      DynamicSupervisor.start_child(__MODULE__, spec)
    end
  end