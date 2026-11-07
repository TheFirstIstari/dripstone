defmodule DripstoneWeb.AlertLive.IndexTest do
  # Changes the app-wide tracker store and app env, so it must not run alongside other tests.
  use DripstoneWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  alias Dripstone.Alerts
  alias Dripstone.Tracker
  alias Dripstone.Tracker.SampleStore

  setup do
    previous = SampleStore.get_state()
    on_exit(fn -> SampleStore.put_state(previous) end)
    Tracker.reset_sample_data!()
    :ok
  end

  defp row_ids(view),
    do:
      view
      |> render()
      |> LazyHTML.from_document()
      |> LazyHTML.query("#alerts > li[id^=alert-row]")
      |> LazyHTML.attribute("id")

  defp expected_ids(filters),
    do: Enum.map(Tracker.list_alerts(filters), &"alert-row-#{&1.alert.id}")

  defp finding(severity, trigger \\ "promotion_shift") do
    %{
      trigger: trigger,
      severity: severity,
      title: "Live #{severity} #{trigger}",
      observed_at: DateTime.utc_now(),
      network_id: "net-c0421",
      evidence: [%{explanation: "Links switched domain.", strength: "strong"}]
    }
  end

  test "lists only Open alerts by default, newest first", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/alerts")

    assert row_ids(view) == expected_ids(%{status: :open})
    assert length(row_ids(view)) == 10
    assert has_element?(view, "#alert-count", "10 open")
    assert has_element?(view, "#nav-alerts[aria-current=page]")
  end

  test "each row shows severity, title, trigger, network, platforms and age", %{conn: conn} do
    [%{alert: alert, network: network} | _] = Tracker.list_alerts(%{trigger: "promotion_shift"})
    {:ok, view, _html} = live(conn, "/alerts")

    row = "#alert-row-#{alert.id}"
    assert has_element?(view, "#{row} [data-severity=high]", "High")
    assert has_element?(view, row, alert.title)
    assert has_element?(view, row, "Promotion shift")
    assert has_element?(view, row, network.name)
    assert has_element?(view, "#{row} time")
    assert has_element?(view, ~s(#{row} a[href="/alerts/#{alert.id}"]))
  end

  test "re-alerts of dismissed networks are marked", %{conn: conn} do
    [%{alert: alert}] = Tracker.list_alerts() |> Enum.filter(&(&1.network.id == "net-echo"))
    {:ok, view, _html} = live(conn, "/alerts")

    assert has_element?(
             view,
             "#alert-row-#{alert.id} [data-previously-dismissed]",
             "Previously dismissed"
           )
  end

  describe "filters" do
    test "combine with AND and are kept in the URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/alerts")

      view
      |> form("#alert-filters",
        filters: %{status: "open", severity: "medium", trigger: "network_growth", platform: ""}
      )
      |> render_change()

      assert_patch(view, "/alerts?severity=medium&trigger=network_growth")

      assert row_ids(view) ==
               expected_ids(%{status: :open, severity: :medium, trigger: "network_growth"})

      assert length(row_ids(view)) == 2
    end

    test "are restored from the URL on load", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/alerts?status=all&platform=telegram")

      assert row_ids(view) == expected_ids(%{status: :all, platform: "telegram"})

      assert has_element?(
               view,
               "#alert-filters select[name='filters[status]'] option[selected][value=all]"
             )

      assert has_element?(
               view,
               "#alert-filters select[name='filters[platform]'] option[selected][value=telegram]"
             )
    end

    test "unknown filter values are ignored", %{conn: conn} do
      {:ok, view, _html} =
        live(conn, "/alerts?status=bogus&severity=extreme&trigger=nope&platform=myspace")

      assert row_ids(view) == expected_ids(%{status: :open})
    end

    test "no matches show an empty state with a way to clear the filters", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/alerts?trigger=network_growth&severity=high")

      assert row_ids(view) == []
      assert has_element?(view, "#alerts-empty", "No alerts match these filters")
      assert has_element?(view, ~s(#alert-filters-clear[href="/alerts"]))
    end

    test "trigger and platform options come from the catalog and registry", %{conn: conn} do
      config = Application.get_env(:dripstone, Alerts)
      on_exit(fn -> Application.put_env(:dripstone, Alerts, config) end)

      extra = [
        id: "link_rotation",
        name: "Link rotation",
        description: "Cycling short-lived links."
      ]

      Application.put_env(:dripstone, Alerts, trigger_types: config[:trigger_types] ++ [extra])

      {:ok, view, _html} = live(conn, "/alerts")

      assert has_element?(
               view,
               "#alert-filters select[name='filters[trigger]'] option[value=link_rotation]",
               "Link rotation"
             )

      assert has_element?(
               view,
               "#alert-filters select[name='filters[platform]'] option[value=mastodon]",
               "Mastodon"
             )
    end
  end

  describe "live arrival" do
    test "a matching new alert appears at the top, highlighted", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/alerts")
      {:ok, %{alert: alert}} = Tracker.report_finding(finding("medium"))

      assert [first | _] = row_ids(view)
      assert first == "alert-row-#{alert.id}"
      assert has_element?(view, "#alert-row-#{alert.id}[data-new]", "New")
      assert has_element?(view, "#alert-count", "11 open")
    end

    test "an alert outside the filters doesn't change the list", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/alerts?severity=high")
      before = row_ids(view)

      {:ok, %{alert: alert}} = Tracker.report_finding(finding("low"))

      assert row_ids(view) == before
      refute has_element?(view, "#alert-row-#{alert.id}")
    end

    test "an alert decided elsewhere leaves the Open inbox", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/alerts")
      [%{alert: alert} | _] = Tracker.list_alerts()

      {:ok, _} = Tracker.confirm_alert(alert.id)

      refute has_element?(view, "#alert-row-#{alert.id}")
      assert has_element?(view, "#alert-count", "9 open")
    end

    test "the highlight clears when the filters change", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/alerts")
      {:ok, %{alert: alert}} = Tracker.report_finding(finding("high"))
      assert has_element?(view, "#alert-row-#{alert.id}[data-new]")

      view |> form("#alert-filters", filters: %{severity: "high"}) |> render_change()

      assert has_element?(view, "#alert-row-#{alert.id}")
      refute has_element?(view, "#alert-row-#{alert.id}[data-new]")
    end
  end
end
