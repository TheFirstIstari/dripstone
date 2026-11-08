defmodule Dripstone.Discovery.Health do
  @moduledoc """
  Feed health for live discovery sources (Bluesky Jetstream, Mastodon timelines):
  in-memory counters that `write/1` turns into one `FeedHealth` row in Live,
  replacing that feed's previous entry. Sources call it once a minute, never per
  post, since every Live write rewrites the whole database.
  """

  alias Dripstone.Tracker.{FeedHealth, Store}

  @day_s 24 * 60 * 60

  @doc "Fresh counters."
  @spec new() :: map()
  def new,
    do: %{
      connected: false,
      last_item_at: nil,
      window_started_at: nil,
      items_24h: 0,
      last_error: nil,
      last_error_at: nil
    }

  @doc "Counts one received item at `now` (24-hour window, reset when it expires)."
  @spec count_item(map(), DateTime.t()) :: map()
  def count_item(c, now) do
    expired = c.window_started_at && DateTime.diff(now, c.window_started_at) >= @day_s

    if is_nil(c.window_started_at) or expired,
      do: %{c | last_item_at: now, window_started_at: now, items_24h: 1},
      else: %{c | last_item_at: now, items_24h: c.items_24h + 1}
  end

  @doc "The `FeedHealth` for `feed_id`: Down while disconnected, otherwise healthy."
  @spec to_feed_health(map(), String.t()) :: FeedHealth.t()
  def to_feed_health(c, feed_id) do
    %FeedHealth{
      feed_id: feed_id,
      status: if(c.connected, do: :healthy, else: :down),
      last_item_at: trunc_dt(c.last_item_at),
      items_24h: c.items_24h,
      window_started_at: trunc_dt(c.window_started_at),
      last_error: c.last_error,
      last_error_at: trunc_dt(c.last_error_at)
    }
  end

  @doc "Writes one feed's health into Live, in one write."
  @spec write(FeedHealth.t()) :: :ok
  def write(%FeedHealth{feed_id: feed_id} = health) do
    {:ok, :ok} =
      Store.write(fn ->
        {:ok, tracker} = Store.load()
        others = Enum.reject(tracker.feed_health, &(&1.feed_id == feed_id))
        :ok = Store.save(%{tracker | feed_health: [health | others]})
        {:ok, :ok}
      end)

    :ok
  end

  defp trunc_dt(nil), do: nil
  defp trunc_dt(at), do: DateTime.truncate(at, :second)
end
