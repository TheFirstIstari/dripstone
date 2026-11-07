defmodule DripstoneWeb.DigestLiveTest do
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
end
