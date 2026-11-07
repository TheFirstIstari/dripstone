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
    stub_reddit: Dripstone.Adapters.StubReddit
  }

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
