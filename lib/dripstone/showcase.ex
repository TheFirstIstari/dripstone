defmodule Dripstone.Showcase do
  @moduledoc """
  Hand-built demo corpus under `priv/datasets/showcase/`.

  `v1.json` holds linked accounts, their posts, and the Jev-style group
  findings (`repost-ring`, `shared-link`, `timing-sync`, `none` relations)
  that justify the links. `load/1` replays the corpus through the real
  tracker path — `Report` cast + `Rules` run, exactly as detection reports —
  so the overview screen renders the resulting linked networks.

  Separate from the scraped corpora under `priv/datasets/<platform>/`: this
  one is versioned by hand and tells the data-in-relations-out story.
  """

  alias Dripstone.Tracker.{Report, Rules, State}

  @corpus "v1.json"

  @doc "Loads the named showcase corpus file into a tracker state."
  @spec load(String.t()) :: {:ok, State.t()} | {:error, term()}
  def load(name \\ @corpus) do
    with {:ok, raw} <- File.read(corpus_path(name)),
         {:ok, %{"findings" => findings}} when is_list(findings) <- Jason.decode(raw) do
      replay_findings(%State{}, findings)
    else
      {:ok, _} -> {:error, :invalid_corpus}
      {:error, _} = error -> error
    end
  end

  @doc "Corpus path for a showcase file (tests override the dir)."
  @spec corpus_path(String.t(), keyword()) :: Path.t()
  def corpus_path(name, opts \\ []) do
    dir =
      Keyword.get(opts, :showcase_dir, Path.join([File.cwd!(), "priv", "datasets", "showcase"]))

    Path.join(dir, name)
  end

  defp replay_findings(state, findings) do
    Enum.reduce_while(findings, {:ok, state}, fn raw, {:ok, state} ->
      with {:ok, report} <- Report.cast(raw, state),
           {:ok, _result, state} <- Rules.run(state, report, observed_at!(raw)) do
        {:cont, {:ok, state}}
      else
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp observed_at!(%{"observed_at" => iso}) do
    case DateTime.from_iso8601(iso) do
      {:ok, at, _offset} -> DateTime.truncate(at, :second)
      _ -> raise ArgumentError, "showcase corpus has invalid observed_at #{inspect(iso)}"
    end
  end
end
