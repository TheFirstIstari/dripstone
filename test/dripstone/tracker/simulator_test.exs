defmodule Dripstone.Tracker.SimulatorTest do
  # Changes the app-wide store, so it must not run alongside other tests.
  use ExUnit.Case, async: false

  alias Dripstone.Tracker
  alias Dripstone.Tracker.{SampleStore, Simulator}
  alias Dripstone.Workers.AssessWorker

  setup do
    previous = SampleStore.get_state()
    on_exit(fn -> SampleStore.put_state(previous) end)
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
    state = SampleStore.get_state()

    :ok =
      SampleStore.put_state(%{
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

    health = Map.new(SampleStore.get_state().feed_health, &{&1.feed_id, &1})
    assert DateTime.after?(health["x"].last_item_at, stale)
    assert health["telegram"].last_item_at == stale
    assert health["facebook"].last_item_at == stale
    assert Enum.find(Tracker.feed_health(), &(&1.feed.id() == "x")).health.status == :healthy
  end
end
