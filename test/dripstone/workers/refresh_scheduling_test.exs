defmodule Dripstone.Workers.RefreshSchedulingTest do
  # Uses the app-wide tracker store and changes the AI client config: not async.
  use Dripstone.DataCase, async: false
  use Oban.Testing, repo: Dripstone.Repo

  @moduletag :capture_log

  import Dripstone.TrackerFixtures

  alias Dripstone.Adapters
  alias Dripstone.Tracker.{State, Store}
  alias Dripstone.Workers.{RefreshScheduler, RefreshWorker}

  setup do
    {:ok, previous} = Store.load()
    :ok = Store.save(%State{})
    on_exit(fn -> :ok = Store.save(previous) end)

    dir = Path.join(System.tmp_dir!(), "refresh-#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    config = Application.get_env(:dripstone, :datasets, [])
    Application.put_env(:dripstone, :datasets, Keyword.put(config, :datasets_dir, dir))
    on_exit(fn -> Application.put_env(:dripstone, :datasets, config) end)
    on_exit(fn -> File.rm_rf!(dir) end)

    ai = Application.get_env(:dripstone, Dripstone.AIClient, [])
    Application.put_env(:dripstone, Dripstone.AIClient, Keyword.put(ai, :api_key, nil))
    on_exit(fn -> Application.put_env(:dripstone, Dripstone.AIClient, ai) end)

    {:ok, dir: dir}
  end

  test "scheduler enqueues one refresh per tracked account", %{dir: _dir} do
    :ok = Store.save(state_with_accounts(new_network_finding()))
    assert :ok = perform_job(RefreshScheduler, %{})
    assert_enqueued(worker: RefreshWorker, args: %{"adapter" => "stub_x", "handle" => "a1"})
    assert_enqueued(worker: RefreshWorker, args: %{"adapter" => "stub_x", "handle" => "a2"})
    assert_enqueued(worker: RefreshWorker, args: %{"adapter" => "stub_x", "handle" => "a3"})
  end

  test "scheduler skips accounts whose networks are all dismissed" do
    state =
      state_with_accounts(new_network_finding())
      |> dismiss("net-1", at(1))

    :ok = Store.save(state)
    assert :ok = perform_job(RefreshScheduler, %{})
    refute_enqueued(worker: RefreshWorker)
  end

  test "refresh worker writes a corpus then enqueues an assessment", %{dir: dir} do
    assert :ok =
             perform_job(RefreshWorker, %{
               "adapter" => "stub_x",
               "feed" => "x",
               "handle" => "alice"
             })

    assert {:ok, _} = Dripstone.Datasets.latest_corpus("x", datasets_dir: dir)

    assert_enqueued(
      worker: Dripstone.Workers.AssessWorker,
      args: %{"adapter" => "stub_x", "handle" => "alice"}
    )
  end

  test "refresh worker cancels on an unknown adapter" do
    assert {:cancel, _} =
             perform_job(RefreshWorker, %{
               "adapter" => "stub_myspace",
               "feed" => "myspace",
               "handle" => "carol"
             })
  end

  test "cron is configured hourly in config and runtime" do
    assert Dripstone.Adapters.get("stub_x") == Adapters.StubX

    for file <- ["config/config.exs", "config/runtime.exs"] do
      body = file |> Path.expand() |> File.read!()
      assert body =~ "RefreshScheduler", "#{file} must schedule RefreshScheduler"
      assert body =~ "0 * * * *", "#{file} must run the refresh hourly"
    end
  end
end
