defmodule Dripstone.Feeds.Bluesky do
  @moduledoc "Bluesky. Handles are domain-style, e.g. `alice.bsky.social`."
  @behaviour Dripstone.Feeds.Feed

  alias Dripstone.Feeds.URL

  @base "https://bsky.app/profile"

  @impl true
  def id, do: "bluesky"

  @impl true
  def name, do: "Bluesky"

  @impl true
  def format_handle(%{handle: handle}), do: "@" <> URL.bare(handle)

  @impl true
  def profile_url(%{handle: handle}), do: URL.build(@base, [URL.bare(handle)])

  @impl true
  def post_url(%{handle: handle, post_id: post_id}),
    do: URL.build(@base, [URL.bare(handle), "post", post_id])

  @impl true
  def expected_interval, do: 60
end
