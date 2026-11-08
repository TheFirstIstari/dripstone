defmodule Dripstone.Discovery.BurstsTest do
  # live-discovery "Burst prescreening" scenarios.
  use ExUnit.Case, async: true

  alias Dripstone.Discovery.Bursts

  @min 60_000

  defp feed(state, posts) do
    Enum.reduce(posts, {state, []}, fn {did, url, at}, {state, found} ->
      case Bursts.observe(state, did, url, at) do
        {state, nil} -> {state, found}
        {state, candidate} -> {state, found ++ [candidate]}
      end
    end)
  end

  test "five accounts sharing a link within ten minutes make one candidate" do
    posts = for n <- 1..5, do: {"did:#{n}", "https://deals.example/x", n * @min}
    {_state, [candidate]} = feed(Bursts.new(), posts)

    assert candidate.url == "https://deals.example/x"
    assert candidate.domain == "deals.example"
    assert length(candidate.dids) == 5
  end

  test "posts spread beyond the window don't add up" do
    posts = for n <- 1..5, do: {"did:#{n}", "https://deals.example/x", n * 11 * @min}
    assert {_state, []} = feed(Bursts.new(), posts)
  end

  test "a common domain is ignored" do
    posts = for n <- 1..20, do: {"did:#{n}", "https://www.youtube.com/watch?v=abc", n}
    assert {_state, []} = feed(Bursts.new(), posts)
  end

  test "the same link can't produce a second candidate during the cooldown" do
    first = for n <- 1..5, do: {"did:#{n}", "https://deals.example/x", n * @min}
    more = for n <- 6..12, do: {"did:#{n}", "https://deals.example/x", 10 * @min + n * @min}

    assert {_state, [_one]} = feed(Bursts.new(), first ++ more)
  end

  test "one account repeating a link counts once" do
    posts = for n <- 1..10, do: {"did:same", "https://deals.example/x", n * @min}
    assert {_state, []} = feed(Bursts.new(), posts)
  end

  test "tracking parameters and case don't split a link" do
    urls = [
      "https://Deals.Example/x?utm_source=a",
      "https://deals.example/x?fbclid=123",
      "http://www.deals.example/x",
      "https://deals.example/x#top",
      "https://deals.example/x?utm_campaign=z&ref=y"
    ]

    posts = urls |> Enum.with_index(1) |> Enum.map(fn {u, n} -> {"did:#{n}", u, n * @min} end)
    assert {_state, [%{url: "https://deals.example/x"}]} = feed(Bursts.new(), posts)
  end

  test "the number of tracked links stays bounded" do
    posts = for n <- 1..50, do: {"did:1", "https://site#{n}.example/", n}
    {state, []} = feed(Bursts.new(max_tracked: 10), posts)
    assert map_size(state.seen) <= 10
    # The most recent links are the ones kept.
    assert Map.has_key?(state.seen, "https://site50.example/")
  end

  test "non-web links are ignored" do
    assert {_state, nil} = Bursts.observe(Bursts.new(), "did:1", "mailto:x@y.z", 1)
    assert Bursts.normalize("at://did/app.bsky.feed.post/1") == :error
  end
end
