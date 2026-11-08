defmodule Dripstone.Tracker.Store.Post do
  @moduledoc false
  # Persistence row for `Dripstone.Tracker.Post`.
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  schema "tracker_posts" do
    field :account_id, :string
    field :post_id, :string
    field :posted_at, :utc_datetime
    field :text, :string
    field :domain, :string
  end
end
