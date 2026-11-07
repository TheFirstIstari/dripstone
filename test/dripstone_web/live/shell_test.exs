defmodule DripstoneWeb.ShellTest do
  # Reads and changes the app-wide tracker store, so it must not run alongside other tests.
  use DripstoneWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  alias Dripstone.Tracker
  alias Dripstone.Tracker.SampleStore

  @sections [
    {"/", "overview", "Overview"},
    {"/alerts", "alerts", "Alerts"},
    {"/networks", "networks", "Networks"},
    {"/accounts", "accounts", "Accounts"},
    {"/feeds", "feeds", "Feeds"}
  ]

  setup do
    previous = SampleStore.get_state()
    on_exit(fn -> SampleStore.put_state(previous) end)
    Tracker.reset_sample_data!()
    :ok
  end

  defp finding(severity, network_id \\ "net-c0421") do
    %{
      trigger: "promotion_shift",
      severity: severity,
      title: "Shift for #{network_id}",
      observed_at: DateTime.utc_now(),
      network_id: network_id,
      evidence: [%{explanation: "Links switched domain.", strength: "strong"}]
    }
  end

  defp title(html),
    do: html |> LazyHTML.from_document() |> LazyHTML.query("head > title") |> LazyHTML.text()

  describe "navigation" do
    for {path, key, _title} <- @sections do
      test "#{path} marks #{key} as the active section", %{conn: conn} do
        {:ok, view, _html} = live(conn, unquote(path))

        assert has_element?(view, "#nav-#{unquote(key)}[aria-current=page]")

        for {_path, other, _title} <- @sections, other != unquote(key) do
          refute has_element?(view, "#nav-#{other}[aria-current=page]")
        end
      end
    end

    test "nav links reach every section", %{conn: conn} do
      for {path, key, _title} <- @sections, key != "overview" do
        {:ok, view, _html} = live(conn, "/")

        assert {:error, {:live_redirect, %{to: ^path}}} =
                 view |> element("#nav-#{key}") |> render_click()
      end
    end

    test "the drawer has its own copy of the navigation for narrow screens", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/networks")
      assert has_element?(view, "#open-nav")
      assert has_element?(view, "#nav-drawer #drawer-nav-networks[aria-current=page]")
    end
  end

  describe "open-alert badge" do
    test "shows the number of open alerts", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/accounts")

      assert has_element?(view, "#nav-alerts-badge", "10")
    end

    test "updates live when an alert is raised in another session", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/accounts")
      {:ok, %{action: :created}} = Tracker.report_finding(finding("medium"))

      assert has_element?(view, "#nav-alerts-badge", "11")
    end

    test "is hidden when no alerts are open", %{conn: conn} do
      for %{alert: alert} <- Tracker.list_alerts(), do: {:ok, _} = Tracker.dismiss_alert(alert.id)

      {:ok, view, _html} = live(conn, "/")
      refute has_element?(view, "#nav-alerts-badge")
    end
  end

  describe "live toasts" do
    test "a High severity alert shows a toast linking to it", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      {:ok, %{alert: alert}} = Tracker.report_finding(finding("high"))

      assert has_element?(view, "#toast-#{alert.id}[data-toast]", alert.title)
      assert has_element?(view, ~s(#toast-#{alert.id} a[href="/alerts/#{alert.id}"]))
    end

    test "a Medium severity alert does not toast", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      {:ok, _} = Tracker.report_finding(finding("medium"))

      _ = render(view)
      refute has_element?(view, "[data-toast]")
    end

    test "toasts can be dismissed and stack at most three", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      for network <- ~w(net-c0421 net-c0422 net-c0425 net-lumen),
          do: {:ok, _} = Tracker.report_finding(finding("high", network))

      _ = render(view)

      assert view
             |> render()
             |> LazyHTML.from_document()
             |> LazyHTML.query("[data-toast]")
             |> Enum.count() == 3

      [first | _] =
        view
        |> render()
        |> LazyHTML.from_document()
        |> LazyHTML.query("[data-toast]")
        |> LazyHTML.attribute("id")

      view |> element("##{first} button[phx-click=dismiss_toast]") |> render_click()
      refute has_element?(view, "##{first}")
    end
  end

  test "top bar search opens Accounts filtered to the query, from any screen", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/networks")

    assert {:error, {:live_redirect, %{to: "/accounts?q=crypto_"}}} =
             view |> form("#global-search", %{q: "crypto_"}) |> render_submit()
  end

  describe "page titles" do
    for {path, _key, title} <- @sections do
      test "#{path} is titled #{title} · Dripstone", %{conn: conn} do
        {:ok, _view, html} = live(conn, unquote(path))

        assert title(html) == "#{unquote(title)} · Dripstone"
      end
    end

    test "no Phoenix branding remains", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      refute html =~ "Phoenix Framework"
      refute html =~ "phoenixframework.org"
    end
  end

  test "the Sample data indicator is on every screen", %{conn: conn} do
    for {path, _key, _title} <- @sections do
      {:ok, view, _html} = live(conn, path)
      assert has_element?(view, "#data-source", "Sample data")
    end
  end

  describe "not-found pages stay inside the shell" do
    for {path, back} <- [
          {"/alerts/does-not-exist", "/alerts"},
          {"/networks/does-not-exist", "/networks"},
          {"/accounts/does-not-exist", "/accounts"}
        ] do
      test path, %{conn: conn} do
        {:ok, view, _html} = live(conn, unquote(path))

        assert has_element?(view, "#not-found")
        assert has_element?(view, ~s(#not-found-back[href="#{unquote(back)}"]))
        assert has_element?(view, "#sidebar")
      end
    end
  end

  test "detail pages for existing items render with their titles", %{conn: conn} do
    [%{alert: alert} | _] = Tracker.list_alerts()
    {:ok, _view, html} = live(conn, "/alerts/#{alert.id}")
    assert title(html) == "#{alert.title} · Dripstone"

    {:ok, _view, html} = live(conn, "/networks/net-sunrise")
    assert title(html) == "Discount Spam Ring · Dripstone"

    [member | _] = Tracker.get_network("net-c0421").network.member_ids
    {:ok, view, _html} = live(conn, "/accounts/#{member}")
    refute has_element?(view, "#not-found")
  end
end
