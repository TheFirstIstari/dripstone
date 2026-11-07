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
    for {id, severity} <- [{"net-big", "high"}, {"net-quiet", "low"}] do
      assert {:ok, _} =
               Tracker.report_finding(%{
                 trigger: "new_network",
                 severity: severity,
                 title: "#{id} detected",
                 observed_at: DateTime.utc_now(),
                 new_network: %{
                   id: id,
                   name: id,
                   member_ids: ["acc-0001", "acc-0002"],
                   confidence: 90,
                   platforms: ["x"]
                 },
                 evidence: [
                   %{explanation: "Shared links.", strength: "strong", account_ids: ["acc-0001"]}
                 ]
               })
    end

    {:ok, view, _html} = live(conn, "/digest")
    html = render(view)

    assert html =~ "Detected with 2 members (90% confidence)"
    refute html =~ "net-quiet"
    assert html =~ "digest-new_edge-net-big-"
  end
end
