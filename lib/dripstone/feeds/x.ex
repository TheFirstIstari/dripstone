defmodule Dripstone.Feeds.X do
  @moduledoc "X (formerly Twitter)."
  @behaviour Dripstone.Feeds.Feed

  alias Dripstone.Feeds.URL

  @base "https://x.com"

  @impl true
  def id, do: "x"

  @impl true
  def name, do: "X"

  @impl true
  def format_handle(%{handle: handle}), do: "@" <> URL.bare(handle)

  @impl true
  def profile_url(%{handle: handle}), do: URL.build(@base, [URL.bare(handle)])

  @impl true
  def post_url(%{handle: handle, post_id: post_id}),
    do: URL.build(@base, [URL.bare(handle), "status", post_id])

  @impl true
  def expected_interval, do: 60
end
