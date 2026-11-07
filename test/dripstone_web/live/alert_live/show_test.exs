defmodule DripstoneWeb.AlertLive.ShowTest do
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

  # The open "new network" alert of a Suspected network with no other alerts.
  defp lone_alert(network_id) do
    [%{alert: alert}] = Tracker.list_alerts() |> Enum.filter(&(&1.network.id == network_id))
    alert
  end

  defp promotion_shift do
    [%{alert: alert}] = Tracker.list_alerts(%{trigger: "promotion_shift"})
    alert
  end

  defp decide(view, action, note \\ "") do
    view
    |> form("#decision-form", decision: %{note: note})
    |> render_submit(%{"action" => action})
  end

  describe "alert details" do
    test "shows the fields, network, evidence strongest first and before/after values", %{
      conn: conn
    } do
      alert = promotion_shift()
      {:ok, view, html} = live(conn, "/alerts/#{alert.id}")

      assert html =~ "#{alert.title} · Dripstone"
      assert has_element?(view, "#page-title", alert.title)
      assert has_element?(view, "[data-severity=high]", "High")
      assert has_element?(view, "header", "Promotion shift")
      assert has_element?(view, "[data-status=open]", "Open")

      assert has_element?(view, "#network-card", "Discount Spam Ring")
      assert has_element?(view, ~s(#network-card a[href="/networks/net-sunrise"]))

      assert has_element?(view, "#evidence-0 [data-strength=strong]", "Strong")
      assert has_element?(view, "#evidence-1 [data-strength=moderate]")
      assert has_element?(view, "#evidence-0 a[href^='/accounts/']")

      assert has_element?(view, "#comparison-before", "deals-a.example (62% of links)")
      assert has_element?(view, "#comparison-after", "deals-b.example (55% of links)")
    end

    test "the AI rationale is labeled as AI-generated", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/alerts/#{promotion_shift().id}")
      assert has_element?(view, "#ai-rationale [data-ai-label]", "AI-generated")
    end

    test "alerts without AI text or a comparison simply omit those sections", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/alerts/#{lone_alert("net-driftwood").id}")
      refute has_element?(view, "#ai-rationale")
      refute has_element?(view, "#comparison")
      assert has_element?(view, "#evidence")
    end

    test "a re-alert links to the dismissed alert", %{conn: conn} do
      alert = lone_alert("net-echo")
      {:ok, view, _html} = live(conn, "/alerts/#{alert.id}")

      assert has_element?(
               view,
               ~s(#previously-dismissed[href="/alerts/#{alert.previously_dismissed_alert_id}"])
             )
    end
  end

  describe "decisions" do
    test "confirming sets the alert and network to Confirmed and shows the decision", %{
      conn: conn
    } do
      alert = lone_alert("net-c0421")
      {:ok, view, _html} = live(conn, "/alerts/#{alert.id}")

      decide(view, "confirm", "Same copy everywhere.")

      assert has_element?(view, "#decision-made", "Confirmed")
      assert has_element?(view, "#decision-made", "by Unattributed")
      assert has_element?(view, "#decision-note-text", "Same copy everywhere.")
      assert has_element?(view, "#network-card [data-status=confirmed]")
      refute has_element?(view, "#decision-form")
    end

    test "dismissing the only alert dismisses the network", %{conn: conn} do
      alert = lone_alert("net-c0422")
      {:ok, view, _html} = live(conn, "/alerts/#{alert.id}")

      decide(view, "dismiss")

      assert has_element?(view, "#decision-made", "Dismissed")
      assert has_element?(view, "#network-card [data-status=dismissed]")
      assert Tracker.get_network("net-c0422").network.status == :dismissed
    end

    test "undo restores the alert and network until the next decision", %{conn: conn} do
      alert = lone_alert("net-c0425")
      {:ok, view, _html} = live(conn, "/alerts/#{alert.id}")

      decide(view, "dismiss")
      view |> element("#undo-decision") |> render_click()

      assert has_element?(view, "#decision-form")
      assert has_element?(view, "header [data-status=open]")
      assert has_element?(view, "#network-card [data-status=suspected]")
      refute has_element?(view, "#undo-decision")
    end

    test "a note over 500 characters is refused with an explanation", %{conn: conn} do
      alert = lone_alert("net-c0421")
      {:ok, view, _html} = live(conn, "/alerts/#{alert.id}")

      decide(view, "confirm", String.duplicate("x", 501))

      assert has_element?(view, "#decision-form", "should be at most 500 character(s)")
      assert Tracker.get_alert(alert.id).alert.status == :open
    end

    test "the note counter and validation update while typing", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/alerts/#{lone_alert("net-c0421").id}")

      html = view |> form("#decision-form", decision: %{note: "abc"}) |> render_change()
      assert html =~ "3/500"
    end

    test "decided alerts are read-only", %{conn: conn} do
      alert = lone_alert("net-c0421")
      {:ok, _} = Tracker.confirm_alert(alert.id, %{"note" => "Reviewed."})

      {:ok, view, _html} = live(conn, "/alerts/#{alert.id}")

      assert has_element?(view, "#decision-made", "Confirmed")
      refute has_element?(view, "#decision-form")

      refute has_element?(view, "#undo-decision"),
             "undo is only offered for your own last decision"
    end
  end

  describe "moving through the inbox" do
    test "j/k neighbours follow the inbox the alert was opened from", %{conn: conn} do
      [first, second, third | _] =
        Tracker.list_alerts(%{status: :open}) |> Enum.map(& &1.alert.id)

      {:ok, view, _html} = live(conn, "/alerts/#{second}")

      assert has_element?(view, "#alert-position", "2 of 10")
      assert has_element?(view, ~s(#prev-alert[href="/alerts/#{first}"]))
      assert has_element?(view, ~s(#next-alert[href="/alerts/#{third}"]))
    end

    test "the inbox filters are carried along", %{conn: conn} do
      [a, b] = Tracker.list_alerts(%{trigger: "network_growth"}) |> Enum.map(& &1.alert.id)
      {:ok, view, _html} = live(conn, "/alerts/#{a}?trigger=network_growth")

      assert has_element?(view, "#alert-position", "1 of 2")
      assert has_element?(view, ~s(#next-alert[href="/alerts/#{b}?trigger=network_growth"]))
      assert has_element?(view, ~s(a[href="/alerts?trigger=network_growth"]), "Alerts")
    end
  end

  describe "keyboard shortcut events (sent by the .AlertShortcuts hook)" do
    test "the hook element is present with a unique id and knows the alert is open", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/alerts/#{lone_alert("net-c0421").id}")
      assert has_element?(view, "#alert-shortcuts[phx-hook][data-open=true]")
    end

    test "c confirms with the typed note", %{conn: conn} do
      alert = lone_alert("net-c0421")
      {:ok, view, _html} = live(conn, "/alerts/#{alert.id}")

      view
      |> element("#alert-shortcuts")
      |> render_hook("decide", %{"action" => "confirm", "decision" => %{"note" => "From keys"}})

      assert has_element?(view, "#decision-note-text", "From keys")
      assert has_element?(view, "#alert-shortcuts[data-open=false]")
    end

    test "d dismisses", %{conn: conn} do
      alert = lone_alert("net-c0422")
      {:ok, view, _html} = live(conn, "/alerts/#{alert.id}")

      view |> element("#alert-shortcuts") |> render_hook("decide", %{"action" => "dismiss"})
      assert has_element?(view, "#decision-made", "Dismissed")
    end

    test "j and k navigate to the neighbours", %{conn: conn} do
      [first, second | _] = Tracker.list_alerts() |> Enum.map(& &1.alert.id)
      {:ok, view, _html} = live(conn, "/alerts/#{second}")

      assert {:error, {:live_redirect, %{to: to}}} =
               view |> element("#alert-shortcuts") |> render_hook("navigate", %{"to" => "prev"})

      assert to == "/alerts/#{first}"
    end

    test "deciding an already-decided alert by key does nothing harmful", %{conn: conn} do
      alert = lone_alert("net-c0421")
      {:ok, view, _html} = live(conn, "/alerts/#{alert.id}")
      {:ok, _} = Tracker.dismiss_alert(alert.id)

      view |> element("#alert-shortcuts") |> render_hook("decide", %{"action" => "confirm"})

      assert Tracker.get_alert(alert.id).alert.status == :dismissed
      assert has_element?(view, "#decision-made", "Dismissed")
    end
  end

  test "a decision elsewhere updates the open page live", %{conn: conn} do
    alert = lone_alert("net-c0421")
    {:ok, view, _html} = live(conn, "/alerts/#{alert.id}")

    {:ok, _} = Tracker.confirm_alert(alert.id)

    assert has_element?(view, "#decision-made", "Confirmed")
    refute has_element?(view, "#decision-form")
  end
end
