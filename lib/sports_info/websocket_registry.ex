defmodule SportsInfo.WebSocketRegistry do
    # Define the child specification for this module
    def child_spec(_opts) do
      %{
        id: __MODULE__,
        start: {__MODULE__, :start_link, [[]]},
        type: :worker,
        restart: :permanent,
        shutdown: 500
      }
    end
  
    # Start the Registry for mapping sports to WebSocketClient processes
    def start_link(_opts \\ []) do
      Registry.start_link(keys: :unique, name: __MODULE__)
    end
  end