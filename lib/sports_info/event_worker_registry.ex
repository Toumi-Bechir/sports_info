defmodule SportsInfo.EventWorkerRegistry do
    # Start the Registry for mapping shard IDs to EventWorker processes
    def start_link do
      Registry.start_link(keys: :unique, name: __MODULE__)
    end
  end