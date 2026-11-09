defmodule Dripstone.Workers.RefreshWorker do
  @moduledoc """
  Refreshes one handle: records a fresh fetcher corpus, then enqueues
  `AssessWorker` to score it. Enqueued per account by `RefreshScheduler`
  (hourly cron); also safe to enqueue manually for one-off captures.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Dripstone.{Adapters, Datasets}
  alias Dripstone.Workers.AssessWorker

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"adapter" => adapter, "feed" => feed, "handle" => handle}}) do
    with {:ok, module} <- adapter_module(adapter),
         {:ok, _path} <- Datasets.refresh(module, feed, handle, datasets_opts()),
         {:ok, _job} <-
           %{"adapter" => adapter, "handle" => handle} |> AssessWorker.new() |> Oban.insert() do
      :ok
    end
  end

  def perform(%Oban.Job{args: args}), do: {:cancel, "unknown refresh args #{inspect(args)}"}

  defp adapter_module(name) do
    case Adapters.get(name) do
      nil -> {:cancel, "unknown adapter #{inspect(name)}"}
      module -> {:ok, module}
    end
  end

  # Tests point corpora at a tmp dir via `config :dripstone, :datasets, opts`.
  defp datasets_opts, do: Application.get_env(:dripstone, :datasets, [])
end
