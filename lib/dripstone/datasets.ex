defmodule Dripstone.Datasets do
  @moduledoc """
  Versioned fetcher corpora under `priv/datasets/<platform>/<date>.jsonl`.

  Each JSONL line is one post object: post fields plus `fetched_at` (UTC
  ISO-8601 capture timestamp) and `source` (`"<platform>:<handle>"`).

  Flow: `mix dripstone.datasets.refresh` calls a fetcher's
  `fetch_posts/2` once and records the response here; tests read the
  checked-in corpora back via `read_corpus/2` with zero network.

  Rate-limit policy: live fetchers MUST stay within platform limits and
  honor robots.txt before fetching; `refresh/4` additionally backs off
  exponentially on 429/`rate_limited` errors instead of hammering.
  """

  @type platform :: String.t()

  @doc """
  Base corpora dir. Defaults to `priv/datasets` under the cwd;
  `:datasets_dir` overrides (tests point it at a tmp dir).
  """
  @spec base_dir(keyword()) :: Path.t()
  def base_dir(opts) do
    Keyword.get(opts, :datasets_dir, Path.join(File.cwd!(), "priv/datasets"))
  end

  @doc "Dated corpus path for a platform, e.g. `priv/datasets/x/2026-11-07.jsonl`."
  @spec corpus_path(platform(), String.t(), keyword()) :: Path.t()
  def corpus_path(platform, date, opts \\ []) do
    Path.join([base_dir(opts), platform, date <> ".jsonl"])
  end

  @doc """
  Fetches via `adapter` (with 429 backoff) and records the response as a new
  dated corpus. Returns `{:ok, path}`.
  """
  @spec refresh(module(), platform(), String.t(), keyword()) ::
          {:ok, Path.t()} | {:error, term()}
  def refresh(adapter, platform, handle, opts \\ []) do
    with {:ok, posts} <- fetch_with_backoff(adapter, handle, opts) do
      write_corpus(platform, handle, posts, opts)
    end
  end

  @doc """
  Writes posts as JSONL (post fields + `fetched_at` + `source`).
  Returns `{:ok, path}`.
  """
  @spec write_corpus(platform(), String.t(), list(map()), keyword()) ::
          {:ok, Path.t()} | {:error, term()}
  def write_corpus(platform, handle, posts, opts \\ []) do
    date = Keyword.get(opts, :date, Date.utc_today() |> Date.to_iso8601())
    fetched_at = DateTime.utc_now() |> DateTime.to_iso8601()
    source = platform <> ":" <> handle
    path = corpus_path(platform, date, opts)

    lines =
      Enum.map(posts, fn post ->
        Jason.encode!(%{
          "id" => field(post, :id),
          "handle" => field(post, :handle),
          "text" => field(post, :text),
          "urls" => field(post, :urls) || [],
          "published_at" => iso8601(field(post, :published_at)),
          "fetched_at" => fetched_at,
          "source" => source
        })
      end)

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, Enum.map_join(lines, "\n", & &1) <> "\n") do
      {:ok, path}
    end
  end

  @doc "Latest dated corpus file for a platform, or `{:error, :no_corpus}`."
  @spec latest_corpus(platform(), keyword()) :: {:ok, Path.t()} | {:error, :no_corpus}
  def latest_corpus(platform, opts \\ []) do
    pattern = Path.join([base_dir(opts), platform, "*.jsonl"])

    case pattern |> Path.wildcard() |> Enum.sort(:desc) do
      [latest | _] -> {:ok, latest}
      [] -> {:error, :no_corpus}
    end
  end

  @doc "Reads the latest corpus for a platform (file I/O only, zero network)."
  @spec read_corpus(platform(), keyword()) :: {:ok, list(map())} | {:error, term()}
  def read_corpus(platform, opts \\ []) do
    with {:ok, path} <- latest_corpus(platform, opts),
         {:ok, raw} <- File.read(path) do
      lines =
        raw
        |> String.split("\n", trim: true)
        |> Enum.map(&Jason.decode!/1)

      {:ok, lines}
    end
  end

  defp fetch_with_backoff(adapter, handle, opts, attempt \\ 0) do
    max = Keyword.get(opts, :max_retries, 3)

    case adapter.fetch_posts(handle, opts) do
      {:error, reason} = err ->
        if rate_limited?(reason) and attempt < max do
          sleep(backoff_ms(attempt, opts))
          fetch_with_backoff(adapter, handle, opts, attempt + 1)
        else
          err
        end

      ok ->
        ok
    end
  end

  defp rate_limited?({:http_status, 429}), do: true
  defp rate_limited?(:rate_limited), do: true
  defp rate_limited?({:rate_limited, _}), do: true
  defp rate_limited?(_), do: false

  # Exponential backoff: base, 2x base, 4x base, ... (default 1s, 2s, 4s).
  defp backoff_ms(attempt, opts) do
    Keyword.get(opts, :retry_sleep_ms, 1_000) * Integer.pow(2, attempt)
  end

  defp sleep(0), do: :ok
  defp sleep(ms), do: Process.sleep(ms)

  defp field(post, key) do
    Map.get(post, key, Map.get(post, Atom.to_string(key)))
  end

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp iso8601(other), do: other
end
