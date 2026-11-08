defmodule Dripstone.Adapters do
  @moduledoc """
  Fetch-adapter boundary for source feeds.

  Handles stay opaque strings here; URL/handle building reuses the future
  feed registry.
  """

  @callback fetch_posts(handle :: String.t(), opts :: keyword()) ::
              {:ok, list(map())} | {:error, term()}

  @registry %{
    stub_x: Dripstone.Adapters.StubX,
    stub_reddit: Dripstone.Adapters.StubReddit,
    bluesky: Dripstone.Adapters.Bluesky,
    mastodon: Dripstone.Adapters.Mastodon
  }

  @doc """
  Reads a stub fixture file. Defaults under the project cwd; `:fixture_path`
  overrides for tests.
  """
  @spec read_fixture([String.t()], keyword()) ::
          {:ok, binary()} | {:error, {:fixture_unreadable, term()}}
  def read_fixture(segments, opts) when is_list(segments) and is_list(opts) do
    path = Keyword.get(opts, :fixture_path, Path.join([File.cwd!() | segments]))

    case File.read(path) do
      {:ok, _} = ok -> ok
      {:error, reason} -> {:error, {:fixture_unreadable, reason}}
    end
  end

  def all, do: @registry

  def get(name) when is_atom(name), do: Map.get(@registry, name)

  def get(name) when is_binary(name) do
    try do
      get(String.to_existing_atom(name))
    rescue
      ArgumentError -> nil
    end
  end

  def get(_), do: nil
end
