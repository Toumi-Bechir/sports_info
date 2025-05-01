defmodule SportsInfo.EventData do
  @num_shards 16

  def get_all_events(sport \\ nil) do
    events = 0..(@num_shards - 1)
             |> Enum.flat_map(&SportsInfo.EventWorker.get_events(&1, sport))
    IO.puts("EventData: Fetched #{length(events)} events for sport #{sport}")
    if sport do
      filtered_events = Enum.filter(events, fn event -> Map.get(event, "sport") == sport end)
      IO.puts("EventData: Filtered to #{length(filtered_events)} events for sport #{sport}")
      filtered_events
    else
      events
    end
  end

  def get_event(event_id) do
    shard = :erlang.phash2(event_id, @num_shards)
    event = SportsInfo.EventWorker.get_event(shard, event_id)
    IO.puts("EventData: Fetched event #{event_id}:") #{inspect(event)}
    event
  end
end