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
  def perform(%Oban.Job{args: %{"adapter" => adapter, "handle" => handle} = args}) do
    with {:ok, module} <- adapter(adapter),
         {:ok, posts} <- module.fetch_posts(handle) do
      opts = scorer_opts(args)

      case Scorer.assess(posts, opts) do
        %{score: score, labels: labels, ai_answers: answers} ->
          finding = %{
            kind: "account",
            observed_at: DateTime.utc_now(),
            model: if(answers, do: model(opts)),
            account: %{feed_id: feed_id(module), handle: handle},
            posts: posts,
            heuristics: %{score: score, labels: labels},
            answers: answers
          }

          case Tracker.report_finding(finding) do
            {:ok, _result} -> :ok
            {:error, reason} -> {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}

        other ->
          {:error, {:invalid_assessment, other}}
      end
    end
  end

  # Test-only adapter override (`Application.put_env(:dripstone, AssessWorker,
  # adapters: %{"name" => Module})`): lets regression tests feed poison payloads
  # through the worker without changing the fixed adapter registry.
  defp adapter(name) do
    test_adapters = Application.get_env(:dripstone, __MODULE__, []) |> Keyword.get(:adapters, %{})

    case Map.fetch(test_adapters, name) do
      {:ok, module} ->
        {:ok, module}

      :error ->
        case Adapters.get(name) do
          module when is_map_key(@feeds, module) -> {:ok, module}
          _ -> {:cancel, "unknown adapter #{inspect(name)}"}
        end
    end
  end

  # Feed for an adapter (real or test-only override).
  defp feed_id(module) do
    overrides =
      Application.get_env(:dripstone, __MODULE__, []) |> Keyword.get(:feed_overrides, %{})

    Map.get_lazy(overrides, module, fn -> Map.fetch!(@feeds, module) end)
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
