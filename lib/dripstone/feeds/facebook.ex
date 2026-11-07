defmodule Dripstone.Feeds.Facebook do
  @moduledoc "Facebook public pages and profiles."
  @behaviour Dripstone.Feeds.Feed

  alias Dripstone.Feeds.URL

  @base "https://www.facebook.com"

  @impl true
  def id, do: "facebook"

  @impl true
  def name, do: "Facebook"

  @impl true
  def format_handle(%{handle: handle}), do: URL.bare(handle)

  @impl true
  def profile_url(%{handle: handle}), do: URL.build(@base, [URL.bare(handle)])

  @impl true
  def post_url(%{handle: handle, post_id: post_id}),
    do: URL.build(@base, [URL.bare(handle), "posts", post_id])

  @impl true
  def expected_interval, do: 900
end
