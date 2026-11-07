defmodule Dripstone.Tracker.FeedHealth do
  @moduledoc "Health of one platform feed, keyed by the feed's string id."

  @enforce_keys [:feed_id, :status]
  defstruct [
    :feed_id,
    :status,
    :last_item_at,
    :last_error,
    :last_error_at,
    :window_started_at,
    items_24h: 0
  ]

  @type t :: %__MODULE__{
          feed_id: String.t(),
          status: :healthy | :degraded | :down | :not_connected,
          last_item_at: DateTime.t() | nil,
          items_24h: non_neg_integer(),
          window_started_at: DateTime.t() | nil,
          last_error: String.t() | nil,
          last_error_at: DateTime.t() | nil
        }
end
