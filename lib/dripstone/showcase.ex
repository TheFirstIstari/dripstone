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
  @spec load(String.t(), keyword()) :: {:ok, State.t()} | {:error, term()}
  def load(name \\ @corpus, opts \\ []) do
    with {:ok, raw} <- File.read(corpus_path(name, opts)),
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
      Keyword.get_lazy(opts, :showcase_dir, fn ->
        # Releases run eval from any cwd; prefer the OTP priv dir.
        case :code.priv_dir(:dripstone) do
          {:error, _} -> Path.join([File.cwd!(), "priv", "datasets", "showcase"])
          priv -> Path.join(to_string(priv), Path.join(["datasets", "showcase"]))
        end
      end)

    Path.join(dir, name)
  end

  defp replay_findings(state, findings) do
    Enum.reduce_while(findings, {:ok, state}, fn raw, {:ok, state} ->
      with {:ok, report} <- Report.cast(raw, state),
           {:ok, at} <- observed_at(raw),
           {:ok, _result, state} <- Rules.run(state, report, at) do
        {:cont, {:ok, state}}
      else
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp observed_at(%{"observed_at" => iso}) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, at, _offset} -> {:ok, DateTime.truncate(at, :second)}
      _ -> {:error, :invalid_observed_at}
    end
  end

  defp observed_at(_), do: {:error, :invalid_observed_at}
end
