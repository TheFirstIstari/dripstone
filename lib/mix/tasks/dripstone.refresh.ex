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
    Mix.Tasks.Dripstone.Datasets.Refresh.run(forward_args(args))
  end

  @doc false
  def forward_args(args) do
    {opts, rest, _} =
      OptionParser.parse(args,
        strict: [platform: :string, handle: :string, all: :boolean, date: :string]
      )

    case {opts[:platform], rest} do
      {nil, [platform | _]} ->
        ["--platform", platform] ++ OptionParser.to_argv(Keyword.delete(opts, :platform))

      _ ->
        args
    end
  end
end
