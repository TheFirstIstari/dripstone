defmodule DripstoneWeb.FeedLiveTest do
  # Uses the app-wide tracker store and changes app env, so it must not run alongside other tests.
  use DripstoneWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  alias Dripstone.Feeds
  alias Dripstone.Tracker
  alias Dripstone.Tracker.Store

  setup do
    {:ok, previous} = Store.load()
    on_exit(fn -> :ok = Store.save(previous) end)
    Tracker.reset_sample_data!()
    :ok
  end

  defp row_ids(view),
    do:
      view
      |> render()
      |> LazyHTML.from_document()
      |> LazyHTML.query("#feeds > tr[id^=feed-]")
      |> LazyHTML.attribute("id")

  test "lists all six feeds in registry order with their health", %{conn: conn} do
    {:ok, view, html} = live(conn, "/feeds")

    assert html =~ "Feeds · Dripstone"
    assert has_element?(view, "#nav-feeds[aria-current=page]")

    assert row_ids(view) ==
             ~w(feed-x feed-reddit feed-bluesky feed-mastodon feed-telegram feed-facebook)

    assert has_element?(view, "#feed-x", "X")
    assert has_element?(view, "#feed-x [data-status=healthy]", "Healthy")
    assert has_element?(view, "#feed-x", "18,204")
    assert has_element?(view, "#feed-x", "402")
    assert has_element?(view, "#feed-x time")
    assert has_element?(view, "#feed-facebook [data-status=degraded]", "Degraded")
  end

  test "a Down feed shows its most recent error and when it happened", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/feeds")

    assert has_element?(view, "#feed-telegram [data-status=down]", "Down")
    assert has_element?(view, "#feed-telegram [data-last-error]", "401 Unauthorized")
    assert has_element?(view, "#feed-telegram [data-last-error] time")
  end

  test "is read-only and points to the doc for adding feeds", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/feeds")

    assert has_element?(
             view,
             "#feeds-how-to-add",
             "openspec/docs/FEEDS.md"
           )

    refute has_element?(view, "#feeds button")
    refute has_element?(view, "#feeds form")
    refute has_element?(view, "#feeds a")
  end

  test "a newly registered feed appears with no other change", %{conn: conn} do
    config = Application.get_env(:dripstone, Feeds)
    on_exit(fn -> Application.put_env(:dripstone, Feeds, config) end)

    Application.put_env(:dripstone, Feeds,
      feeds: config[:feeds] ++ [Dripstone.Test.ThrowawayFeed]
    )

    {:ok, view, _html} = live(conn, "/feeds")

    assert List.last(row_ids(view)) == "feed-threads"
    assert has_element?(view, "#feed-threads", "Threads")
    assert has_element?(view, "#feed-threads [data-status=not_connected]", "Not connected")
  end
end
