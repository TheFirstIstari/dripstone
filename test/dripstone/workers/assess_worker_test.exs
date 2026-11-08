defmodule Dripstone.Workers.AssessWorkerTest do
  # Uses the app-wide tracker store and changes the AI client config: not async.
  use Dripstone.DataCase, async: false
  use Oban.Testing, repo: Dripstone.Repo

  @moduletag :capture_log

  alias Dripstone.Tracker
  alias Dripstone.Tracker.{State, Store}
  alias Dripstone.Workers.AssessWorker

  setup do
    {:ok, previous} = Store.load()
    :ok = Store.save(%State{})
    on_exit(fn -> :ok = Store.save(previous) end)

    # No key, so the scorer never calls the real AI endpoint and falls back to
    # heuristics only.
    config = Application.get_env(:dripstone, Dripstone.AIClient, [])
    Application.put_env(:dripstone, Dripstone.AIClient, Keyword.put(config, :api_key, nil))
    on_exit(fn -> Application.put_env(:dripstone, Dripstone.AIClient, config) end)

    :ok = Tracker.subscribe()
    :ok
  end

  test "runs the stub adapter and scorer, then reports an account finding" do
    assert :ok = perform_job(AssessWorker, %{"adapter" => "stub_x", "handle" => "alice"})

    [account] = Map.values(elem(Store.load(), 1).accounts)
    assert %{feed_id: "x", handle: "alice"} = account
    assert_receive {:account_updated, id}
    assert id == account.id

    # Heuristics only (no key): no answers, no model, and account findings raise no alert.
    assert account.assessment.answers == nil
    assert account.assessment.model == nil
    assert elem(Store.load(), 1).posts[account.id] != []
    refute_received {:alert_raised, _}
  end

  test "reddit handles land on the Reddit feed" do
    assert :ok = perform_job(AssessWorker, %{"adapter" => "stub_reddit", "handle" => "bob"})
    assert [%{feed_id: "reddit", handle: "bob"}] = Map.values(elem(Store.load(), 1).accounts)
  end

  test "an unknown adapter cancels the job" do
    assert {:cancel, _} =
             perform_job(AssessWorker, %{"adapter" => "stub_myspace", "handle" => "carol"})
  end
end
