defmodule SportsInfoWeb.MatchListLive do
  use SportsInfoWeb, :live_view

  @sports ["soccer", "basket", "tennis", "baseball", "amfootball", "hockey", "volleyball"]
  @events_per_page 50
  @visible_events_limit 10
  @markets [
    {"1777", "Money Line 3-way"},
    {"50246", "Money Line 3-way (Alt)"},
    {"match_goals", "Match Goals"},
    {"asian_handicap", "Asian Handicap"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    IO.puts("MatchListLive: Mounting..............................................................................................................................................................")
    sport = "soccer"
    topic = "sports:events:#{sport}"
    IO.puts("MatchListLive: Subscribing to topic #{topic}")
    Phoenix.PubSub.subscribe(SportsInfo.PubSub, topic)

    socket = assign(socket, %{
      sport: sport,
      sports: @sports,
      events: [],
      leagues: %{},
      page: 1,
      total_events: 0,
      total_pages: 1,
      visible_events_by_league: %{},
      visible_event_ids_by_league: %{},
      collapsed_leagues: MapSet.new(),
      show_in_play_only: false,
      sort_by: "time",
      selected_market: "1777",
      favorite_matches: MapSet.new(),
      search_query: "",
      markets: @markets,
      loading: false,
      all_events_loaded: false
    })

    {events, total} = fetch_events(sport, 1, false, "time", "")
    leagues = group_events_by_league(events)

    visible_events_by_league = Enum.reduce(leagues, %{}, fn {league, league_events}, acc ->
      visible_events = Enum.take(league_events, @visible_events_limit)
      Map.put(acc, league, visible_events)
    end)

    socket = assign(socket, events: events, leagues: leagues, visible_events_by_league: visible_events_by_league, total_events: total, total_pages: max(1, div(total + @events_per_page - 1, @events_per_page)))

    if Enum.empty?(events) do
      schedule_initial_fetch()
    end

    {:ok, socket}
  end

  @impl true
  def handle_event("select_sport", %{"sport" => sport}, socket) do
    old_topic = "sports:events:#{socket.assigns.sport}"
    new_topic = "sports:events:#{sport}"
    IO.puts("MatchListLive: Unsubscribing from topic #{old_topic}")
    Phoenix.PubSub.unsubscribe(SportsInfo.PubSub, old_topic)
    IO.puts("MatchListLive: Subscribing to topic #{new_topic}")
    Phoenix.PubSub.subscribe(SportsInfo.PubSub, new_topic)

    {events, total} = fetch_events(sport, 1, socket.assigns.show_in_play_only, socket.assigns.sort_by, socket.assigns.search_query)
    leagues = group_events_by_league(events)

    visible_events_by_league = Enum.reduce(leagues, %{}, fn {league, league_events}, acc ->
      visible_events = Enum.take(league_events, @visible_events_limit)
      Map.put(acc, league, visible_events)
    end)

    socket = assign(socket, sport: sport, events: events, leagues: leagues, visible_events_by_league: visible_events_by_league, page: 1, total_events: total, total_pages: max(1, div(total + @events_per_page - 1, @events_per_page)), visible_event_ids_by_league: %{}, collapsed_leagues: MapSet.new())

    if Enum.empty?(events) do
      schedule_initial_fetch()
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("load_more", _, socket) do
    if socket.assigns.all_events_loaded do
      {:noreply, socket}
    else
      page = socket.assigns.page + 1
      {new_events, total} = fetch_events(socket.assigns.sport, page, socket.assigns.show_in_play_only, socket.assigns.sort_by, socket.assigns.search_query)
      events = socket.assigns.events ++ new_events
      leagues = group_events_by_league(events)

      visible_events_by_league = Enum.reduce(leagues, %{}, fn {league, league_events}, acc ->
        visible_events = Enum.take(league_events, @visible_events_limit)
        Map.put(acc, league, visible_events)
      end)

      all_events_loaded = length(events) >= total

      {:noreply, assign(socket, events: events, leagues: leagues, visible_events_by_league: visible_events_by_league, page: page, total_events: total, all_events_loaded: all_events_loaded)}
    end
  end

  @impl true
  def handle_event("update_visible_events", %{"league" => league, "visible_ids" => visible_ids}, socket) do
    IO.puts("handle_event: Updating visible events for league #{league} with IDs #{inspect(visible_ids)}")
    visible_event_ids = MapSet.new(visible_ids)
    league_events = socket.assigns.leagues[league] || []

    visible_events = league_events
                     |> Enum.filter(fn event -> MapSet.member?(visible_event_ids, event["id"]) end)
                     |> Enum.take(@visible_events_limit)

    visible_events_by_league = Map.put(socket.assigns.visible_events_by_league, league, visible_events)
    visible_event_ids_by_league = Map.put(socket.assigns.visible_event_ids_by_league, league, visible_event_ids)

    IO.puts("handle_event: Updated visible_event_ids_by_league: #{inspect(visible_event_ids_by_league)}")

    {:noreply, assign(socket, visible_events_by_league: visible_events_by_league, visible_event_ids_by_league: visible_event_ids_by_league)}
  end

  @impl true
  def handle_event("update_visible_events", %{"visible_ids" => visible_ids}, socket) do
    IO.puts("Received update_visible_events without league key: #{inspect(visible_ids)}")
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_league", %{"league" => league}, socket) do
    collapsed_leagues = if MapSet.member?(socket.assigns.collapsed_leagues, league) do
      MapSet.delete(socket.assigns.collapsed_leagues, league)
    else
      MapSet.put(socket.assigns.collapsed_leagues, league)
    end

    {:noreply, assign(socket, collapsed_leagues: collapsed_leagues)}
  end

  @impl true
  def handle_event("toggle_in_play", _, socket) do
    show_in_play_only = not socket.assigns.show_in_play_only
    {events, total} = fetch_events(socket.assigns.sport, 1, show_in_play_only, socket.assigns.sort_by, socket.assigns.search_query)
    leagues = group_events_by_league(events)

    visible_events_by_league = Enum.reduce(leagues, %{}, fn {league, league_events}, acc ->
      visible_events = Enum.take(league_events, @visible_events_limit)
      Map.put(acc, league, visible_events)
    end)

    socket = assign(socket, show_in_play_only: show_in_play_only, events: events, leagues: leagues, visible_events_by_league: visible_events_by_league, page: 1, total_events: total, total_pages: max(1, div(total + @events_per_page - 1, @events_per_page)), visible_event_ids_by_league: %{})

    if Enum.empty?(events) do
      schedule_initial_fetch()
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("sort_by", %{"sort" => sort_by}, socket) do
    {events, total} = fetch_events(socket.assigns.sport, 1, socket.assigns.show_in_play_only, sort_by, socket.assigns.search_query)
    leagues = group_events_by_league(events)

    visible_events_by_league = Enum.reduce(leagues, %{}, fn {league, league_events}, acc ->
      visible_events = Enum.take(league_events, @visible_events_limit)
      Map.put(acc, league, visible_events)
    end)

    socket = assign(socket, sort_by: sort_by, events: events, leagues: leagues, visible_events_by_league: visible_events_by_league, page: 1, total_events: total, total_pages: max(1, div(total + @events_per_page - 1, @events_per_page)), visible_event_ids_by_league: %{})

    if Enum.empty?(events) do
      schedule_initial_fetch()
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_market", %{"market" => market}, socket) do
    {:noreply, assign(socket, selected_market: market)}
  end

  @impl true
  def handle_event("toggle_favorite", %{"event_id" => event_id}, socket) do
    favorite_matches = if MapSet.member?(socket.assigns.favorite_matches, event_id) do
      MapSet.delete(socket.assigns.favorite_matches, event_id)
    else
      MapSet.put(socket.assigns.favorite_matches, event_id)
    end

    {:noreply, assign(socket, favorite_matches: favorite_matches)}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {events, total} = fetch_events(socket.assigns.sport, 1, socket.assigns.show_in_play_only, socket.assigns.sort_by, query)
    leagues = group_events_by_league(events)

    visible_events_by_league = Enum.reduce(leagues, %{}, fn {league, league_events}, acc ->
      visible_events = Enum.take(league_events, @visible_events_limit)
      Map.put(acc, league, visible_events)
    end)

    socket = assign(socket, search_query: query, events: events, leagues: leagues, visible_events_by_league: visible_events_by_league, page: 1, total_events: total, total_pages: max(1, div(total + @events_per_page - 1, @events_per_page)), visible_event_ids_by_league: %{})

    if Enum.empty?(events) do
      schedule_initial_fetch()
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:event_update, event_id, event}, socket) do
    #IO.puts("MatchListLive: Received event update for event #{event_id}, sport #{event["sport"]}, expected sport #{socket.assigns.sport}")
    #IO.puts("MatchListLive: Event details - cmp_name: #{event["cmp_name"]}, id: #{event_id}")
    if event["sport"] == socket.assigns.sport do
      #IO.puts("MatchListLive: Processing update for event #{event_id}: time=#{event["et"]}, score=#{inspect(Map.get(event, "stats", %{}))}")
      updated_events = update_event(socket.assigns.events, event_id, event)
      leagues = group_events_by_league(updated_events)

      league = event["cmp_name"] || "Unknown League"
      league_events = leagues[league] || []

      # Log the entire visible_event_ids_by_league for debugging
      #IO.puts("Handle_info: Current visible_event_ids_by_league: #{inspect(socket.assigns.visible_event_ids_by_league)}")

      # Retrieve the visible event IDs for the league
      visible_event_ids = Map.get(socket.assigns.visible_event_ids_by_league, league, MapSet.new())
      IO.puts("Handle_info: Visible event IDs for league #{league}: #{inspect(visible_event_ids)}")

      # Push the update to the client regardless of visibility; client will handle visibility
      #IO.puts("Handle_info: Pushing update to client for event #{event_id}")
      socket = push_event(socket, "update_event", %{id: event_id, data: event})

      # Update the assigns for consistency
      visible_events = league_events
                       |> Enum.filter(fn e -> MapSet.member?(visible_event_ids, e["id"]) end)
                       |> Enum.take(@visible_events_limit)
      visible_events_by_league = Map.put(socket.assigns.visible_events_by_league, league, visible_events)

      IO.puts("Handle_info: Updated visible events for league #{league}, count: #{length(visible_events)}")

      {:noreply, assign(socket, events: updated_events, leagues: leagues, visible_events_by_league: visible_events_by_league, total_events: length(updated_events))}
    else
      IO.puts("Handle_info: Ignoring update for event #{event_id} due to sport mismatch")
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:fetch_initial_events, socket) do
    if Enum.empty?(socket.assigns.events) do
      {events, total} = fetch_events(socket.assigns.sport, 1, socket.assigns.show_in_play_only, socket.assigns.sort_by, socket.assigns.search_query)
      if Enum.empty?(events) do
        schedule_initial_fetch()
        {:noreply, socket}
      else
        leagues = group_events_by_league(events)
        visible_events_by_league = Enum.reduce(leagues, %{}, fn {league, league_events}, acc ->
          visible_events = Enum.take(league_events, @visible_events_limit)
          Map.put(acc, league, visible_events)
        end)
        {:noreply, assign(socket, events: events, leagues: leagues, visible_events_by_league: visible_events_by_league, total_events: total, total_pages: max(1, div(total + @events_per_page - 1, @events_per_page)))}
      end
    else
      {:noreply, socket}
    end
  end

  defp update_event(events, event_id, new_event) do
    case Enum.find_index(events, fn e -> e["id"] == event_id end) do
      nil ->
        IO.puts("MatchListLive: Adding new event #{event_id} to events list")
        [new_event | events]
      index ->
        IO.puts("MatchListLive: Updating existing event #{event_id} at index #{index}")
        List.replace_at(events, index, new_event)
    end
  end

  defp fetch_events(sport, page, show_in_play_only, sort_by, search_query) do
    all_events = SportsInfo.EventData.get_all_events(sport)
    filtered_events = all_events
                      |> filter_in_play(show_in_play_only)
                      |> filter_by_search(search_query)

    sorted_events = case sort_by do
      "time" -> Enum.sort_by(filtered_events, & &1["et"], :asc)
      "league" -> Enum.sort_by(filtered_events, & &1["cmp_name"], :asc)
    end

    total = length(sorted_events)
    start_index = (page - 1) * @events_per_page
    events = Enum.slice(sorted_events, start_index, @events_per_page)
    {events, total}
  end

  defp filter_in_play(events, true), do: Enum.filter(events, fn event -> event["et"] != nil end)
  defp filter_in_play(events, false), do: events

  defp filter_by_search(events, ""), do: events
  defp filter_by_search(events, query) do
    query = String.downcase(query)
    Enum.filter(events, fn event ->
      String.contains?(String.downcase(event["t1"]["n"]), query) ||
      String.contains?(String.downcase(event["t2"]["n"]), query)
    end)
  end

  defp group_events_by_league(events) do
    events
    |> Enum.group_by(fn event -> Map.get(event, "cmp_name", "Unknown League") end)
    |> Enum.into(%{}, fn {league, league_events} ->
      {league, Enum.sort_by(league_events, & &1["et"], :asc)}
    end)
  end

  defp schedule_initial_fetch do
    Process.send_after(self(), :fetch_initial_events, 5_000)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <!-- Search Bar -->
      <div class="mb-2 px-2">
        <form phx-change="search" class="relative">
          <input
            type="text"
            name="query"
            value={@search_query}
            placeholder="Search teams..."
            class="w-full px-4 py-2 text-sm bg-[#3a3a3a] text-white rounded focus:outline-none focus:ring-2 focus:ring-[#00c4b4]"
          />
          <svg class="w-5 h-5 text-gray-400 absolute right-4 top-1/2 transform -translate-y-1/2" fill="currentColor" viewBox="0 0 24 24">
            <path d="M15.5 14h-.79l-.28-.27A6.471 6.471 0 0 0 16 9.5 6.5 6.5 0 1 0 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z"/>
          </svg>
        </form>
      </div>

      <!-- Filters and Sort Options -->
      <div class="flex justify-between items-center mb-2 px-2">
        <div class="flex space-x-2">
          <button
            phx-click="toggle_in_play"
            class={"px-3 py-1 text-sm font-semibold rounded flex items-center #{if @show_in_play_only, do: "bg-[#4a4a4a] text-white", else: "bg-[#3a3a3a] text-gray-300 hover:bg-[#4a4a4a]"}"}
          >
            <%= if @show_in_play_only do %>
              Show All
            <% else %>
              <svg class="w-4 h-4 mr-1 text-green-400" fill="currentColor" viewBox="0 0 24 24">
                <circle cx="12" cy="12" r="10"/>
              </svg>
              In-Play Only
            <% end %>
          </button>
        </div>
        <div class="flex space-x-2">
          <button
            phx-click="sort_by"
            phx-value-sort="time"
            class={"px-3 py-1 text-sm font-semibold rounded #{if @sort_by == "time", do: "bg-[#4a4a4a] text-white", else: "bg-[#3a3a3a] text-gray-300 hover:bg-[#4a4a4a]"}"}
          >
            Sort by Time
          </button>
          <button
            phx-click="sort_by"
            phx-value-sort="league"
            class={"px-3 py-1 text-sm font-semibold rounded #{if @sort_by == "league", do: "bg-[#4a4a4a] text-white", else: "bg-[#3a3a3a] text-gray-300 hover:bg-[#4a4a4a]"}"}
          >
            Sort by League
          </button>
        </div>
      </div>

      <!-- Sport Selection Tabs -->
      <div class="flex space-x-2 mb-2 overflow-x-auto px-2">
        <%= for sport <- @sports do %>
          <button
            phx-click="select_sport"
            phx-value-sport={sport}
            class={"px-3 py-1 text-sm uppercase font-semibold rounded #{if @sport == sport, do: "bg-[#4a4a4a] text-white", else: "bg-[#3a3a3a] text-gray-300 hover:bg-[#4a4a4a]"}"}
          >
            <%= String.capitalize(sport) %>
          </button>
        <% end %>
        <!-- Market Dropdown -->
        <div class="ml-auto relative">
          <button
            id="market-dropdown"
            class="px-3 py-1 text-sm uppercase font-semibold rounded bg-[#3a3a3a] text-gray-300 hover:bg-[#4a4a4a] flex items-center"
            phx-click={Phoenix.LiveView.JS.toggle(to: "#market-options")}
          >
            <%= Enum.find(@markets, fn {id, _name} -> id == @selected_market end) |> elem(1) %>
            <svg class="w-4 h-4 ml-1" fill="currentColor" viewBox="0 0 24 24">
              <path d="M12 16l6-6H6l6 6z"/>
            </svg>
          </button>
          <div
            id="market-options"
            class="hidden absolute right-0 mt-1 bg-[#3a3a3a] rounded shadow-lg z-10"
          >
            <%= for {market_id, market_name} <- @markets do %>
              <button
                phx-click="select_market"
                phx-value-market={market_id}
                class="block w-full text-left px-4 py-2 text-sm text-gray-300 hover:bg-[#4a4a4a] hover:text-white"
              >
                <%= market_name %>
              </button>
            <% end %>
          </div>
        </div>
      </div>

      <!-- Matches Grouped by League -->
      <div id="match-list" class="px-2" phx-hook="VirtualizeMatchList">
        <%= if Enum.empty?(@leagues) do %>
          <div class="text-center text-gray-400 py-4">
            No matches available for <%= String.capitalize(@sport) %>.
          </div>
        <% else %>
          <%= for {league, league_events} <- @leagues do %>
            <div class="mb-2">
              <!-- League Header with Toggle -->
              <div class="flex justify-between items-center mb-1">
                <h2 class="text-sm md:text-base font-bold text-[#00c4b4] flex items-center" style="line-height: 2.5rem;">
                  <svg class="w-4 h-4 mr-1" fill="currentColor" viewBox="0 0 24 24">
                    <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8z"/>
                  </svg>
                  <%= league %>
                </h2>
                <button
                  phx-click="toggle_league"
                  phx-value-league={league}
                  class="text-gray-400 hover:text-white"
                >
                  <%= if MapSet.member?(@collapsed_leagues, league) do %>
                    <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
                      <path d="M12 8l-6 6h12l-6-6z"/>
                    </svg>
                  <% else %>
                    <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
                      <path d="M12 16l6-6H6l6 6z"/>
                    </svg>
                  <% end %>
                </button>
              </div>
              <%= unless MapSet.member?(@collapsed_leagues, league) do %>
                <div class="grid grid-cols-5 gap-2 font-semibold text-center text-xs bg-[#3a3a3a] p-2 rounded-t">
                  <div>Time</div>
                  <div class="col-span-2">Teams</div>
                  <div>Home</div>
                  <div>Tie</div>
                  <div>Away</div>
                </div>
                <div
                  id={"league-#{league}"}
                  class="relative"
                  style={"height: #{length(league_events) * 48}px;"}
                  phx-update="ignore"
                  data-league={league}
                >
                  <!-- Visible Events -->
                  <%= for event <- Map.get(@visible_events_by_league, league, []) do %>
                    <.link
                      id={"event-#{event["id"]}"}
                      patch={"/match/#{event["id"]}"}
                      replace={true}
                      class="match-row cursor-pointer absolute w-full transition-all duration-200 hover:bg-[#3a3a3a] hover:shadow-md"
                      style={"top: #{event_position(event, league_events)}px;"}
                    >
                      <div class="time flex items-center justify-center">
                        <%= if event["et"] do %>
                          <span class="text-[#00c4b4] font-bold time-value"><%= format_time(event["et"]) %></span>
                          <svg class="w-3 h-3 ml-1 text-red-500 animate-pulse" fill="currentColor" viewBox="0 0 24 24">
                            <circle cx="12" cy="12" r="10"/>
                          </svg>
                        <% else %>
                          <span class="text-gray-400 time-value"><%= format_start_time(event["id"]) %></span>
                        <% end %>
                      </div>
                      <div class="col-span-2 flex justify-between items-center">
                        <div class="flex items-center space-x-1 truncate">
                          <div class="w-5 h-5 bg-gray-500 rounded-full"></div>
                          <span class="truncate text-xs md:text-sm"><%= event["t1"]["n"] %></span>
                        </div>
                        <span class="score mx-1 text-[#ffcd00] font-bold">
                          <%= get_score(event, "a", 0) %>:<%= get_score(event, "a", 1) %>
                        </span>
                        <div class="flex items-center space-x-1 truncate">
                          <span class="truncate text-xs md:text-sm"><%= event["t2"]["n"] %></span>
                          <div class="w-5 h-5 bg-gray-500 rounded-full"></div>
                        </div>
                      </div>
                      <%= case get_odds(event, @selected_market) do %>
                        <% %{"1" => home, "X" => tie, "2" => away} -> %>
                          <div class="odds-home text-[#ffcd00] font-bold text-xs md:text-sm"><%= home %></div>
                          <div class="odds-tie text-[#ffcd00] font-bold text-xs md:text-sm"><%= tie %></div>
                          <div class="odds-away text-[#ffcd00] font-bold text-xs md:text-sm"><%= away %></div>
                        <% _ -> %>
                          <div class="odds-home">-</div>
                          <div class="odds-tie">-</div>
                          <div class="odds-away">-</div>
                      <% end %>
                      <button
                        phx-click="toggle_favorite"
                        phx-value-event_id={event["id"]}
                        class="absolute left-0 top-1/2 transform -translate-y-1/2 text-yellow-400 hover:text-yellow-300"
                      >
                        <%= if MapSet.member?(@favorite_matches, event["id"]) do %>
                          <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
                            <path d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z"/>
                          </svg>
                        <% else %>
                          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z"/>
                          </svg>
                        <% end %>
                      </button>
                    </.link>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>
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

  defp format_start_time(event_id) do
    id_num = String.split(event_id, "_") |> List.last() |> String.to_integer()
    hour = rem(id_num, 24)
    minute = rem(id_num * 5, 60)
    "#{String.pad_leading(to_string(hour), 2, "0")}:#{String.pad_leading(to_string(minute), 2, "0")}"
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

  defp event_position(event, league_events) do
    index = Enum.find_index(league_events, fn e -> e["id"] == event["id"] end) || 0
    index * 48
  end
end