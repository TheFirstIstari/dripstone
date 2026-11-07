defmodule Dripstone.Tracker.DecisionsTest do
  # Changes the app-wide store, so it must not run alongside other tests.
  use ExUnit.Case, async: false

  alias Dripstone.Tracker
  alias Dripstone.Tracker.{Decision, SampleStore}

  setup do
    previous = SampleStore.get_state()
    on_exit(fn -> SampleStore.put_state(previous) end)
    Tracker.reset_sample_data!()
    :ok = Tracker.subscribe()
    :ok
  end

  # The open "new network" alert of a Suspected network with no other alerts.
  defp lone_alert(network_id) do
    [%{alert: alert}] = Tracker.list_alerts(%{}) |> Enum.filter(&(&1.network.id == network_id))
    alert
  end

  test "confirming sets the alert and its network to Confirmed and records the decision" do
    alert = lone_alert("net-c0421")

    assert {:ok, %{alert: confirmed, decision: %Decision{} = decision, network: network}} =
             Tracker.confirm_alert(alert.id, %{"note" => "  Same copy everywhere.  "})

    assert confirmed.status == :confirmed
    assert network.status == :confirmed
    assert decision.by == "Detection"
    assert decision.note == "Same copy everywhere."
    assert decision.action == :confirm

    detail = Tracker.get_alert(alert.id)
    assert detail.decision.id == decision.id

    assert Enum.any?(
             Tracker.get_network("net-c0421").history,
             &(&1.actor == :analyst and &1.summary =~ "Confirmed")
           )
  end

  test "dismissing the only alert of a Suspected network dismisses the network" do
    alert = lone_alert("net-c0422")

    assert {:ok, %{alert: %{status: :dismissed}, network: %{status: :dismissed}}} =
             Tracker.dismiss_alert(alert.id, %{})
  end

  test "dismissing does not dismiss a network that has a confirmed alert" do
    [%{alert: growth}] =
      Tracker.list_alerts(%{trigger: "network_growth"})
      |> Enum.filter(&(&1.network.id == "net-bluewave"))

    assert {:ok, %{network: %{status: :confirmed}}} = Tracker.dismiss_alert(growth.id)
  end

  test "undo restores both the alert's and the network's previous statuses" do
    alert = lone_alert("net-c0425")
    {:ok, %{decision: decision}} = Tracker.dismiss_alert(alert.id)

    assert {:ok, %{alert: restored, network: network}} = Tracker.undo_decision(decision.id)
    assert restored.status == :open
    assert restored.decision_id == nil
    assert network.status == :suspected
    assert Tracker.get_alert(alert.id).decision == nil
  end

  test "undo of an older decision is refused once a newer decision changed the network" do
    [%{alert: first}, %{alert: second}] =
      Tracker.list_alerts(%{}) |> Enum.filter(&(&1.network.id == "net-sunrise"))

    {:ok, %{decision: older}} = Tracker.dismiss_alert(first.id)
    {:ok, %{decision: _newer}} = Tracker.confirm_alert(second.id)

    assert {:error, :superseded} = Tracker.undo_decision(older.id)
    assert %{alert: %{status: :confirmed}} = Tracker.get_alert(second.id)
  end

  test "an undone or unknown decision can't be undone again" do
    alert = lone_alert("net-c0425")
    {:ok, %{decision: decision}} = Tracker.confirm_alert(alert.id)
    {:ok, _} = Tracker.undo_decision(decision.id)

    assert {:error, :not_found} = Tracker.undo_decision(decision.id)
  end

  test "a note over 500 characters is rejected and nothing changes" do
    alert = lone_alert("net-c0421")
    before = SampleStore.get_state()

    assert {:error, %Ecto.Changeset{action: :insert} = changeset} =
             Tracker.confirm_alert(alert.id, %{"note" => String.duplicate("x", 501)})

    assert {"should be at most %{count} character(s)", _} = changeset.errors[:note]
    assert SampleStore.get_state() == before
    assert {:ok, _} = Tracker.confirm_alert(alert.id, %{"note" => String.duplicate("x", 500)})
  end

  test "decisions and undo are attributed to the acting analyst" do
    alert = lone_alert("net-c0421")

    assert {:ok, %{decision: decision}} =
             Tracker.confirm_alert(alert.id, %{}, "analyst@example.com")

    assert decision.by == "analyst@example.com"

    assert Enum.any?(
             Tracker.get_network("net-c0421").history,
             &(&1.by == "analyst@example.com" and &1.actor == :analyst)
           )

    assert {:ok, _} = Tracker.undo_decision(decision.id, "analyst@example.com")

    assert Enum.any?(
             Tracker.get_network("net-c0421").history,
             &(&1.by == "analyst@example.com" and &1.summary =~ "Undid")
           )
  end

  test "decided alerts can't be decided again" do
    alert = lone_alert("net-c0421")
    {:ok, _} = Tracker.confirm_alert(alert.id)

    assert {:error, :not_open} = Tracker.dismiss_alert(alert.id)
    assert {:error, :not_found} = Tracker.confirm_alert("alert-nope")
  end

  test "decisions are broadcast" do
    alert = lone_alert("net-c0421")
    {:ok, _} = Tracker.confirm_alert(alert.id)

    assert_receive {:alert_updated, %{id: id, status: :confirmed}} when id == alert.id
    assert_receive {:network_updated, "net-c0421"}
  end
end
