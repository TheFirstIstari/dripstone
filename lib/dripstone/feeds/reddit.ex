defmodule Dripstone.Feeds.Reddit do
  @moduledoc "Reddit."
  @behaviour Dripstone.Feeds.Feed

  alias Dripstone.Feeds.URL

  @base "https://www.reddit.com"
  @prefixes ["/u/", "u/", "@"]

  @impl true
  def id, do: "reddit"

  @impl true
  def name, do: "Reddit"

  @impl true
  def format_handle(%{handle: handle}), do: "u/" <> URL.bare(handle, @prefixes)
  def format_handle(_), do: nil

  @impl true
  def profile_url(%{handle: handle}), do: URL.build(@base, ["user", URL.bare(handle, @prefixes)])
  def profile_url(_), do: nil

  @impl true
  def post_url(%{post_id: post_id}), do: URL.build(@base, ["comments", post_id])
  def post_url(_), do: nil

  @impl true
  def expected_interval, do: 300
end
