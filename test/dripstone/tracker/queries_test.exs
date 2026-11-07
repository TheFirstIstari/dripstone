defmodule Dripstone.Tracker.QueriesTest do
  use ExUnit.Case, async: true

  alias Dripstone.Tracker.{Curation, FeedHealth, Queries, SampleLoader}

  @now ~U[2026-11-07 17:00:00Z]

  setup_all do
    %{state: SampleLoader.load(@now)}
  end

  describe "risk levels" do
    for {score, level} <- [
          {0, :low},
          {39, :low},
          {40, :medium},
          {69, :medium},
          {70, :high},
          {100, :high}
        ] do
      test "#{score} is #{level}" do
        assert Queries.risk_level(unquote(score)) == unquote(level)
      end
    end
  end

  describe "accounts" do
    test "default: highest risk first, 50 per page, with the total", %{state: state} do
      page = Queries.list_accounts(state, %{})
      assert page.total == 1300
      assert page.pages == 26
      assert page.page == 1
      assert length(page.entries) == 50

      scores = Enum.map(page.entries, & &1.account.risk_score)
      assert scores == Enum.sort(scores, :desc)
    end

    test "page 2 holds rows 51-100, and out-of-range pages are clamped", %{state: state} do
      all =
        Queries.list_accounts(state, %{page: 1}).entries ++
          Queries.list_accounts(state, %{page: 2}).entries

      assert all |> Enum.map(& &1.account.id) |> Enum.uniq() |> length() == 100

      assert Queries.list_accounts(state, %{page: 999}).page == 26
      assert Queries.list_accounts(state, %{page: -3}).page == 1
    end

    test "sort by last seen, newest first", %{state: state} do
      seen =
        Queries.list_accounts(state, %{sort: :last_seen}).entries
        |> Enum.map(& &1.account.last_seen_at)

      assert seen == Enum.sort(seen, {:desc, DateTime})
    end

    test "filters combine with AND", %{state: state} do
      %{entries: entries, total: total} =
        Queries.list_accounts(state, %{platform: "reddit", risk: :high})

      assert total > 0
      assert Enum.all?(entries, &(&1.account.feed_id == "reddit" and &1.account.risk_score >= 70))
    end

    test "text search on handle or display name, case-insensitive", %{state: state} do
      [%{account: target} | _] = Queries.list_accounts(state, %{}).entries
      %{entries: entries} = Queries.list_accounts(state, %{q: String.upcase(target.handle)})
      assert Enum.any?(entries, &(&1.account.id == target.id))

      name_hits =
        Queries.list_accounts(state, %{q: "  " <> String.downcase(target.display_name) <> " "})

      assert Enum.all?(
               name_hits.entries,
               &String.contains?(
                 String.downcase(&1.account.display_name),
                 String.downcase(target.display_name)
               )
             )
    end

    test "network membership: any, none, or a specific network", %{state: state} do
      any = Queries.list_accounts(state, %{network: "any"})
      none = Queries.list_accounts(state, %{network: "none"})
      assert any.total + none.total == 1300
      assert Enum.all?(any.entries, &(&1.networks != []))
      assert Enum.all?(none.entries, &(&1.networks == []))

      sunrise = Queries.list_accounts(state, %{network: "net-sunrise"})
      assert sunrise.total == length(state.networks["net-sunrise"].member_ids)
    end

    test "no matches gives an empty first page", %{state: state} do
      assert %{entries: [], total: 0, page: 1, pages: 1} =
               Queries.list_accounts(state, %{q: "zzz-no-such"})
    end

    test "account detail includes networks, posts newest first and links strongest first", %{
      state: state
    } do
      [member | _] = state.networks["net-sunrise"].member_ids
      detail = Queries.get_account(state, member)

      assert Enum.any?(detail.networks, &(&1.id == "net-sunrise"))
      times = Enum.map(detail.posts, & &1.posted_at)
      assert times == Enum.sort(times, {:desc, DateTime})
      assert detail.links != []
      ranks = Enum.map(detail.links, &%{weak: 1, moderate: 2, strong: 3}[&1.strength])
      assert ranks == Enum.sort(ranks, :desc)
    end

    test "unknown ids return nil", %{state: state} do
      assert Queries.get_account(state, "acc-nope") == nil
      assert Queries.get_network(state, "net-nope") == nil
      assert Queries.get_alert(state, "alert-nope") == nil
    end
  end

  describe "alerts" do
    test "default lists open alerts, newest first", %{state: state} do
      entries = Queries.list_alerts(state, %{})
      assert length(entries) == 10
      assert Enum.all?(entries, &(&1.alert.status == :open))
      raised = Enum.map(entries, & &1.alert.raised_at)
      assert raised == Enum.sort(raised, {:desc, DateTime})
    end

    test "filters by status, severity, trigger and platform", %{state: state} do
      assert length(Queries.list_alerts(state, %{status: :all})) == map_size(state.alerts)

      assert Enum.all?(
               Queries.list_alerts(state, %{status: :confirmed}),
               &(&1.alert.status == :confirmed)
             )

      high_growth = Queries.list_alerts(state, %{trigger: "network_growth", severity: :high})
      assert high_growth == []

      growth = Queries.list_alerts(state, %{trigger: "network_growth"})
      assert length(growth) == 2

      telegram = Queries.list_alerts(state, %{platform: "telegram"})
      assert telegram != [] and Enum.all?(telegram, &("telegram" in &1.network.platforms))
    end

    test "alert detail sorts evidence strongest first and resolves the trigger type", %{
      state: state
    } do
      [%{alert: %{id: id}} | _] = Queries.list_alerts(state, %{trigger: "promotion_shift"})
      detail = Queries.get_alert(state, id)

      assert detail.trigger_type.name == "Promotion shift"
      strengths = Enum.map(detail.alert.evidence, & &1.strength)
      assert hd(strengths) == :strong
      assert detail.alert.comparison.after =~ "deals-b.example"
      assert map_size(detail.accounts) > 0
    end

    test "neighbors follow the filtered order", %{state: state} do
      ids = state |> Queries.list_alerts(%{}) |> Enum.map(& &1.alert.id)
      [first, second, third | _] = ids

      assert %{position: 1, total: 10, prev: nil, next: ^second} =
               Queries.alert_neighbors(state, first, %{})

      assert %{position: 2, prev: ^first, next: ^third} =
               Queries.alert_neighbors(state, second, %{})

      assert %{next: nil} = Queries.alert_neighbors(state, List.last(ids), %{})
    end

    test "an alert that left the list points at the one now in its place", %{state: state} do
      [_first, second, third | _] = state |> Queries.list_alerts(%{}) |> Enum.map(& &1.alert.id)
      decided = put_in(state.alerts[second].status, :confirmed)

      assert %{position: nil, total: 9, next: ^third} =
               Queries.alert_neighbors(decided, second, %{})
    end
  end

  describe "networks" do
    test "most recently active first, with open alert counts", %{state: state} do
      entries = Queries.list_networks(state, %{})
      assert length(entries) == 12
      activity = Enum.map(entries, & &1.last_activity_at)
      assert activity == Enum.sort(activity, {:desc, DateTime})
      assert Enum.find(entries, &(&1.network.id == "net-sunrise")).open_alerts == 2
    end

    test "filters by status, platform and tag", %{state: state} do
      suspected = Queries.list_networks(state, %{status: :suspected})
      assert suspected != [] and Enum.all?(suspected, &(&1.network.status == :suspected))

      assert [%{network: %{id: "net-sunrise"}}] =
               Queries.list_networks(state, %{tag: "discount-spam"})

      assert Enum.all?(
               Queries.list_networks(state, %{platform: "mastodon"}),
               &("mastodon" in &1.network.platforms)
             )
    end

    test "networks retired by a merge are excluded from lists but still viewable", %{state: state} do
      {:ok, _, merged, _} = Curation.merge(state, "net-driftwood", "net-sunrise", @now)

      ids = merged |> Queries.list_networks(%{}) |> Enum.map(& &1.network.id)
      refute "net-driftwood" in ids
      assert %{retired_into: %{id: "net-sunrise"}} = Queries.get_network(merged, "net-driftwood")
    end

    test "network detail: members by risk, alerts, history and a heatmap", %{state: state} do
      detail = Queries.get_network(state, "net-sunrise")

      assert length(detail.members) == length(detail.network.member_ids)

      assert Enum.map(detail.alerts, & &1.trigger_id) |> Enum.sort() == [
               "new_network",
               "promotion_shift"
             ]

      assert Enum.any?(detail.history, &(&1.actor == :analyst))
      assert detail.heatmap.busiest == "Weekdays 09:00–10:00 UTC"
      assert detail.heatmap.max > 0
    end

    test "list_tags/1 suggests tags by prefix", %{state: state} do
      assert Queries.list_tags(state, "disc") == ["discount-spam"]
      assert Queries.list_tags(state, "") == ["coordinated-promo", "discount-spam"]
      assert Queries.list_tags(state, "zz") == []
    end
  end

  describe "overview and feeds" do
    test "headline counts and a 30-day trend", %{state: state} do
      overview = Queries.overview(state, @now)

      assert overview.open_alerts == 10

      assert overview.open_high_alerts ==
               Enum.count(Queries.list_alerts(state, %{}), &(&1.alert.severity == :high))

      assert overview.tracked_accounts == 1300
      assert length(overview.trend) == 30
      assert List.last(overview.trend).date == ~D[2026-11-07]
      assert overview.trend_total == Enum.sum(Enum.map(overview.trend, & &1.count))
      assert length(overview.newest_open_alerts) == 5
      assert length(overview.recent_networks) == 5
    end

    test "feed health lists every feed, non-healthy first on the overview", %{state: state} do
      feeds = Queries.feed_health(state)
      assert Enum.map(feeds, & &1.feed.id()) == ~w(x reddit bluesky mastodon telegram facebook)
      assert Enum.sum(Enum.map(feeds, & &1.accounts)) == 1300

      [first, second | _] = Queries.overview(state, @now).feeds
      assert Enum.sort([first.health.status, second.health.status]) == [:degraded, :down]
    end

    test "a feed with no health data counts as not connected", %{state: state} do
      state = %{state | feed_health: Enum.reject(state.feed_health, &(&1.feed_id == "x"))}
      assert %{health: %FeedHealth{status: :not_connected}} = hd(Queries.feed_health(state))
    end
  end
end
