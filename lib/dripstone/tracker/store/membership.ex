defmodule Dripstone.Tracker.Store.Membership do
  @moduledoc false
  # One network member. `position` preserves the domain `member_ids` order.
  use Ecto.Schema

  @primary_key false
  schema "tracker_memberships" do
    field :network_id, :string, primary_key: true
    field :account_id, :string, primary_key: true
    field :joined_at, :utc_datetime
    field :position, :integer
  end
end
