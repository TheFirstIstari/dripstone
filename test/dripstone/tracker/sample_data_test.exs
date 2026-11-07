defmodule Dripstone.Tracker.SampleDataTest do
  use ExUnit.Case, async: true

  alias Dripstone.Feeds
  alias Dripstone.Tracker.{Account, FeedHealth, Link, Post, SampleData}

  @now ~U[2026-11-07 17:00:00Z]

  setup_all do
    %{data: SampleData.generate(@now)}
  end

  defp findings(data, trigger) do
    for %{type: :finding, finding: %{trigger: ^trigger} = f} = event <- data.events,
        do: Map.put(f, :event_at, event.at)
  end

  defp network_of(%{network_id: id}), do: id
  defp network_of(%{new_network: %{id: id}}), do: id

  defp initial_members(data, network) do
    Enum.find_value(findings(data, "new_network"), fn f ->
      if f.new_network.id == network, do: f.new_network.member_ids
    end)
  end

  describe "determinism" do
    test "the same `now` always produces the same data", %{data: data} do
      assert SampleData.generate(@now) == data
    end

    test "does not disturb the caller's random state" do
      :rand.seed(:exsss, {1, 2, 3})
      expected = :rand.uniform(1_000_000)
      :rand.seed(:exsss, {1, 2, 3})
      SampleData.generate(@now)
      assert :rand.uniform(1_000_000) == expected
    end
  end

  describe "base data" do
    test "about 1,300 accounts spread over every registered feed", %{data: data} do
      assert length(data.accounts) == 1300
      assert Enum.all?(data.accounts, &match?(%Account{}, &1))

      feed_ids = data.accounts |> Enum.map(& &1.feed_id) |> Enum.uniq() |> Enum.sort()
      assert feed_ids == Feeds.all() |> Enum.map(& &1.id()) |> Enum.sort()

      ids = Enum.map(data.accounts, & &1.id)
      assert ids == Enum.uniq(ids)
    end

    test "accounts have risk scores 0-100 and signals that sum to the score", %{data: data} do
      for account <- data.accounts do
        assert account.risk_score in 0..100
        assert account.signals != []
        assert Enum.sum(Enum.map(account.signals, & &1.contribution)) == account.risk_score
        contributions = Enum.map(account.signals, & &1.contribution)
        assert contributions == Enum.sort(contributions, :desc)
      end
    end

    test "Mastodon accounts carry a valid instance", %{data: data} do
      for %Account{feed_id: "mastodon"} = account <- data.accounts do
        assert Feeds.get("mastodon").profile_url(account) =~ ~r{^https://[a-z.]+/@}
      end
    end

    test "posts belong to known accounts, and some accounts have none", %{data: data} do
      ids = MapSet.new(data.accounts, & &1.id)
      assert Enum.all?(data.posts, &(match?(%Post{}, &1) and &1.account_id in ids))
      assert Enum.all?(data.posts, &(DateTime.compare(&1.posted_at, @now) != :gt))

      with_posts = MapSet.new(data.posts, & &1.account_id)
      assert Enum.any?(data.accounts, &(&1.id not in with_posts))
    end

    test "links join two distinct known accounts", %{data: data} do
      ids = MapSet.new(data.accounts, & &1.id)

      for %Link{account_ids: {a, b}, kind: kind, strength: strength} <- data.links do
        assert a < b and a in ids and b in ids
        assert kind in Link.kinds()
        assert strength in Link.strengths()
      end
    end

    test "feed health covers every feed, including one Down and one Degraded", %{data: data} do
      assert Enum.all?(data.feed_health, &match?(%FeedHealth{}, &1))

      assert Enum.sort(Enum.map(data.feed_health, & &1.feed_id)) ==
               Feeds.all() |> Enum.map(& &1.id()) |> Enum.sort()

      assert %FeedHealth{feed_id: "telegram", last_error: "401 Unauthorized"} =
               Enum.find(data.feed_health, &(&1.status == :down))

      assert Enum.any?(data.feed_health, &(&1.status == :degraded))
    end

    test "feeds reported Healthy are within their expected interval", %{data: data} do
      for %FeedHealth{status: :healthy} = health <- data.feed_health do
        interval = Feeds.get(health.feed_id).expected_interval()

        assert DateTime.diff(@now, health.last_item_at) <= interval,
               "#{health.feed_id} has gone quiet"
      end
    end
  end

  describe "events" do
    test "are in time order and only use catalog trigger types", %{data: data} do
      times = Enum.map(data.events, & &1.at)
      assert times == Enum.sort(times, DateTime)

      catalog = MapSet.new(Dripstone.Alerts.trigger_types(), & &1.id)

      for %{type: :finding, finding: f} <- data.events do
        assert f.trigger in catalog
        assert f.severity in ~w(low medium high)
        assert f.evidence != []
        assert Map.has_key?(f, :network_id) or Map.has_key?(f, :new_network)
      end
    end

    test "about a dozen networks are created, one with 400 members", %{data: data} do
      created = findings(data, "new_network")
      assert length(created) == 12
      assert Enum.any?(created, &(length(&1.new_network.member_ids) == 400))
    end

    test "includes a promotion shift with before/after domains", %{data: data} do
      assert [shift] = findings(data, "promotion_shift")
      assert shift.comparison.before =~ "deals-a.example"
      assert shift.comparison.after =~ "deals-b.example"
      assert shift.network_updates.main_domain == "deals-b.example"
    end

    test "includes growth on a network that was confirmed earlier", %{data: data} do
      confirmed =
        for %{type: :decision, action: :confirm, network_id: id, at: at} <- data.events,
            do: {id, at}

      assert Enum.any?(findings(data, "network_growth"), fn growth ->
               Enum.any?(confirmed, fn {id, at} ->
                 id == growth.network_id and DateTime.before?(at, growth.event_at)
               end)
             end)
    end

    test "includes a reactivation after at least 14 days of silence", %{data: data} do
      assert [reactivation] = findings(data, "network_reactivation")
      network = reactivation.network_id

      members = data |> initial_members(network) |> MapSet.new()

      member_posts =
        data.posts
        |> Enum.filter(&(&1.account_id in members))
        |> Enum.map(& &1.posted_at)
        |> Enum.sort(DateTime)

      recent = Enum.filter(member_posts, &(DateTime.diff(@now, &1, :day) < 1))
      [latest_quiet | _] = member_posts |> Enum.reject(&(&1 in recent)) |> Enum.reverse()

      assert recent != []
      assert DateTime.diff(hd(recent), latest_quiet, :day) >= 14
    end

    test "includes a dismissed network that returns, plus a stale finding", %{data: data} do
      [{network, dismissed_at}] =
        for %{type: :decision, action: :dismiss, network_id: id, at: at} <- data.events,
            Enum.any?(findings(data, "network_growth"), &(&1.network_id == id)),
            do: {id, at}

      growth = Enum.filter(findings(data, "network_growth"), &(&1.network_id == network))

      assert Enum.any?(growth, fn f ->
               DateTime.after?(f.event_at, dismissed_at) and
                 DateTime.before?(f.observed_at, dismissed_at)
             end),
             "expected a stale finding reported after, but observed before, the dismissal"

      assert Enum.any?(growth, &DateTime.after?(&1.observed_at, dismissed_at)),
             "expected a finding observed after the dismissal"
    end

    test "includes a network with no AI summary or rationale", %{data: data} do
      assert Enum.any?(
               findings(data, "new_network"),
               &(is_nil(&1.new_network.summary) and is_nil(&1.ai_rationale))
             )
    end

    test "includes a renamed, tagged network whose removed member a later finding re-adds",
         %{data: data} do
      curation = for %{type: :curation} = e <- data.events, do: e
      assert %{network_id: network} = Enum.find(curation, &(&1.action == :rename))
      assert Enum.any?(curation, &(&1.action == :add_tag and &1.network_id == network))

      %{account_id: removed, at: removed_at} =
        Enum.find(curation, &(&1.action == :remove_member and &1.network_id == network))

      assert Enum.any?(data.events, fn
               %{type: :finding, at: at, finding: %{network_updates: %{add_member_ids: ids}} = f} ->
                 network_of(f) == network and removed in ids and DateTime.after?(at, removed_at)

               _other ->
                 false
             end)
    end
  end
end
