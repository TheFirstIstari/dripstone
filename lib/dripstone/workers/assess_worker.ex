defmodule Dripstone.Workers.AssessWorker do
  @moduledoc """
  Runs detection for one handle and reports the result to the tracker as an
  **account finding** (see `openspec/docs/DETECTION_INTERFACE.md`).

  Takes `%{"adapter" => "stub_x", "handle" => "..."}` args: fetches the handle's
  posts with that adapter, scores them with `Dripstone.Scorer.assess/2` (heuristics
  plus Jev's answers, or heuristics only if the AI call fails), then calls
  `Dripstone.Tracker.report_finding/1`. Account findings update the account and
  raise no alert.

  `Scorer.assess/2` calls the AI client, which may only run in a job like this one,
  never in LiveView or request processes. One attempt only, so a failing job never
  repeats AI calls.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Dripstone.{Adapters, Scorer, Tracker}

  # Which tracker feed each fetch adapter's accounts belong to.
  @feeds %{
    Dripstone.Adapters.StubX => "x",
    Dripstone.Adapters.StubReddit => "reddit"
  }

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"adapter" => _, "handle" => _} = args}) do
    # Jobs queued by the Demo simulator report into Demo; everything else is Live.
    dataset = if args["dataset"] == "demo", do: :demo, else: :live
    Dripstone.Tracker.with_dataset(dataset, fn -> assess(args) end)
  end

  defp assess(%{"adapter" => adapter, "handle" => handle} = args) do
    opts = scorer_opts(args)

    with {:ok, module, feed} <- adapter(adapter),
         {:ok, posts} <- module.fetch_posts(handle),
         {:ok, assessment} <- assess(posts, opts) do
      finding = %{
        kind: "account",
        observed_at: DateTime.utc_now(),
        model: if(assessment.ai_answers, do: model(opts)),
        account: %{feed_id: feed, handle: handle},
        posts: posts,
        heuristics: %{score: assessment.score, labels: assessment.labels},
        answers: assessment.ai_answers
      }

      case Tracker.report_finding(finding) do
        {:ok, _result} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  # Scorer.assess/2 returns {:error, ...} for non-list posts. A poison adapter
  # payload must fail the job cleanly, not crash-loop on `.score` (#137).
  defp assess(posts, opts) do
    case Scorer.assess(posts, opts) do
      %{score: _, labels: _, ai_answers: _} = assessment -> {:ok, assessment}
      {:error, _} = error -> error
      other -> {:error, {:invalid_assessment, other}}
    end
  end

  defp adapter(name) do
    case Adapters.get(name) || extra_adapter(name) do
      module when is_map_key(@feeds, module) -> {:ok, module, Map.fetch!(@feeds, module)}
      {module, feed} when is_atom(module) and is_binary(feed) -> {:ok, module, feed}
      _ -> {:cancel, "unknown adapter #{inspect(name)}"}
    end
  end

  # Test seam: %{"name" => {module, feed}} doubles, e.g. poison payloads (#137).
  defp extra_adapter(name) do
    :dripstone
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:extra_adapters, %{})
    |> Map.get(name)
  end

  defp scorer_opts(%{"model" => model}) when is_binary(model), do: [model: model]
  defp scorer_opts(_args), do: []

  # The model the AI client was asked to use: the job's, else the configured one.
  defp model(opts) do
    Keyword.get_lazy(opts, :model, fn ->
      :dripstone |> Application.get_env(Dripstone.AIClient, []) |> Keyword.get(:model)
    end)
  end
end
