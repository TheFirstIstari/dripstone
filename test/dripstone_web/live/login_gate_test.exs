defmodule DripstoneWeb.LoginGateTest do
  # Project spec "Analyst login": the app shell and every mutation route require a
  # logged-in analyst. Uses the app-wide tracker store, so not async.
  use DripstoneWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Dripstone.AccountsFixtures

  @screens ~w(/alerts /alerts/alert-1 /networks /networks/net-sunrise /accounts /accounts/acc-0001 /feeds)

  describe "logged out" do
    for path <- @screens do
      test "#{path} redirects to the login page", %{conn: conn} do
        assert {:error, {:redirect, %{to: "/users/log-in", flash: flash}}} =
                 live(conn, unquote(path))

        assert flash["error"] == "You must log in to access this page."
      end
    end

    test "the root is a public landing page with a log-in link (200 for deploy checks)", %{
      conn: conn
    } do
      assert {:ok, view, _html} = live(conn, "/")
      assert has_element?(view, "#landing-log-in", "Log in")
      refute has_element?(view, "#headline-counts")
    end

    test "the plain HTTP request is redirected too", %{conn: conn} do
      conn = get(conn, "/alerts")
      assert redirected_to(conn) == "/users/log-in"
    end

    test "after logging in, the analyst lands where they were heading", %{conn: conn} do
      conn = get(conn, "/alerts")
      assert redirected_to(conn) == "/users/log-in"

      user = user_fixture() |> set_password()

      conn =
        post(recycle(conn), "/users/log-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert redirected_to(conn) == "/alerts"
    end

    test "the login page stays public and registration is closed", %{conn: conn} do
      assert {:ok, _view, _html} = live(conn, "/users/log-in")
      assert html_response(get(conn, "/users/register"), 404) =~ "Not Found"
    end
  end

  describe "logged in" do
    setup :register_and_log_in_user

    test "the shell shows the analyst's email, Settings and Log out", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, "/")

      assert has_element?(view, "#user-email", user.email)
      assert has_element?(view, ~s(#user-menu a[href="/users/settings"]), "Settings")

      assert has_element?(
               view,
               ~s(#user-menu a[href="/users/log-out"][data-method=delete]),
               "Log out"
             )

      refute has_element?(view, ~s(#user-menu a[href="/users/log-in"]))
    end

    test "account settings render inside the same shell, with the live badge", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/users/settings")

      assert has_element?(view, "#sidebar")
      assert has_element?(view, "#nav-alerts-badge")
    end
  end
end
