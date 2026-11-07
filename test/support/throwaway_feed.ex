defmodule Dripstone.Test.ThrowawayFeed do
  @moduledoc false
  # A feed written from the skeleton in openspec/docs/FEEDS.md, used to prove that
  # registering a new feed is enough for it to appear in the registry.
  @behaviour Dripstone.Feeds.Feed

  alias Dripstone.Feeds.URL

  @base "https://www.threads.net"

  @impl true
  def id, do: "threads"

  @impl true
  def name, do: "Threads"

  @impl true
  def format_handle(%{handle: handle}), do: "@" <> URL.bare(handle)

  @impl true
  def profile_url(%{handle: handle}), do: URL.build(@base, [{:prefixed, "@", URL.bare(handle)}])

  @impl true
  def post_url(%{handle: handle, post_id: post_id}),
    do: URL.build(@base, [{:prefixed, "@", URL.bare(handle)}, "post", post_id])

  @impl true
  def expected_interval, do: 120
end
