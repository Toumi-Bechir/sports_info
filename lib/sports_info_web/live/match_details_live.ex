defmodule SportsInfoWeb.MatchDetailsLive do
    use SportsInfoWeb, :live_view
  
    @impl true
    def mount(%{"id" => event_id}, _session, socket) do
      # Fetch the event
      event = SportsInfo.EventData.get_event(event_id)
  
      if event do
        # Subscribe to updates for this event's sport
        Phoenix.PubSub.subscribe(SportsInfo.PubSub, "sports:events:#{event["sport"]}")
  
        socket = assign(socket, %{
          event_id: event_id,
          event: event,
          markets: extract_markets(event)
        })
  
        {:ok, socket}
      else
        {:ok, redirect(socket, to: "/")}
      end
    end
  
    @impl true
    def handle_info({:event_update, event_id, event}, socket) do
      if event_id == socket.assigns.event_id do
        markets = extract_markets(event)
        {:noreply, assign(socket, event: event, markets: markets)}
      else
        {:noreply, socket}
      end
    end
  
    defp extract_markets(event) do
      case event["odds"] do
        nil -> %{}
        odds ->
          odds
          |> Enum.map(fn %{"id" => id, "o" => odds_list} = market ->
            {id, %{
              name: market_name(id),
              odds: Enum.map(odds_list, fn o -> {o["n"], o["v"]} end) |> Map.new()
            }}
          end)
          |> Map.new()
      end
    end
  
    defp market_name(50246), do: "Money Line 3-way"
    defp market_name(10115), do: "Double Chance"
    defp market_name(10563), do: "2nd Goal"
    # Add more market names as needed
    defp market_name(id), do: "Market #{id}"
  
    @impl true
    def render(assigns) do
      ~H"""
      <div class="flex">
        <!-- Left Sidebar: List of Matches -->
        <aside class="w-48 bg-gray-800 p-2 hidden md:block">
          <div class="mb-4">
            <h2 class="text-lg font-bold text-teal-400">Matches</h2>
            <!-- Placeholder for match list -->
            <div class="text-sm">
              <div class="bg-gray-700 p-2 mb-1">Match 1 - 0:0</div>
              <div class="bg-gray-700 p-2 mb-1">Match 2 - 1:1</div>
            </div>
          </div>
        </aside>
  
        <!-- Main Content: Match Details -->
        <main class="flex-1 p-4">
          <!-- Header with Teams and Score -->
          <div class="bg-gray-800 p-4 rounded mb-4">
            <h1 class="text-xl font-bold">
              <%= @event["t1"]["n"] %> <%= get_score(@event, "a", 0) %> - <%= get_score(@event, "a", 1) %> <%= @event["t2"]["n"] %>
            </h1>
            <div class="text-sm text-gray-400"><%= format_time(@event["et"]) %></div>
          </div>
  
          <!-- Tabs for Markets -->
          <div class="flex space-x-2 mb-4 overflow-x-auto">
            <button class="px-4 py-2 bg-gray-600 rounded">ALL</button>
            <button class="px-4 py-2 bg-gray-700 rounded hover:bg-gray-600">Same Game Parlay</button>
            <button class="px-4 py-2 bg-gray-700 rounded hover:bg-gray-600">Flash Bets</button>
            <button class="px-4 py-2 bg-gray-700 rounded hover:bg-gray-600">Asian Lines</button>
            <button class="px-4 py-2 bg-gray-700 rounded hover:bg-gray-600">Corners/Card</button>
          </div>
  
          <!-- Markets -->
          <div>
            <%= for {market_id, market} <- @markets do %>
              <div class="mb-4">
                <h2 class="text-lg font-bold text-teal-400"><%= market.name %></h2>
                <div class="grid grid-cols-3 gap-2 text-center bg-gray-700 p-2 rounded">
                  <%= for {name, value} <- market.odds do %>
                    <div class="p-2 bg-gray-600 rounded">
                      <div class="text-sm"><%= name %></div>
                      <div class="font-bold"><%= value %></div>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        </main>
  
        <!-- Right Sidebar: Tracker and Stats -->
        <aside class="w-64 bg-gray-800 p-2 hidden lg:block">
          <!-- Tracker Placeholder -->
          <div class="bg-gray-700 p-2 mb-4 rounded">
            <h2 class="text-lg font-bold text-teal-400">Tracker</h2>
            <div class="h-32 bg-gray-600 rounded">Tracker Placeholder</div>
          </div>
  
          <!-- Stats Placeholder -->
          <div class="bg-gray-700 p-2 rounded">
            <h2 class="text-lg font-bold text-teal-400">Stats</h2>
            <div class="text-sm">
              <div>Dangerous Attacks: 69 - 52</div>
              <div>Shots On Target: 5 - 1</div>
            </div>
          </div>
        </aside>
      </div>
      """
    end
  
    defp format_time(nil), do: "00:00"
    defp format_time(seconds) do
      minutes = div(seconds, 60)
      seconds = rem(seconds, 60)
      String.pad_leading(to_string(minutes), 2, "0") <> ":" <> String.pad_leading(to_string(seconds), 2, "0")
    end
  
    defp get_score(event, stat_key, team_index) do
      case event["stats"] do
        nil -> 0
        stats ->
          case stats[stat_key] do
            nil -> 0
            scores -> Enum.at(scores, team_index, 0)
          end
      end
    end
  end