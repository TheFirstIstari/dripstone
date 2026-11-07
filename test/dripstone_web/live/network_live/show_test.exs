defmodule DripstoneWeb.NetworkLive.ShowTest do
  # Changes the app-wide tracker store, so it must not run alongside other tests.
  use DripstoneWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  alias Dripstone.Tracker
  alias Dripstone.Tracker.SampleStore

  setup do
    previous = SampleStore.get_state()
    on_exit(fn -> SampleStore.put_state(previous) end)
    Tracker.reset_sample_data!()
    :ok
  end

  defp ids(view, selector),
    do:
      view
      |> render()
      |> LazyHTML.from_document()
      |> LazyHTML.query(selector)
      |> LazyHTML.attribute("id")

  test "the header shows name, detected name, tags, status, size, main domain and open alerts", %{
    conn: conn
  } do
    {:ok, view, html} = live(conn, "/networks/net-sunrise")

    assert html =~ "Discount Spam Ring · Dripstone"
    assert has_element?(view, "#page-title", "Discount Spam Ring")
    assert has_element?(view, "#detected-as", "Detected as Sunrise Cluster")
    assert has_element?(view, "#tag-discount-spam")
    assert has_element?(view, "#tag-coordinated-promo")
    assert has_element?(view, "#network-header [data-status=suspected]", "Suspected")
    assert has_element?(view, "#main-domain", "deals-b.example")
    assert has_element?(view, "#open-alerts-link", "2 open alerts")
    assert has_element?(view, "#nav-networks[aria-current=page]")
  end

  test "the AI summary is labeled, or the page says there is none", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/networks/net-sunrise")
    assert has_element?(view, "#network-summary [data-ai-label]", "AI-generated")

    {:ok, view, _html} = live(conn, "/networks/net-driftwood")
    assert has_element?(view, "#no-summary", "No summary has been generated")
    refute has_element?(view, "#network-summary [data-ai-label]")
  end

  test "shared evidence is listed strongest first with how many members it involves", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/networks/net-sunrise")

    assert has_element?(view, "#shared-evidence-0 [data-strength=strong]")
    assert has_element?(view, "#shared-evidence-0", "involving")
    assert has_element?(view, "#shared-evidence-2 [data-strength=moderate]")
  end

  test "the posting heatmap names the busiest period", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/networks/net-sunrise")

    assert has_element?(
             view,
             "#network-heatmap [data-summary]",
             "Busiest: Weekdays 09:00–10:00 UTC"
           )
  end

  test "members are listed by risk and link to their account pages", %{conn: conn} do
    %{members: [top | _] = members} = Tracker.get_network("net-sunrise")
    {:ok, view, _html} = live(conn, "/networks/net-sunrise")

    assert length(ids(view, "#member-list > li[id^=member-]")) == length(members)
    assert hd(ids(view, "#member-list > li[id^=member-]")) == "member-#{top.account.id}"

    assert {:error, {:live_redirect, %{to: to}}} =
             view |> element("#member-#{top.account.id} a") |> render_click()

    assert to == "/accounts/#{top.account.id}"
  end

  test "alert history marks re-alerts of a previously dismissed network", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/networks/net-echo")

    alerts = ids(view, "#network-alerts > li[id^=network-alert-]")
    assert length(alerts) == 2
    assert has_element?(view, "#network-alerts [data-status=dismissed]")

    assert has_element?(
             view,
             "#network-alerts [data-previously-dismissed]",
             "Previously dismissed"
           )
  end

  test "related networks are listed", %{conn: conn} do
    {:ok, _} = Tracker.relate_networks("net-sunrise", "net-c0425")
    {:ok, view, _html} = live(conn, "/networks/net-sunrise")

    assert has_element?(view, ~s(#related-net-c0425 a[href="/networks/net-c0425"]))
  end

  test "a merged network says so and links to where it went", %{conn: conn} do
    {:ok, _} = Tracker.merge_networks("net-driftwood", "net-sunrise")
    {:ok, view, _html} = live(conn, "/networks/net-driftwood")

    assert has_element?(view, "#merged-notice", "This network was merged")

    assert has_element?(
             view,
             ~s(#merged-into[href="/networks/net-sunrise"]),
             "Discount Spam Ring"
           )

    refute has_element?(view, "#network-tabs")
  end

  test "updates live when detection changes the network", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/networks/net-c0421")

    {:ok, _} =
      SampleStore.apply_finding(%{
        trigger: "promotion_shift",
        severity: "high",
        title: "Shift",
        observed_at: DateTime.utc_now(),
        network_id: "net-c0421",
        evidence: [%{explanation: "Switched domain.", strength: "strong"}],
        network_updates: %{main_domain: "rally-b.example"}
      })

    assert has_element?(view, "#main-domain", "rally-b.example")
    assert has_element?(view, "#open-alerts-link", "2 open alerts")
  end
end
