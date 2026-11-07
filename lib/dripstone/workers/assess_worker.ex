defmodule Dripstone.Workers.AssessWorker do
  @moduledoc """
  Runs detection for one handle and records the result in the tracker (interim
  hookup, see `Dripstone.Tracker.Assessments`).

  Takes `%{"adapter" => "stub_x", "handle" => "..."}` args: fetches the handle's
  posts with that adapter, scores them with `Dripstone.Scorer.assess/2` (heuristics
  plus AI, or heuristics only if the AI call fails), then calls
  `Dripstone.Tracker.record_assessment/1`.

  `Scorer.assess/2` calls the AI client, which may only run in a job like this one,
  never in LiveView or request processes. One attempt only, so a failing job never
  repeats AI calls.

  Being changed: openspec change `add-jev-intake` makes this worker send an account
  finding through `Tracker.report_finding/1` instead (it supersedes issue #49).
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Dripstone.{Adapters, Scorer, Tracker}

  # Which tracker feed each fetch adapter's accounts belong to.
  @feeds %{
    Dripstone.Adapters.StubX => "x",
    Dripstone.Adapters.StubReddit => "reddit"
  }

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"adapter" => adapter, "handle" => handle} = args}) do
    with {:ok, module} <- adapter(adapter),
         {:ok, posts} <- module.fetch_posts(handle) do
      assessment = Scorer.assess(posts, scorer_opts(args))

      case Tracker.record_assessment(%{
             feed_id: Map.fetch!(@feeds, module),
             handle: handle,
             posts: posts,
             assessment: assessment
           }) do
        {:ok, _result} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp adapter(name) do
    case Adapters.get(name) do
      module when is_map_key(@feeds, module) -> {:ok, module}
      _ -> {:cancel, "unknown adapter #{inspect(name)}"}
    end
  end

  defp scorer_opts(%{"model" => model}) when is_binary(model), do: [model: model]
  defp scorer_opts(_args), do: []
end
