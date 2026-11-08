defmodule DripstoneWeb.OverviewLiveTest do
  # Changes the app-wide tracker store, so it must not run alongside other tests.
  use DripstoneWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  alias Dripstone.Tracker
  alias Dripstone.Tracker.Store

  setup do
    {:ok, previous} = Store.load()
    on_exit(fn -> :ok = Store.save(previous) end)
    Tracker.reset_sample_data!()
    :ok
  end

  defp count(view, id), do: view |> element("##{id} p.text-3xl") |> render() |> text()

  defp text(html), do: html |> LazyHTML.from_fragment() |> LazyHTML.text() |> String.trim()

  defp href(view, selector),
    do:
      view
      |> element(selector)
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.attribute("href")
      |> hd()

  defp ids(view, selector),
    do:
      view
      |> render()
      |> LazyHTML.from_document()
      |> LazyHTML.query(selector)
      |> LazyHTML.attribute("id")

  test "is the landing page", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    assert has_element?(view, "#nav-overview[aria-current=page]")
    assert has_element?(view, "#headline-counts")
  end

  test "scope without a user takes the logged-out branch in mount and render" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, current_scope: %{user: nil}, flash: %{}}
    }

    assert {:ok, %{assigns: %{page_title: "Dripstone"}}} =
             DripstoneWeb.OverviewLive.mount(%{}, %{}, socket)

    assigns = %{current_scope: %{user: nil}, flash: %{}}
    assert %Phoenix.LiveView.Rendered{static: static} = DripstoneWeb.OverviewLive.render(assigns)
    assert Enum.join(static) =~ "landing"
  end

  describe "headline counts" do
    test "show open, open high, suspected networks and tracked accounts", %{conn: conn} do
      overview = Tracker.overview()
      {:ok, view, _html} = live(conn, "/")

      assert count(view, "count-open-alerts") == "10"
      assert count(view, "count-high-alerts") == to_string(overview.open_high_alerts)
      assert count(view, "count-suspected-networks") == to_string(overview.suspected_networks)
      assert count(view, "count-tracked-accounts") == "1,300"
    end

    test "link to the matching filtered screens", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      assert has_element?(view, ~s(#count-open-alerts[href="/alerts"]))
      uri = view |> href("#count-high-alerts") |> URI.parse()
      assert uri.path == "/alerts"
      assert URI.decode_query(uri.query) == %{"status" => "open", "severity" => "high"}
      assert has_element?(view, ~s(#count-suspected-networks[href="/networks?status=suspected"]))
      assert has_element?(view, ~s(#count-tracked-accounts[href="/accounts"]))
    end

    test "update live when an alert is raised", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      {:ok, %{alert: alert}} =
        Tracker.apply_finding(%{
          trigger: "promotion_shift",
          severity: "high",
          title: "Live shift",
          observed_at: DateTime.utc_now(),
          network_id: "net-c0421",
          evidence: [%{explanation: "Links switched domain.", strength: "strong"}]
        })

      assert count(view, "count-open-alerts") == "11"
      assert has_element?(view, "#overview-alert-#{alert.id}", "Live shift")
    end
  end

  test "the alert trend covers 30 days and states the total", %{conn: conn} do
    %{trend_total: total} = Tracker.overview()
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(
             view,
             "#alert-trend-chart [data-summary]",
             "#{total} alerts raised in the last 30 days."
           )

    assert view
           |> render()
           |> LazyHTML.from_document()
           |> LazyHTML.query("#alert-trend-chart rect")
           |> Enum.count() == 30
  end

  describe "newest open alerts" do
    test "lists up to five, newest first, linking to each alert", %{conn: conn} do
      expected =
        Tracker.list_alerts() |> Enum.take(5) |> Enum.map(&"overview-alert-#{&1.alert.id}")

      {:ok, view, _html} = live(conn, "/")

      assert ids(view, "#newest-alert-list > li[id^=overview-alert]") == expected
      assert has_element?(view, ~s(#open-inbox[href="/alerts"]))
    end

    test "says the queue is clear when nothing is open", %{conn: conn} do
      for %{alert: alert} <- Tracker.list_alerts(), do: {:ok, _} = Tracker.dismiss_alert(alert.id)
      {:ok, view, _html} = live(conn, "/")

      assert has_element?(view, "#queue-clear", "Nothing waiting for review")
      assert ids(view, "#newest-alert-list > li[id^=overview-alert]") == []
      assert count(view, "count-open-alerts") == "0"
    end
  end

  test "recently active networks: five, most recent first, with a link to all", %{conn: conn} do
    expected =
      Tracker.list_networks() |> Enum.take(5) |> Enum.map(&"overview-network-#{&1.network.id}")

    {:ok, view, _html} = live(conn, "/")

    assert ids(view, "#recent-network-list > li[id^=overview-network]") == expected
    assert has_element?(view, ~s(#see-all-networks[href="/networks"]))
  end

  test "the feed strip lists every feed with non-healthy ones first", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    [first, second | rest] = ids(view, "#feed-strip-list > a")
    assert Enum.sort([first, second]) == ["feed-strip-facebook", "feed-strip-telegram"]
    assert length(rest) == 4

    assert has_element?(view, "#feed-strip-telegram[data-feed-status=down]", "Down")
    assert has_element?(view, "#feed-strip-facebook", "Degraded")
  end
end
