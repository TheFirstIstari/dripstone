defmodule Mix.Tasks.Dripstone.Datasets.Refresh do
  @shortdoc "Refresh versioned fetcher corpora under priv/datasets"

  @moduledoc """
  Records one real fetcher response per platform into a dated corpus:

      mix dripstone.datasets.refresh --platform x --handle "@someone"
      mix dripstone.datasets.refresh --platform reddit --handle "u/someone"
      mix dripstone.datasets.refresh --all --handle "@someone"

  Writes `priv/datasets/<platform>/<date>.jsonl`; each line is one post plus
  `fetched_at` and `source`. Respects rate limits: fetchers must honor
  robots.txt and stay within platform limits; 429 responses back off and
  retry instead of hammering.
  """

  use Mix.Task

  @platforms %{
    "x" => Dripstone.Adapters.StubX,
    "reddit" => Dripstone.Adapters.StubReddit,
    "bluesky" => Dripstone.Adapters.Bluesky,
    "mastodon" => Dripstone.Adapters.Mastodon
  }

  @impl Mix.Task
  def run(args) do
    # Real fetchers make HTTP requests, so the HTTP client must be running (the
    # stubs never needed it).
    {:ok, _} = Application.ensure_all_started(:req)

    {opts, _, _} =
      OptionParser.parse(args,
        strict: [platform: :string, handle: :string, all: :boolean, date: :string]
      )

    platforms =
      cond do
        opts[:all] -> Map.keys(@platforms)
        is_binary(opts[:platform]) -> [opts[:platform]]
        true -> []
      end

    handle = opts[:handle]

    cond do
      platforms == [] ->
        Mix.raise(
          "pass --platform <name> or --all (known: #{Enum.join(Map.keys(@platforms), ", ")})"
        )

      not is_binary(handle) ->
        Mix.raise("pass --handle <handle>")

      true ->
        Enum.each(platforms, fn platform ->
          case Map.fetch(@platforms, platform) do
            {:ok, adapter} ->
              task_opts = if opts[:date], do: [date: opts[:date]], else: []

              case Dripstone.Datasets.refresh(adapter, platform, handle, task_opts) do
                {:ok, path} -> Mix.shell().info("wrote #{path}")
                {:error, reason} -> Mix.raise("refresh #{platform} failed: #{inspect(reason)}")
              end

            :error ->
              Mix.raise("unknown platform #{inspect(platform)}")
          end
        end)
    end
  end
end
