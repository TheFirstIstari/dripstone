defmodule Dripstone.Tracker.Store.Meta do
  @moduledoc false
  # Single-row counters. `"seq"` feeds `State.next_id/2`; `"seeded"` marks the
  # sample seed rows as loaded so a restart never wipes analyst decisions.
  use Ecto.Schema

  @primary_key {:key, :string, autogenerate: false}
  schema "tracker_meta" do
    field :value, :integer
  end
end
