defmodule Dripstone.Workers.AssessWorkerTest do
  # Uses the app-wide tracker store and changes the AI client config: not async.
  use Dripstone.DataCase, async: false
  use Oban.Testing, repo: Dripstone.Repo

  @moduletag :capture_log

  alias Dripstone.Tracker
  alias Dripstone.Tracker.{SampleStore, State}
  alias Dripstone.Workers.AssessWorker

  setup do
    previous = SampleStore.get_state()
    :ok = SampleStore.put_state(%State{})
    on_exit(fn -> SampleStore.put_state(previous) end)

    # No key, so the scorer never calls the real AI endpoint and falls back to
    # heuristics only.
    config = Application.get_env(:dripstone, Dripstone.AIClient, [])
    Application.put_env(:dripstone, Dripstone.AIClient, Keyword.put(config, :api_key, nil))
    on_exit(fn -> Application.put_env(:dripstone, Dripstone.AIClient, config) end)

    :ok = Tracker.subscribe()
    :ok
  end

  test "runs the stub adapter and scorer, then records the result" do
    assert :ok = perform_job(AssessWorker, %{"adapter" => "stub_x", "handle" => "alice"})

    assert_receive {:alert_raised, alert}
    assert alert.trigger_id == "scorer_assessment"
    assert "source: heuristics_only" in Enum.map(alert.evidence, & &1.explanation)

    assert [%{feed_id: "x", handle: "alice", assessment: %{source: :heuristics_only}}] =
             Map.values(SampleStore.get_state().accounts)
  end

  test "reddit handles land on the Reddit feed" do
    assert :ok = perform_job(AssessWorker, %{"adapter" => "stub_reddit", "handle" => "bob"})
    assert [%{feed_id: "reddit", handle: "bob"}] = Map.values(SampleStore.get_state().accounts)
  end

  test "an unknown adapter cancels the job" do
    assert {:cancel, _} =
             perform_job(AssessWorker, %{"adapter" => "stub_myspace", "handle" => "carol"})
  end
end
