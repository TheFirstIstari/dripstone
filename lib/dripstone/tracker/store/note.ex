defmodule Dripstone.Tracker.Store.Note do
  @moduledoc false
  # Persistence row for `Dripstone.Tracker.Note`.
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  schema "tracker_notes" do
    field :network_id, :string
    field :body, :string
    field :by, :string
    field :at, :utc_datetime
  end
end
