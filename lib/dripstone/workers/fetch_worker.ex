defmodule Dripstone.Workers.FetchWorker do
  @moduledoc """
  Smoke worker proving Oban is wired end to end.

  Takes `%{"handle" => handle}` args; real fetching lands later.
  """

  use Oban.Worker, queue: "default"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"handle" => _handle}}) do
    :ok
  end
end
