defmodule Dripstone.Tracker.SeedsTest do
  # Resets the app-wide rows, so it must not run alongside other tests.
  use Dripstone.DataCase, async: false

  alias Dripstone.Tracker
  alias Dripstone.Tracker.{SampleData, SampleLoader, State, Store}

  # From the SampleData timeline: 12 "new network" alerts, of which 6 are decided
  # (4 confirmed, 2 dismissed), leaves 6 open; plus Bluewave growth, Echo's re-alert,
  # Quiet Pine's reactivation and Sunrise's promotion shift = 10.
  @expected_open 10

  setup do
    {:ok, previous} = Store.load()
    on_exit(fn -> :ok = Store.save(previous) end)
    Tracker.reset_sample_data!()
    :ok
  end

  test "first boot seeds the sample rows" do
    Store.reset!()
    {:ok, seeded} = Store.load()
    assert Store.seeded?()
    assert map_size(seeded.accounts) == 1300
  end

  test "every alert traces back to a replayed finding" do
    {:ok, state} = Store.load()
    events = SampleData.generate(DateTime.utc_now()).events

    reported =
      for %{type: :finding, finding: f} <- events,
          into: MapSet.new(),
          do: {f[:network_id] || f.new_network.id, f.trigger}

    for {_id, alert} <- state.alerts do
      assert {alert.network_id, alert.trigger_id} in reported
      assert alert.evidence != []
    end
  end

  test "the open alert count matches the seed timeline" do
    {:ok, state} = Store.load()
    open = state.alerts |> Map.values() |> Enum.count(&(&1.status == :open))
    assert open == @expected_open
  end

  test "seed decisions and curation were applied at the right points" do
    {:ok, state} = Store.load()

    sunrise = state.networks["net-sunrise"]
    assert sunrise.name == "Discount Spam Ring"
    assert sunrise.detected_name == "Sunrise Cluster"
    assert sunrise.tags == ["discount-spam", "coordinated-promo"]
    assert [removed] = sunrise.removed_account_ids
    refute removed in sunrise.member_ids, "a later finding must not re-add the removed member"
    assert sunrise.main_domain == "deals-b.example"

    echo_alerts = state.alerts |> Map.values() |> Enum.filter(&(&1.network_id == "net-echo"))
    assert length(echo_alerts) == 2, "the stale finding must be ignored"

    assert %{previously_dismissed_alert_id: dismissed_id} =
             Enum.find(echo_alerts, &(&1.status == :open))

    assert state.alerts[dismissed_id].status == :dismissed
    assert state.networks["net-echo"].status == :suspected

    assert state.networks["net-bluewave"].status == :confirmed

    assert Enum.any?(
             Map.values(state.alerts),
             &(&1.network_id == "net-bluewave" and &1.trigger_id == "network_growth" and
                 &1.status == :open)
           )
  end

  test "reset_sample_data!/0 discards changes" do
    [%{alert: alert} | _] = Tracker.list_alerts()
    {:ok, _} = Tracker.confirm_alert(alert.id)
    Tracker.reset_sample_data!()
    assert Tracker.get_alert(alert.id).alert.status == :open
  end

  test "history is capped at the newest entries" do
    now = DateTime.utc_now()
    {:ok, state} = Store.load()
    max = State.max_history()

    state =
      Enum.reduce(1..(max + 10), state, fn i, acc ->
        State.add_history(acc, "net-echo", :system, "sys", "e#{i}", now)
      end)

    assert length(state.history) == max
    assert hd(state.history).summary == "e#{max + 10}"
  end

  test "loading is deterministic for a given time" do
    now = ~U[2026-11-07 17:00:00Z]
    assert SampleLoader.load(now) == SampleLoader.load(now)
  end
end
