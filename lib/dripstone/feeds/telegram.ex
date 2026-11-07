defmodule Dripstone.Feeds.Telegram do
  @moduledoc "Telegram public channels and groups."
  @behaviour Dripstone.Feeds.Feed

  alias Dripstone.Feeds.URL

  @base "https://t.me"

  @impl true
  def id, do: "telegram"

  @impl true
  def name, do: "Telegram"

  @impl true
  def format_handle(%{handle: handle}), do: "@" <> URL.bare(handle)

  @impl true
  def profile_url(%{handle: handle}), do: URL.build(@base, [URL.bare(handle)])

  @impl true
  def post_url(%{handle: handle, post_id: post_id}),
    do: URL.build(@base, [URL.bare(handle), post_id])

  @impl true
  def expected_interval, do: 300
end
