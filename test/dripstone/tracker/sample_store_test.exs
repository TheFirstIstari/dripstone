defmodule Dripstone.Tracker.SampleStoreTest do
  # Resets the app-wide store, so it must not run alongside other tests.
  use ExUnit.Case, async: false

  alias Dripstone.Tracker
  alias Dripstone.Tracker.{SampleData, SampleLoader, SampleStore}

  # From the SampleData timeline: 12 "new network" alerts, of which 6 are decided
  # (4 confirmed, 2 dismissed), leaves 6 open; plus Bluewave growth, Echo's re-alert,
  # Quiet Pine's reactivation and Sunrise's promotion shift = 10.
  @expected_open 10

  setup do
    previous = SampleStore.get_state()
    on_exit(fn -> SampleStore.put_state(previous) end)
    Tracker.reset_sample_data!()
    :ok
  end

  test "the app starts the store with the sample data loaded" do
    assert Process.whereis(SampleStore)
    assert map_size(SampleStore.get_state().accounts) == 1300
  end

  test "every alert traces back to a replayed finding" do
    state = SampleStore.get_state()
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
    open = SampleStore.get_state().alerts |> Map.values() |> Enum.count(&(&1.status == :open))
    assert open == @expected_open
  end

  test "seed decisions and curation were applied at the right points" do
    state = SampleStore.get_state()

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

  test "network graphs are cached per membership and cleared on change" do
    graph = Tracker.network_graph("net-c0422")
    assert map_size(SampleStore.get_state().cache) == 1
    assert Tracker.network_graph("net-c0422") == graph

    [member | _] = Tracker.get_network("net-c0422").network.member_ids
    {:ok, _} = Tracker.remove_members("net-c0422", [member])

    assert SampleStore.get_state().cache == %{}
    refute Enum.any?(Tracker.network_graph("net-c0422").nodes, &(&1.id == member))
    assert map_size(SampleStore.get_state().cache) == 1
    assert Tracker.network_graph("net-nope") == nil
  end

  test "history is capped at the newest entries" do
    now = DateTime.utc_now()
    state = SampleStore.get_state()
    max = Dripstone.Tracker.State.max_history()

    state =
      Enum.reduce(1..(max + 10), state, fn i, acc ->
        Dripstone.Tracker.State.add_history(acc, "net-echo", :system, "sys", "e#{i}", now)
      end)

    assert length(state.history) == max
    assert hd(state.history).summary == "e#{max + 10}"
  end

  test "loading is deterministic for a given time" do
    now = ~U[2026-11-07 17:00:00Z]
    assert SampleLoader.load(now) == SampleLoader.load(now)
  end

  test "load: false boots empty (prod gate, #50)" do
    {:ok, pid} = SampleStore.start_link(load: false, name: :sample_store_empty_check)
    assert SampleStore.get_state(:sample_store_empty_check).alerts == %{}
    GenServer.stop(pid)
  end

  test "load: :showcase starts on the showcase corpus" do
    {:ok, pid} = SampleStore.start_link(load: :showcase, name: :sample_store_showcase_check)
    state = SampleStore.get_state(:sample_store_showcase_check)
    GenServer.stop(pid)

    {:ok, expected} = Dripstone.Showcase.load()

    assert Map.keys(state.networks) |> Enum.sort() == Map.keys(expected.networks) |> Enum.sort()
    assert map_size(state.accounts) == 6
  end
end
