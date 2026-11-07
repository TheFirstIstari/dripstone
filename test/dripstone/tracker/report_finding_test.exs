defmodule Dripstone.Tracker.ReportFindingTest do
  # Uses the shared, app-wide store, so it must not run alongside other tests.
  use ExUnit.Case, async: false

  import Dripstone.TrackerFixtures

  alias Dripstone.Tracker
  alias Dripstone.Tracker.{SampleStore, State}

  setup do
    previous = SampleStore.get_state()
    :ok = SampleStore.put_state(%State{})
    on_exit(fn -> SampleStore.put_state(previous) end)
    :ok = Tracker.subscribe()
    :ok
  end

  defp noul(p), do: %{"type" => "noul", "noul" => p}

  defp group(handles, extra \\ %{}) do
    Map.merge(
      %{
        "kind" => "group",
        "observed_at" => DateTime.to_iso8601(DateTime.utc_now()),
        "accounts" => Enum.map(handles, &%{"feed_id" => "x", "handle" => &1}),
        "answers" => %{"coordinated" => noul(0.9)}
      },
      extra
    )
  end

  test "a group finding raises an alert and broadcasts the alert, network and accounts" do
    assert {:ok,
            %{alerts: [%{action: :created, alert: alert}], network_id: nid, account_ids: ids}} =
             Tracker.report_finding(group(["a", "b"]))

    assert_receive {:alert_raised, ^alert}
    assert_receive {:network_updated, ^nid}
    for id <- ids, do: assert_receive({:account_updated, ^id})
    assert SampleStore.get_state().alerts[alert.id] == alert
  end

  test "one finding can raise two alerts, each broadcast" do
    {:ok, %{network_id: nid}} = Tracker.report_finding(group(["a", "b"]))

    domains = %{"domains" => [%{"domain" => "deals.example", "share" => 0.7}]}

    assert {:ok, %{alerts: [%{alert: growth}, %{alert: shift}]}} =
             Tracker.report_finding(
               group(["a", "b", "c"], %{"network_id" => nid, "heuristics" => domains})
             )

    assert growth.trigger_id == "network_growth"
    assert shift.trigger_id == "promotion_shift"
    assert_receive {:alert_raised, ^growth}
    assert_receive {:alert_raised, ^shift}
  end

  test "an account finding updates the account and raises nothing" do
    attrs = %{
      kind: "account",
      observed_at: DateTime.utc_now(),
      account: %{feed_id: "reddit", handle: "bob"},
      heuristics: %{score: 40, labels: []},
      answers: nil
    }

    assert {:ok, %{alerts: [], account_ids: [id]}} = Tracker.report_finding(attrs)
    assert_receive {:account_updated, ^id}
    refute_received {:alert_raised, _}
  end

  test "a rejected finding returns the reasons, changes nothing and broadcasts nothing" do
    before = SampleStore.get_state()

    assert {:error, %{kind: ["must be account, group or trend"]}} =
             Tracker.report_finding(group(["a", "b"], %{"kind" => "does-not-exist"}))

    assert SampleStore.get_state() == before
    refute_received _any
  end

  test "a stale finding on a dismissed network raises no alert and says why" do
    {:ok, %{network_id: nid}} = Tracker.report_finding(group(["a", "b"]))
    future = DateTime.add(DateTime.utc_now(), 3600, :second)
    :ok = SampleStore.put_state(dismiss(SampleStore.get_state(), nid, future))
    flush()

    assert {:ok, %{alerts: [], reason: :predates_dismissal}} =
             Tracker.report_finding(group(["a", "b", "c"], %{"network_id" => nid}))

    refute_received {:alert_raised, _}
    refute_received {:alert_updated, _}
  end

  test "new links appear in the graph without a membership change" do
    {:ok, %{network_id: nid}} = Tracker.report_finding(group(["a", "b", "c"]))
    assert Tracker.network_graph(nid).edges == []

    relation = %{"type" => "choice", "choice" => "timing-sync", "confidence" => 0.8}
    answers = %{"coordinated" => noul(0.9), "relation" => relation}

    {:ok, %{alerts: []}} =
      Tracker.report_finding(group(["a", "b", "c"], %{"network_id" => nid, "answers" => answers}))

    edges = Tracker.network_graph(nid).edges
    assert length(edges) == 3
    assert Enum.all?(edges, &(&1.kind == :timing_sync))
  end

  test "internal findings still run straight through the intake (tests and sample data)" do
    finding = new_network_finding(%{observed_at: DateTime.utc_now()})
    :ok = SampleStore.put_state(state_with_accounts(finding))
    {:ok, _} = SampleStore.apply_finding(finding)
    assert_receive {:alert_raised, %{trigger_id: "new_network"}}
  end

  defp flush do
    receive do
      _ -> flush()
    after
      0 -> :ok
    end
  end
end
