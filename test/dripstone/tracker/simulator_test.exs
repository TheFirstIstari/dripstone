defmodule Dripstone.Tracker.SimulatorTest do
  # Reports findings into the app-wide store, so it must not run alongside other tests.
  use ExUnit.Case, async: false

  alias Dripstone.Tracker
  alias Dripstone.Tracker.{SampleStore, Simulator}

  setup do
    previous = SampleStore.get_state()
    on_exit(fn -> SampleStore.put_state(previous) end)
    Tracker.reset_sample_data!()
    :ok = Tracker.subscribe()
    :ok
  end

  test "is not started by default" do
    refute Application.get_env(:dripstone, :simulate_alerts)
    assert Process.whereis(Simulator) == nil
  end

  test "reports generated findings that raise new alerts" do
    before = length(Tracker.list_alerts())
    start_supervised!({Simulator, interval: 10, name: :test_simulator})

    assert_receive {:alert_raised, alert}, 2_000
    assert alert.trigger_id in ~w(network_growth network_reactivation promotion_shift)
    assert alert.status == :open

    _ = :sys.get_state(:test_simulator)
    assert length(Tracker.list_alerts()) > before
  end
end
