defmodule Dripstone.Discovery.JetstreamTest do
  # live-discovery "Live stream ingestion" and "Feed health from ingestion",
  # driven from recorded Jetstream frames: no network. Uses the Live rows.
  use Dripstone.DataCase, async: false

  alias Dripstone.Discovery.Jetstream
  alias Dripstone.Tracker.Store

  @now ~U[2026-11-08 10:00:00Z]

  # The shape of a Jetstream post event (as delivered on the wire).
  defp post_event(did, n, text, link \\ nil) do
    record =
      %{"$type" => "app.bsky.feed.post", "text" => text, "createdAt" => "2026-11-08T10:00:00Z"}
      |> then(fn r ->
        if link,
          do:
            Map.put(r, "facets", [
              %{"features" => [%{"$type" => "app.bsky.richtext.facet#link", "uri" => link}]}
            ]),
          else: r
      end)

    %{
      "did" => did,
      "time_us" => 1_762_596_000_000_000 + n * 60_000_000,
      "kind" => "commit",
      "commit" => %{
        "operation" => "create",
        "collection" => "app.bsky.feed.post",
        "rkey" => "r#{n}",
        "record" => record
      }
    }
  end

  defp feed(events) do
    Enum.reduce(events, {Jetstream.new_state(), []}, fn e, {state, found} ->
      {state, c} = Jetstream.handle_event(state, e, @now)
      {state, found ++ c}
    end)
  end

  test "only posts with links are considered (Linked posts are kept)" do
    events =
      for(n <- 1..5, do: post_event("did:plc:#{n}", n, "plain text, no link")) ++
        for n <- 1..4, do: post_event("did:plc:l#{n}", n, "deal", "https://deals.example/x")

    {state, []} = feed(events)
    # All nine posts were counted for feed health, but only linked ones tracked.
    assert state.items_24h == 9
    assert map_size(state.bursts.seen) == 1
  end

  test "five accounts posting one link within minutes complete a candidate group" do
    events =
      for n <- 1..5,
          do: post_event("did:plc:#{n}", n, "deal", "https://deals.example/x?utm_source=bsky")

    {state, [candidate]} = feed(events)

    assert candidate.url == "https://deals.example/x"
    assert length(candidate.dids) == 5
    assert state.cursor_us == List.last(events)["time_us"]
  end

  test "non-post and delete events only move the cursor" do
    identity = %{"did" => "did:plc:x", "time_us" => 42, "kind" => "identity", "identity" => %{}}

    delete = %{
      "did" => "did:plc:x",
      "time_us" => 43,
      "kind" => "commit",
      "commit" => %{"operation" => "delete", "collection" => "app.bsky.feed.post"}
    }

    {state, []} = feed([identity, delete])
    assert state.cursor_us == 43
    assert state.items_24h == 0
  end

  test "disabled by configuration (Disabled by configuration)" do
    refute Jetstream.enabled?()
    refute Process.whereis(Jetstream)
  end

  test "health is Down while disconnected and is written in one flush (Stream disconnected)" do
    state = %{
      Jetstream.new_state()
      | connected: false,
        last_error: ":closed",
        last_error_at: @now
    }

    assert %{feed_id: "bluesky", status: :down, last_error: ":closed"} =
             Jetstream.health(state, @now)

    {:ok, before} = Store.load()
    :ok = Jetstream.flush_health(state)
    {:ok, after_} = Store.load()

    assert %{status: :down} = Enum.find(after_.feed_health, &(&1.feed_id == "bluesky"))
    # The flush replaced Bluesky's entry and left the other feeds alone.
    assert length(after_.feed_health) ==
             length(Enum.reject(before.feed_health, &(&1.feed_id == "bluesky"))) + 1
  end

  test "counting posts doesn't write anything (one write per flush, not per post)" do
    {:ok, before} = Store.load()
    events = for n <- 1..50, do: post_event("did:plc:#{n}", n, "hello")
    {_state, []} = feed(events)
    {:ok, after_} = Store.load()
    assert after_.feed_health == before.feed_health
  end

  test "a connected stream that goes quiet is idle; a disconnected one never is" do
    connected = %{conn: :a_conn, last_data_ms: 1_000, idle_ms: 90_000}

    refute Jetstream.idle?(connected, 1_000 + 90_000)
    assert Jetstream.idle?(connected, 1_000 + 90_001)
    refute Jetstream.idle?(%{connected | conn: nil}, 1_000_000)
    refute Jetstream.idle?(%{connected | last_data_ms: nil}, 1_000_000)
  end
end
