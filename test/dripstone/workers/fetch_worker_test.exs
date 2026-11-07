defmodule Dripstone.Workers.FetchWorkerTest do
  use Dripstone.DataCase
  use Oban.Testing, repo: Dripstone.Repo

  alias Dripstone.Workers.FetchWorker

  test "enqueues a fetch job for a handle" do
    assert {:ok, _job} = FetchWorker.new(%{"handle" => "alice"}) |> Oban.insert()

    assert_enqueued(worker: FetchWorker, args: %{"handle" => "alice"})
  end

  test "performs successfully" do
    assert :ok = perform_job(FetchWorker, %{"handle" => "alice"})
  end
end
