defmodule SportsInfo.TokenFetcher do
    @moduledoc """
    Fetches and caches the JWT token required for Goalserve WebSocket API authentication.
    """
  
    use GenServer
  
    # Define the child specification (already provided by use GenServer, but made explicit)
    def child_spec(_opts) do
      %{
        id: __MODULE__,
        start: {__MODULE__, :start_link, [[]]},
        type: :worker,
        restart: :permanent,
        shutdown: 500
      }
    end
  
    @token_url "http://152.89.28.69:8765/api/v1/auth/gettoken"
    @api_key "d306a694785d45065cb608dada5f9a88"
    @refresh_interval :timer.hours(1)
  
    def start_link(_opts \\ []) do
      :hackney_pool.start_pool(:token_fetcher_pool, [timeout: 5_000, max_connections: 10])
      GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
    end
  
    def get_token do
      GenServer.call(__MODULE__, :get_token)
    end
  
    def init(:ok) do
      {:ok, token} = fetch_token()
      schedule_token_refresh()
      {:ok, %{token: token}}
    end
  
    def handle_call(:get_token, _from, state) do
      {:reply, state.token, state}
    end
  
    def handle_info(:refresh_token, state) do
      case fetch_token() do
        {:ok, new_token} ->
          schedule_token_refresh()
          {:noreply, %{state | token: new_token}}
        {:error, reason} ->
          IO.puts("Failed to refresh token: #{inspect(reason)}")
          Process.send_after(self(), :refresh_token, 5_000)
          {:noreply, state}
      end
    end
  
    defp fetch_token do
      headers = [{"Content-Type", "application/json"}]
      body = Jason.encode!(%{"apiKey" => @api_key})
  
      case HTTPoison.post(@token_url, body, headers, hackney: [pool: :token_fetcher_pool]) do
        {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
          case Jason.decode(response_body) do
            {:ok, %{"token" => token}} ->
              IO.puts("Successfully fetched Goalserve API token")
              {:ok, token}
            {:error, reason} ->
              {:error, "Failed to decode token response: #{inspect(reason)}"}
          end
        {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
          {:error, "Token request failed with status #{status}: #{body}"}
        {:error, reason} ->
          {:error, "Token request failed: #{inspect(reason)}"}
      end
    end
  
    defp schedule_token_refresh do
      Process.send_after(self(), :refresh_token, @refresh_interval)
    end
  end