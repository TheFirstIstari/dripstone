defmodule Dripstone.Feeds do
  @moduledoc """
  Registry of platform feeds.

  Feeds are modules implementing `Dripstone.Feeds.Feed`, listed in order in config:

      config :dripstone, Dripstone.Feeds, feeds: [Dripstone.Feeds.X, ...]

  Everything that shows or filters by platform reads this registry, so adding a
  platform is one module plus one entry in that list. See `docs/FEEDS.md`.
  """

  @doc "All registered feed modules, in configured order."
  @spec all() :: [module()]
  def all do
    :dripstone
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:feeds, [])
  end

  @doc "The feed module with the given string id, or `nil`."
  @spec get(term()) :: module() | nil
  def get(id) when is_binary(id), do: Enum.find(all(), &(&1.id() == id))
  def get(_id), do: nil
end
