defmodule Dripstone.Tracker.Store.History do
  @moduledoc false
  # Persistence row for `Dripstone.Tracker.HistoryEntry`, newest first on load.
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  schema "tracker_history" do
    field :network_id, :string
    field :actor, :string
    field :by, :string
    field :at, :utc_datetime
    field :summary, :string
  end
end
