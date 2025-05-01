defmodule SportsInfo.WebSocketClient do
  use WebSockex

  @base_websocket_url "ws://152.89.28.69:8765"

  def start_link(sport, retries \\ 3) do
    #token = SportsInfo.TokenFetcher.get_token()
    token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1biI6InRiZWNoaXIiLCJuYmYiOjE3NDYxMjQxOTQsImV4cCI6MTc0NjEyNzc5NCwiaWF0IjoxNzQ2MTI0MTk0fQ.9OgSMADnNnK5bcwI3ErwYPBRPefB3Qr18qMkCfosd1E"
    unless token do
      IO.puts("No token available for sport #{sport}. Cannot start WebSocketClient.")
      {:error, :no_token}
    else
      IO.puts("Using token for sport #{sport}: #{token}")
      sport = if sport == "basketball", do: "basket", else: sport
      websocket_url = "#{@base_websocket_url}/ws/#{sport}?tkn=#{token}"
      headers = []

      IO.puts("Attempting to connect to WebSocket for sport #{sport}: #{websocket_url}")
      case WebSockex.start_link(websocket_url, __MODULE__, %{sport: sport}, extra_headers: headers, name: via_tuple(sport)) do
        {:ok, pid} ->
          {:ok, pid}
        {:error, %WebSockex.RequestError{code: 401} = reason} when retries > 0 ->
          IO.puts("Failed to start WebSocketClient for sport #{sport}: #{inspect(reason)}. Retrying (#{retries} attempts left)...")
          Process.sleep(5_000)
          start_link(sport, retries - 1)
        {:error, reason} ->
          IO.puts("Failed to start WebSocketClient for sport #{sport}: #{inspect(reason)}")
          try_alternative_connection(sport, token, retries)
      end
    end
  end

  defp try_alternative_connection(sport, token, retries) do
    sport = if sport == "basketball", do: "basket", else: sport
    websocket_url = "#{@base_websocket_url}/#{sport}"
    headers = [
      {"Authorization", "Bearer #{token}"}
    ]

    IO.puts("Retrying with alternative method for sport #{sport}: #{websocket_url} (Authorization header)")
    case WebSockex.start_link(websocket_url, __MODULE__, %{sport: sport}, extra_headers: headers, name: via_tuple(sport)) do
      {:ok, pid} ->
        {:ok, pid}
      {:error, %WebSockex.RequestError{code: 401} = reason} when retries > 0 ->
        IO.puts("Failed to start WebSocketClient for sport #{sport}: #{inspect(reason)}. Retrying (#{retries} attempts left)...")
        Process.sleep(5_000)
        start_link(sport, retries - 1)
      {:error, reason} ->
        IO.puts("Failed to start WebSocketClient for sport #{sport}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def handle_connect(_conn, state) do
    IO.puts("WebSocket connected for sport: #{state.sport}")
    schedule_ping()
    {:ok, state}
  end

  def handle_frame({:text, msg}, state) do
    #IO.puts("Received WebSocket message for sport #{state.sport}: ")#{msg}
    case Jason.decode(msg) do
      {:ok, message} ->
        # Use the "sp" field from the message if available, otherwise fall back to state.sport
        sport = Map.get(message, "sp")
        #IO.puts("Sport from message +++++++++++++++++++++ +++++++++++++++++ +++++++++++++++  ++++++++++++++++++++ : #{inspect(sport)}") 
        message_with_sport = Map.put(message, "sport", sport)
        handle_message(message_with_sport)
        {:ok, state}
      {:error, reason} ->
        IO.puts("Failed to decode WebSocket message for sport #{state.sport}: #{inspect(reason)}")
        {:ok, state}
    end
  end

  def handle_frame({:binary, _msg}, state) do
    IO.puts("Received unexpected binary frame for sport: #{state.sport}")
    {:ok, state}
  end

  def handle_disconnect(%{reason: reason}, state) do
    IO.puts("WebSocket disconnected for sport #{state.sport}: #{inspect(reason)}")
    {:reconnect, state}
  end

  def handle_info(:ping, state) do
    IO.puts("Sending ping for sport #{state.sport}")
    schedule_ping()
    {:ok, state}
  end

  def handle_info(message, state) do
    IO.puts("Received unexpected message for sport #{state.sport}: #{inspect(message)}")
    {:ok, state}
  end

  defp handle_message(%{"mt" => "avl", "evts" => events, "sport" => sport} = _message) do
    IO.puts("Processing avl message with #{length(events)} events for sport #{sport}")
    Enum.each(events, fn event ->
      event_id = event["id"]
      event_with_sport = Map.put(event, "sport", sport)
      SportsInfo.MessageProducer.add_message(event_id, %{"mt" => "avl", "evts" => [event_with_sport]})
    end)
  end

  defp handle_message(%{"mt" => "updt", "id" => event_id, "sport" => sport} = message) do
    #IO.puts("Processing updt message for event #{event_id} in sport #{sport}")
    message_with_sport = Map.put(message, "sport", sport)
    SportsInfo.MessageProducer.add_message(event_id, message_with_sport)
  end

  defp handle_message(message) do
    #IO.puts("Received unknown message type: #{inspect(message)}")
    :ok
  end

  defp via_tuple(sport) do
    {:via, Registry, {SportsInfo.WebSocketRegistry, sport}}
  end

  defp schedule_ping do
    Process.send_after(self(), :ping, 30_000)
  end
end