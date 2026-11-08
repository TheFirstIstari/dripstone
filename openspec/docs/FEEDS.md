<!-- Contract doc for the feeds capability; the skeleton is followed by tests. -->
# Adding a platform feed

A **feed** tells Dripstone about one social platform: its id, its display name, how
handles look, and how to link to profiles and posts. Every place that shows or filters
by platform reads the feed registry, so adding a platform takes two steps.

Built in: X, Reddit, Bluesky, Mastodon, Telegram, Facebook (`lib/dripstone/feeds/`).

> Feeds describe platforms only. Fetching posts is a separate **adapter** behind
> `Dripstone.Adapters` (`fetch_posts(handle, opts) :: {:ok, posts} | {:error, reason}`),
> which must go through `Dripstone.Adapters.Polite` for rate limits, robots.txt and 429
> back-off. **Bluesky has a real fetcher** (`Dripstone.Adapters.Bluesky`, public AppView,
> no authentication); X and Reddit are still stubs. To give a platform a real fetcher:
> write the adapter, register it in `Dripstone.Adapters`, in `AssessWorker`'s feed map
> and in the refresh task's platforms, and record a seed corpus with
> `mix dripstone.refresh <platform> --handle <handle>` for fixture-first tests.

## 1. Write the module

Create `lib/dripstone/feeds/<platform>.ex`, one module per file:

```elixir
defmodule Dripstone.Feeds.Threads do
  @moduledoc "Threads."
  @behaviour Dripstone.Feeds.Feed

  alias Dripstone.Feeds.URL

  @base "https://www.threads.net"

  # Stable id used in URLs, filters and stored data. Never change it once used.
  @impl true
  def id, do: "threads"

  @impl true
  def name, do: "Threads"

  # How a handle is displayed. URL.bare/1 strips a leading "@".
  @impl true
  def format_handle(%{handle: handle}), do: "@" <> URL.bare(handle)

  # URL.build/2 percent-encodes each segment and returns nil if any is missing.
  # Use {:prefixed, "@", value} to keep a literal "@" in a path segment.
  @impl true
  def profile_url(%{handle: handle}), do: URL.build(@base, [{:prefixed, "@", URL.bare(handle)}])

  @impl true
  def post_url(%{handle: handle, post_id: post_id}),
    do: URL.build(@base, [{:prefixed, "@", URL.bare(handle)}, "post", post_id])

  # Expected seconds between items when the feed is healthy.
  @impl true
  def expected_interval, do: 120
end
```

Account and post references are maps (or structs) with `:handle`, plus `:post_id` for
posts. If the platform needs more, such as Mastodon's `:instance`, read it with
`Map.get/2`. Link builders must return `nil` instead of building a link from data
that doesn't validate. Handles, ids and hosts come from outside, so always go through
`URL.build/2` and `URL.host/1` rather than interpolating strings.

## 2. Register it

Add the module to the list in `config/config.exs`. The order here is the display order:

```elixir
config :dripstone, Dripstone.Feeds,
  feeds: [
    Dripstone.Feeds.X,
    # ...
    Dripstone.Feeds.Threads
  ]
```

## 3. Test it

Add cases to `test/dripstone/feeds_test.exs` for `format_handle/1`, `profile_url/1`
and `post_url/1`, including a reference that should produce no link. Then run:

```sh
mix test test/dripstone/feeds_test.exs
```

That's all. `Dripstone.Feeds.all/0` and `Dripstone.Feeds.get("threads")` now include
the new platform.
