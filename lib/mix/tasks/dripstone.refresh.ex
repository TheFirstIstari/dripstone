defmodule Mix.Tasks.Dripstone.Refresh do
  @shortdoc "Refresh versioned fetcher corpora under priv/datasets"

  @moduledoc """
  Shorthand for `mix dripstone.datasets.refresh`. Accepts the platform
  positionally or via `--platform`:

      mix dripstone.refresh x --handle "@someone"
      mix dripstone.refresh reddit --handle "u/someone"
      mix dripstone.refresh --platform x --handle "@someone"
      mix dripstone.refresh --all --handle "@someone"
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, rest, _} =
      OptionParser.parse(args,
        strict: [platform: :string, handle: :string, all: :boolean, date: :string]
      )

    forwarded =
      case {opts[:platform], rest} do
        {nil, [platform | extra]} -> ["--platform", platform] ++ extra ++ opts_to_args(opts)
        _ -> args
      end

    Mix.Tasks.Dripstone.Datasets.Refresh.run(forwarded)
  end

  defp opts_to_args(opts) do
    Enum.flat_map(opts, fn
      {:platform, _} -> []
      {:all, true} -> ["--all"]
      {:all, _} -> []
      {k, v} -> ["--#{k}", to_string(v)]
    end)
  end
end
