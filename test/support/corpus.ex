defmodule Dripstone.Test.Corpus do
  @moduledoc """
  Fixture-first corpus resolution for fetcher tests.

  Resolves checked-in corpora under `priv/datasets/<platform>/<date>.jsonl`
  (newest date wins) so the default test path performs zero HTTP. `:datasets_dir`
  overrides the root (tests use a tmp dir); each JSONL line decodes to one post map.
  """

  @doc "Latest corpus file for `platform`, or `{:error, reason}` when absent."
  @spec latest(String.t() | atom(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def latest(platform, opts \\ []) do
    dir = Path.join(root(opts), to_string(platform))

    case File.ls(dir) do
      {:ok, files} ->
        case files
             |> Enum.filter(&String.ends_with?(&1, ".jsonl"))
             |> Enum.sort()
             |> List.last() do
          nil -> {:error, {:no_corpus, dir}}
          name -> {:ok, Path.join(dir, name)}
        end

      {:error, reason} ->
        {:error, {:corpus_unreadable, reason}}
    end
  end

  @doc "Reads a JSONL corpus file into a list of maps. Raises on bad lines."
  @spec read!(String.t()) :: [map()]
  def read!(path) do
    path
    |> File.stream!()
    |> Enum.map(&Jason.decode!/1)
  end

  defp root(opts), do: Keyword.get(opts, :datasets_dir, Path.join(File.cwd!(), "priv/datasets"))
end
