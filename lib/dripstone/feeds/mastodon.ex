defmodule Dripstone.Feeds.Mastodon do
  @moduledoc """
  Mastodon (and compatible fediverse servers).

  The instance comes from an `:instance` key, or from a full `user@instance`
  handle. Links are only built when the instance is a valid host name.
  """
  @behaviour Dripstone.Feeds.Feed

  alias Dripstone.Feeds.URL

  @impl true
  def id, do: "mastodon"

  @impl true
  def name, do: "Mastodon"

  @impl true
  def format_handle(%{handle: _} = ref) do
    case split(ref) do
      {user, nil} -> "@" <> user
      {user, instance} -> "@#{user}@#{instance}"
    end
  end

  def format_handle(_), do: nil

  @impl true
  def profile_url(%{handle: _} = ref) do
    {user, instance} = split(ref)
    URL.build(base(instance), [{:prefixed, "@", user}])
  end

  def profile_url(_), do: nil

  @impl true
  def post_url(%{handle: _, post_id: post_id} = ref) do
    {user, instance} = split(ref)
    URL.build(base(instance), [{:prefixed, "@", user}, post_id])
  end

  def post_url(_), do: nil

  @impl true
  def expected_interval, do: 120

  defp base(nil), do: nil
  defp base(instance), do: "https://" <> instance

  # Returns {user, valid_instance_or_nil}.
  defp split(%{handle: handle} = ref) do
    case String.split(URL.bare(handle), "@", parts: 2) do
      [user, instance] -> {user, URL.host(instance)}
      [user] -> {user, URL.host(Map.get(ref, :instance))}
    end
  end
end
