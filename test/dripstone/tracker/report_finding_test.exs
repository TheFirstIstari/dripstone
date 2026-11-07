defmodule Dripstone.Tracker.ReportFindingTest do
  # Uses the shared, app-wide store, so it must not run alongside other tests.
  use ExUnit.Case, async: false

  import Dripstone.TrackerFixtures

  alias Dripstone.Tracker
  alias Dripstone.Tracker.{SampleStore, State}

  setup do
    previous = SampleStore.get_state()
    :ok = SampleStore.put_state(state_with_accounts())
    on_exit(fn -> SampleStore.put_state(previous) end)
    :ok = Tracker.subscribe()
    :ok
  end

  test "a new finding is applied and broadcast as a raised alert" do
    assert {:ok, %{action: :created, alert: alert}} =
             Tracker.report_finding(new_network_finding())

    assert_receive {:network_updated, "net-1"}
    assert_receive {:alert_raised, ^alert}
    assert SampleStore.get_state().alerts[alert.id] == alert
  end

  test "a merged finding is broadcast as an updated alert" do
    {:ok, _} = Tracker.report_finding(new_network_finding())
    {:ok, %{action: :created, alert: %{id: id}}} = Tracker.report_finding(finding("net-1"))
    {:ok, %{action: :merged}} = Tracker.report_finding(finding("net-1", %{severity: "high"}))

    assert_receive {:alert_updated, %{id: ^id, severity: :high}}
  end

  test "decoded JSON payloads are accepted" do
    assert {:ok, %{action: :created}} = Tracker.report_finding(stringify(new_network_finding()))
  end

  test "a rejected finding returns the reasons, changes nothing and broadcasts nothing" do
    {:ok, _} = Tracker.report_finding(new_network_finding())
    flush()
    before = SampleStore.get_state()

    assert {:error, %{trigger: ["unknown trigger \"does-not-exist\""]}} =
             Tracker.report_finding(finding("net-1", %{trigger: "does-not-exist"}))

    assert SampleStore.get_state() == before
    refute_received _any
  end

  test "an ignored (stale) finding broadcasts nothing" do
    {:ok, _} = Tracker.report_finding(new_network_finding())
    :ok = SampleStore.put_state(dismiss(SampleStore.get_state(), "net-1", at(10)))
    flush()

    assert {:ok, %{action: :ignored, reason: :predates_dismissal}} =
             Tracker.report_finding(finding("net-1", %{observed_at: at(5)}))

    refute_received _any
  end

  defp flush do
    receive do
      _ -> flush()
    after
      0 -> :ok
    end
  end
end
