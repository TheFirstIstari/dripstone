defmodule DripstoneWeb.DataModesLiveTest do
  # data-modes and ui-shell scenarios: the per-session Live/Demo switch.
  use DripstoneWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Dripstone.AccountsFixtures

  setup :register_and_log_in_user

  test "a fresh session shows Live, with no demo banner (Fresh session, Live data in use)",
       %{conn: conn} do
    {:ok, view, html} = live(conn, "/alerts")

    assert has_element?(view, "#data-source[data-mode=live]", "Live")
    refute has_element?(view, "#demo-banner")
    refute html =~ "Sample data"
  end

  test "switching to Demo keeps the analyst on the page and shows Demo everywhere (Switch to Demo)",
       %{conn: conn} do
    conn =
      conn
      |> put_req_header("referer", "http://localhost/alerts?status=open")
      |> post("/mode", %{"mode" => "demo"})

    assert redirected_to(conn) == "/alerts?status=open"

    conn = recycle(conn)
    {:ok, view, _html} = live(conn, "/alerts")
    assert has_element?(view, "#data-source[data-mode=demo]", "Demo")
    assert has_element?(view, "#demo-banner", "Demo data")

    {:ok, view, _html} = live(conn, "/networks")
    assert has_element?(view, "#demo-banner")
  end

  test "another analyst's session stays on Live", %{conn: conn} do
    conn |> post("/mode", %{"mode" => "demo"})

    other = build_conn() |> log_in_user(user_fixture())
    {:ok, view, _html} = live(other, "/alerts")
    assert has_element?(view, "#data-source[data-mode=live]")
  end

  test "switching back to Live removes the banner", %{conn: conn} do
    conn =
      conn
      |> post("/mode", %{"mode" => "demo"})
      |> recycle()
      |> post("/mode", %{"mode" => "live"})

    {:ok, view, _html} = live(recycle(conn), "/alerts")
    assert has_element?(view, "#data-source[data-mode=live]")
    refute has_element?(view, "#demo-banner")
  end

  test "an external referer can't be used to redirect away", %{conn: conn} do
    conn =
      conn
      |> put_req_header("referer", "https://evil.example//phish")
      |> post("/mode", %{"mode" => "demo"})

    assert redirected_to(conn) == "/"
  end
end
