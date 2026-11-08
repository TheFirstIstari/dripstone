defmodule Dripstone.Tracker.SimulatorTest do
  # Changes the app-wide store, so it must not run alongside other tests.
  use Dripstone.DataCase, async: false

  alias Dripstone.Tracker
  alias Dripstone.Tracker.{Simulator, Store}
  alias Dripstone.Workers.AssessWorker

  setup do
    {:ok, previous} = Store.load()
    on_exit(fn -> :ok = Store.save(previous) end)
    Tracker.reset_sample_data!()
    :ok
  end

  defp capture_jobs do
    test = self()

    fn changeset ->
      send(test, {:enqueued, changeset})
      {:ok, changeset}
    end
  end

  test "is not started by default" do
    refute Application.get_env(:dripstone, :simulate_alerts)
    assert Process.whereis(Simulator) == nil
  end

  test "queues assessment jobs for the stub handles" do
    start_supervised!(
      {Simulator,
       interval: 60_000,
       first_assess: 0,
       assess_interval: 10,
       enqueue: capture_jobs(),
       name: :test_simulator}
    )

    assert_receive {:enqueued, first}, 2_000
    assert_receive {:enqueued, _second}, 2_000

    assert first.changes.worker == inspect(AssessWorker)
    %{"adapter" => adapter, "handle" => handle} = first.changes.args
    assert {adapter, handle} in Simulator.handles()
  end

  test "keeps healthy sample feeds fresh, leaving down and degraded ones alone" do
    stale = DateTime.add(DateTime.utc_now(), -3_600) |> DateTime.truncate(:second)
    state = elem(Store.load(), 1)

    :ok =
      Store.save(%{
        state
        | feed_health: Enum.map(state.feed_health, &%{&1 | last_item_at: stale})
      })

    pid =
      start_supervised!(
        {Simulator,
         interval: 60_000, first_assess: 60_000, enqueue: capture_jobs(), name: :test_simulator}
      )

    send(pid, :tick)
    _ = :sys.get_state(pid)

    health = Map.new(elem(Store.load(), 1).feed_health, &{&1.feed_id, &1})
    assert DateTime.after?(health["x"].last_item_at, stale)
    assert health["telegram"].last_item_at == stale
    assert health["facebook"].last_item_at == stale
    assert Enum.find(Tracker.feed_health(), &(&1.feed.id() == "x")).health.status == :healthy
  end

  test "resets items_24h once the rolling window expires" do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    state = elem(Store.load(), 1)

    :ok =
      Store.save(%{
        state
        | feed_health:
            Enum.map(state.feed_health, fn
              %{status: :healthy} = health ->
                %{health | items_24h: 100, window_started_at: DateTime.add(now, -(25 * 3_600))}

              health ->
                health
            end)
      })

    pid =
      start_supervised!(
        {Simulator,
         interval: 60_000, first_assess: 60_000, enqueue: capture_jobs(), name: :test_simulator}
      )

    send(pid, :tick)
    _ = :sys.get_state(pid)

    health = Map.new(elem(Store.load(), 1).feed_health, &{&1.feed_id, &1})
    assert health["x"].items_24h == 1
    refute DateTime.diff(now, health["x"].window_started_at) >= 24 * 3_600
  end

  describe "canned findings each tick" do
    defp tick(kinds) do
      :ok = Tracker.subscribe()

      pid =
        start_supervised!(
          {Simulator,
           interval: 60_000,
           first_assess: 60_000,
           enqueue: capture_jobs(),
           kinds: kinds,
           name: :test_simulator}
        )

      send(pid, :tick)
      _ = :sys.get_state(pid)
    end

    test "a group of new accounts forms a network through the real rules" do
      before = map_size(elem(Store.load(), 1).networks)
      tick([:new])

      assert_receive {:alert_raised, %{trigger_id: "new_network", model: "simulator"} = alert}
      assert alert.finding_id
      assert map_size(elem(Store.load(), 1).networks) == before + 1
    end

    test "new accounts joining a live network raise network growth" do
      tick([:growth])

      # A network that already has an open growth alert merges into it instead.
      assert_receive {event, %{trigger_id: "network_growth", model: "simulator"}}
                     when event in [:alert_raised, :alert_updated]
    end

    test "a trend finding records the network's trajectory" do
      tick([:trend])

      [%{kind: :trend, network_id: id}] =
        Enum.take(elem(Store.load(), 1).findings, 1)

      assert elem(Store.load(), 1).networks[id].assessment.trajectory in ~w(forming stable fading)
    end

    test "with no live network, it forms one whatever kinds allow" do
      :ok = Store.save(%Dripstone.Tracker.State{})
      tick([:trend])
      assert_receive {:alert_raised, %{trigger_id: "new_network"}}
    end
  end
end
