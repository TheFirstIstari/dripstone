defmodule DripstoneWeb.DigestLiveTest do
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

  test "empty week shows the empty state and marks the nav section", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/digest")

    assert has_element?(view, "#nav-digest[aria-current=page]")
    assert has_element?(view, "#digest-empty")
  end

  test "a fresh high-severity detection appears; quiet ones stay silent", %{conn: conn} do
    noul = fn p -> %{"type" => "noul", "noul" => p} end

    for {handles, p} <- [{["digesta", "digestb"], 0.95}, {["quieta", "quietb"], 0.5}] do
      assert {:ok, _} =
               Tracker.report_finding(%{
                 "kind" => "group",
                 "observed_at" => DateTime.to_iso8601(DateTime.utc_now()),
                 "accounts" => Enum.map(handles, &%{"feed_id" => "x", "handle" => &1}),
                 "answers" => %{"coordinated" => noul.(p)}
               })
    end

    {:ok, view, _html} = live(conn, "/digest")
    html = render(view)

    assert html =~ "digest-new_edge-"
    refute html =~ "quieta"
  end

  test "two same-second items on one network both render with distinct ids", %{conn: conn} do
    noul = fn -> %{"type" => "noul", "noul" => 0.95} end
    now = DateTime.utc_now()

    for handles <- [["samea", "sameb"], ["samea", "samec"]] do
      assert {:ok, _} =
               Tracker.report_finding(%{
                 "kind" => "group",
                 "observed_at" => DateTime.to_iso8601(now),
                 "accounts" => Enum.map(handles, &%{"feed_id" => "x", "handle" => &1}),
                 "answers" => %{"coordinated" => noul.()}
               })
    end

    items = Tracker.change_digest()
    assert length(items) >= 2

    dom_ids =
      Enum.map(items, &"digest-#{&1.kind}-#{&1.network_id}-#{&1.id}")

    assert length(Enum.uniq(dom_ids)) == length(dom_ids)

    {:ok, view, _html} = live(conn, "/digest")
    html = render(view)
    rows = Regex.scan(~r/id="(digest-[^"]+)"/, html) |> Enum.map(&hd(tl(&1)))

    assert length(Enum.uniq(rows)) == length(rows)
    assert length(rows) >= 2
  end
end
