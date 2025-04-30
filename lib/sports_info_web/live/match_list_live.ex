defmodule SportsInfoWeb.MatchListLive do
    use SportsInfoWeb, :live_view
  
    @sports ["soccer", "basketball", "tennis", "baseball", "amfootball", "hockey", "volleyball"]
  
    @impl true
    def mount(_params, _session, socket) do
      # Subscribe to the default sport's updates
      sport = "soccer"
      Phoenix.PubSub.subscribe(SportsInfo.PubSub, "sports:events:#{sport}")
  
      # Initial state
      socket = assign(socket, %{
        sport: sport,
        sports: @sports,
        events: [],
        leagues: %{}
      })
  
      # Fetch initial events
      events = SportsInfo.EventData.get_all_events(sport)
      leagues = group_events_by_league(events)
  
      {:ok, assign(socket, events: events, leagues: leagues)}
    end
  
    @impl true
    def handle_event("select_sport", %{"sport" => sport}, socket) do
      # Unsubscribe from the previous sport's topic
      Phoenix.PubSub.unsubscribe(SportsInfo.PubSub, "sports:events:#{socket.assigns.sport}")
      # Subscribe to the new sport's topic
      Phoenix.PubSub.subscribe(SportsInfo.PubSub, "sports:events:#{sport}")
  
      # Fetch events for the new sport
      events = SportsInfo.EventData.get_all_events(sport)
      leagues = group_events_by_league(events)
  
      {:noreply, assign(socket, sport: sport, events: events, leagues: leagues)}
    end
  
    @impl true
    def handle_info({:event_update, event_id, event}, socket) do
      # Check if the event belongs to the current sport
      if event["sport"] == socket.assigns.sport do
        # Update the events list
        events = update_event(socket.assigns.events, event_id, event)
        leagues = group_events_by_league(events)
        {:noreply, assign(socket, events: events, leagues: leagues)}
      else
        {:noreply, socket}
      end
    end
  
    defp update_event(events, event_id, new_event) do
      case Enum.find_index(events, fn e -> e["id"] == event_id end) do
        nil ->
          # Add new event
          [new_event | events]
        index ->
          # Update existing event
          List.replace_at(events, index, new_event)
      end
    end
  
    defp group_events_by_league(events) do
      events
      |> Enum.group_by(fn event -> event["cmp_name"] end)
      |> Enum.into(%{}, fn {league, league_events} ->
        {league, Enum.sort_by(league_events, & &1["et"], :asc)}
      end)
    end
  
    @impl true
    def render(assigns) do
      ~H"""
      <div>
        <!-- Sport Selection Tabs -->
        <div class="flex space-x-2 mb-4 overflow-x-auto">
          <%= for sport <- @sports do %>
            <button
              phx-click="select_sport"
              phx-value-sport={sport}
              class={"px-4 py-2 rounded #{if @sport == sport, do: "bg-gray-600", else: "bg-gray-700 hover:bg-gray-600"}"}
            >
              <%= String.capitalize(sport) %>
            </button>
          <% end %>
        </div>
  
        <!-- Matches Grouped by League -->
        <div>
          <%= for {league, league_events} <- @leagues do %>
            <div class="mb-6">
              <h2 class="text-lg font-bold mb-2 text-teal-400"><%= league %></h2>
              <div class="grid grid-cols-4 gap-2 font-bold text-center text-sm bg-gray-800 p-2 rounded-t">
                <div>Time</div>
                <div>Teams</div>
                <div>Home</div>
                <div>Tie</div>
                <div>Away</div>
              </div>
              <div id={"league-#{league}"} phx-update="append">
                <%= for event <- league_events do %>
                  <div id={"event-#{event["id"]}"} class="grid grid-cols-4 gap-2 text-center text-sm bg-gray-700 p-2">
                    <div>
                      <%= format_time(event["et"]) %>
                    </div>
                    <div class="flex justify-between">
                      <span><%= event["t1"]["n"] %></span>
                      <span class="mx-2">-</span>
                      <span><%= event["t2"]["n"] %></span>
                    </div>
                    <%= case get_odds(event, 1777) do %>
                      <% %{"1" => home, "X" => tie, "2" => away} -> %>
                        <div><%= home %></div>
                        <div><%= tie %></div>
                        <div><%= away %></div>
                      <% _ -> %>
                        <div>-</div>
                        <div>-</div>
                        <div>-</div>
                    <% end %>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </div>
      """
    end
  
    defp format_time(nil), do: "00:00"
    defp format_time(seconds) do
      minutes = div(seconds, 60)
      seconds = rem(seconds, 60)
      String.pad_leading(to_string(minutes), 2, "0") <> ":" <> String.pad_leading(to_string(seconds), 2, "0")
    end
  
    defp get_odds(event, market_id) do
      case event["odds"] do
        nil -> nil
        odds ->
          case Enum.find(odds, fn o -> o["id"] == market_id end) do
            nil -> nil
            %{"o" => odds_list} ->
              odds_list
              |> Enum.map(fn %{"n" => name, "v" => value} -> {name, value} end)
              |> Map.new()
            _ -> nil
          end
      end
    end
  end