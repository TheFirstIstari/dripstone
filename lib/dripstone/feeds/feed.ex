defmodule Dripstone.Feeds.Feed do
  @moduledoc """
  Behaviour for a social platform feed.

  A feed describes one platform: its stable id, display name, how account handles
  are shown, and how to link to an account's profile and to a post. Feeds are
  listed in the `Dripstone.Feeds` registry (see `openspec/docs/FEEDS.md`).

  Account and post references are plain maps (or structs) with at least a
  `:handle` key; posts also carry `:post_id`. Some feeds read extra keys, such as
  `:instance` for Mastodon. Link builders return `nil` when the reference cannot
  produce a safe link.
  """

  @typedoc "An account reference: `:handle`, plus any platform-specific keys."
  @type account_ref :: %{required(:handle) => String.t(), optional(atom()) => term()}

  @typedoc "A post reference: `:handle` and `:post_id`, plus any platform-specific keys."
  @type post_ref :: %{
          required(:handle) => String.t(),
          required(:post_id) => String.t(),
          optional(atom()) => term()
        }

  @doc "Stable string id, used in URLs, filters and stored data. Never change it."
  @callback id() :: String.t()

  @doc "Display name shown in the UI."
  @callback name() :: String.t()

  @doc "How an account handle is displayed on this platform."
  @callback format_handle(account_ref()) :: String.t()

  @doc "Link to the account's profile, or `nil` if one cannot be built safely."
  @callback profile_url(account_ref()) :: String.t() | nil

  @doc "Link to a post, or `nil` if one cannot be built safely."
  @callback post_url(post_ref()) :: String.t() | nil

  @doc "Expected seconds between items when the feed is healthy."
  @callback expected_interval() :: pos_integer()
end
