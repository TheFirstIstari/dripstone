defmodule DripstoneWeb.NetworkLive.IndexTest do
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

  defp row_ids(view),
    do:
      view
      |> render()
      |> LazyHTML.from_document()
      |> LazyHTML.query("#networks > li[id^=network-row]")
      |> LazyHTML.attribute("id")

  defp expected(filters),
    do: Enum.map(Tracker.list_networks(filters), &"network-row-#{&1.network.id}")

  test "lists every network, most recently active first", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/networks")

    assert row_ids(view) == expected(%{})
    assert length(row_ids(view)) == 12
    assert has_element?(view, "#network-count", "12 networks")
  end

  test "rows show name, tags, status, confidence, size, open alerts and link to the network", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/networks")
    row = "#network-row-net-sunrise"

    assert has_element?(view, row, "Discount Spam Ring")
    assert has_element?(view, row, "#discount-spam")
    assert has_element?(view, "#{row} [data-status=suspected]")
    assert has_element?(view, row, "88%")
    assert has_element?(view, "#{row} [data-open-alerts=\"2\"]", "2 open alerts")
    assert has_element?(view, ~s(#{row} a[href="/networks/net-sunrise"]))
  end

  test "filtering to Suspected lists only Suspected networks and records it in the URL", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/networks")

    view |> form("#network-filters", filters: %{status: "suspected"}) |> render_change()

    assert_patch(view, "/networks?status=suspected")
    assert row_ids(view) == expected(%{status: :suspected})

    assert Enum.all?(
             Tracker.list_networks(%{status: :suspected}),
             &(&1.network.status == :suspected)
           )
  end

  test "filters by tag and platform, restored from the URL", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/networks?tag=discount-spam")
    assert row_ids(view) == ["network-row-net-sunrise"]

    {:ok, view, _html} = live(conn, "/networks?platform=mastodon&status=suspected")
    assert row_ids(view) == expected(%{platform: "mastodon", status: :suspected})
  end

  test "unknown filter values are ignored", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/networks?status=bogus&platform=myspace&tag=nope")
    assert row_ids(view) == expected(%{})
  end

  test "an empty result offers to clear the filters", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/networks?tag=discount-spam&status=confirmed")

    assert row_ids(view) == []
    assert has_element?(view, "#networks-empty", "No networks match these filters")
  end

  test "networks retired by a merge are not listed", %{conn: conn} do
    {:ok, _} = Tracker.merge_networks("net-driftwood", "net-sunrise")
    {:ok, view, _html} = live(conn, "/networks")

    refute has_element?(view, "#network-row-net-driftwood")
    assert length(row_ids(view)) == 11
  end

  test "updates live when a network changes", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/networks")
    {:ok, _} = Tracker.rename_network("net-c0421", %{"name" => "Rally Ticket Bots"})

    assert has_element?(view, "#network-row-net-c0421", "Rally Ticket Bots")
  end
end
