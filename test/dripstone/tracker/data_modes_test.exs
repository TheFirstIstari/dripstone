defmodule Dripstone.Tracker.DataModesTest do
  # Scenarios from the data-modes spec (add-bluesky-live-pipeline). Uses the shared
  # Demo store and the Live rows, so not async.
  use Dripstone.DataCase, async: false

  alias Dripstone.Tracker
  alias Dripstone.Tracker.{DemoStore, Simulator, Store}

  defp noul(p), do: %{"type" => "noul", "noul" => p}

  defp group(handles) do
    %{
      "kind" => "group",
      "observed_at" => DateTime.to_iso8601(DateTime.utc_now()),
      "accounts" => Enum.map(handles, &%{"feed_id" => "x", "handle" => &1}),
      "answers" => %{"coordinated" => noul(0.9)}
    }
  end

  defp live_networks,
    do: Tracker.with_dataset(:live, fn -> map_size(elem(Store.load(), 1).networks) end)

  defp demo_networks, do: map_size(DemoStore.load().networks)

  test "code with no dataset set reads Live" do
    assert Tracker.dataset() == :live
  end

  test "Demo starts once and is reused, seeded with the sample data" do
    :ok = DemoStore.ensure_started()
    pid = Process.whereis(DemoStore)
    :ok = DemoStore.ensure_started()
    assert Process.whereis(DemoStore) == pid
    assert map_size(DemoStore.load().accounts) > 100
  end

  test "a change in Demo leaves Live untouched (Isolated changes, Demo is never persisted)" do
    live_before = live_networks()
    demo_before = demo_networks()

    {:ok, %{alerts: [%{alert: alert}]}} =
      Tracker.with_dataset(:demo, fn -> Tracker.report_finding(group(["demo_a", "demo_b"])) end)

    assert alert.trigger_id == "new_network"
    assert demo_networks() == demo_before + 1
    assert live_networks() == live_before
  end

  test "Demo broadcasts don't reach Live subscribers, and vice versa" do
    :ok = Tracker.subscribe()

    Tracker.with_dataset(:demo, fn -> Tracker.report_finding(group(["iso_a", "iso_b"])) end)
    refute_receive {:alert_raised, _}, 200

    Tracker.with_dataset(:demo, fn -> Tracker.subscribe() end)
    {:ok, _} = Tracker.report_finding(group(["live_a", "live_b"]))
    assert_receive {:alert_raised, %{trigger_id: "new_network"}}
  end

  test "the simulator started for Demo writes to Demo only (Simulator writes to Demo only)" do
    live_before = live_networks()
    demo_before = demo_networks()

    pid =
      start_supervised!(
        {Simulator,
         dataset: :demo,
         interval: 60_000,
         first_assess: 60_000,
         enqueue: fn job -> {:ok, job} end,
         kinds: [:new],
         name: :data_modes_simulator}
      )

    send(pid, :tick)
    _ = :sys.get_state(pid)

    assert demo_networks() == demo_before + 1
    assert live_networks() == live_before
  end
end
