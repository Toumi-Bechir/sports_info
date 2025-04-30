defmodule SportsInfo.WebSocketClient do
  use WebSockex

  # Base URL for the Goalserve WebSocket API
  @base_websocket_url "ws://152.89.28.69:8765/ws"

  # Client API

  # Start the WebSocket client for a specific sport
  def start_link(sport) do
    # Fetch a fresh token
    #token = SportsInfo.TokenFetcher.get_token()
    token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1biI6InRiZWNoaXIiLCJuYmYiOjE3NDYwMzQyMTIsImV4cCI6MTc0NjAzNzgxMiwiaWF0IjoxNzQ2MDM0MjEyfQ.yLxCQckNfEzY6PqFP6LsfsXmibsYphMAFqMsg4RhZh8"
    # Log the token for debugging
    IO.puts("Using token for sport #{sport}: #{token}")

    # Construct the WebSocket URL with the token as a query parameter
    websocket_url = "#{@base_websocket_url}/#{sport}?tkn=#{token}"
    IO.inspect websocket_url

    # Remove the Authorization header to test token in URL only
    headers = []

    IO.puts("Attempting to connect to WebSocket for sport #{sport}: #{websocket_url}")
    case WebSockex.start_link(websocket_url, __MODULE__, %{sport: sport}, extra_headers: headers, name: via_tuple(sport)) do
      {:ok, pid} ->
        {:ok, pid}
      {:error, reason} ->
        IO.puts("Failed to start WebSocketClient for sport #{sport}: #{inspect(reason)}")
        {:error, reason}
    end
  end


  # WebSockex Callbacks

  # Handle successful WebSocket connection
  def handle_connect(_conn, state) do
    IO.puts("WebSocket connected for sport: #{state.sport}")
    {:ok, state}
  end

  # Handle incoming WebSocket text frames (JSON messages)
  def handle_frame({:text, msg}, state) do
    case Jason.decode(msg) do
      {:ok, message} ->
        message_with_sport = Map.put(message, "sport", state.sport)
        handle_message(message_with_sport)
        {:ok, state}
      {:error, reason} ->
        IO.puts("Failed to decode WebSocket message for sport #{state.sport}: #{inspect(reason)}")
        {:ok, state}
    end
  end

  # Handle unexpected binary frames
  def handle_frame({:binary, _msg}, state) do
    IO.puts("Received unexpected binary frame for sport: #{state.sport}")
    {:ok, state}
  end

  # Handle WebSocket disconnection and log the reason
  def handle_disconnect(%{reason: reason}, state) do
    IO.puts("WebSocket disconnected for sport #{state.sport}: #{inspect(reason)}")
    {:ok, state}
  end

  # Handle unexpected messages
  def handle_info(message, state) do
    IO.puts("Received unexpected message for sport #{state.sport}: #{inspect(message)}")
    {:ok, state}
  end

  # Process incoming messages and distribute to MessageProducer
  defp handle_message(%{"mt" => "avl", "evts" => events, "sport" => sport} = _message) do
    Enum.each(events, fn event ->
      event_id = event["id"]
      event_with_sport = Map.put(event, "sport", sport)
      SportsInfo.MessageProducer.add_message(event_id, %{"mt" => "avl", "evts" => [event_with_sport]})
    end)
  end

  defp handle_message(%{"mt" => "updt", "id" => event_id, "sport" => sport} = message) do
    IO.puts("Received update for event #{event_id} in sport #{sport}")
    message_with_sport = Map.put(message, "sport", sport)
    SportsInfo.MessageProducer.add_message(event_id, message_with_sport)
  end

  defp handle_message(message) do
    IO.puts("Received unknown message type: #{inspect(message)}")
    :ok
  end

  # Helper Functions

  # Construct the registry tuple for naming the WebSocket client process
  defp via_tuple(sport) do
    {:via, Registry, {SportsInfo.WebSocketRegistry, sport}}
  end
end