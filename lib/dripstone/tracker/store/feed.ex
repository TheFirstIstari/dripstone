defmodule Dripstone.Tracker.Store.Feed do
  @moduledoc false
  # Persistence row for `Dripstone.Tracker.FeedHealth`.
  use Ecto.Schema

  @primary_key {:feed_id, :string, autogenerate: false}
  schema "tracker_feeds" do
    field :status, :string
    field :last_item_at, :utc_datetime
    field :items_24h, :integer, default: 0
    field :window_started_at, :utc_datetime
    field :last_error, :string
    field :last_error_at, :utc_datetime
  end
end
