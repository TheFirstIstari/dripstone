defmodule Dripstone.Tracker.Store.Decision do
  @moduledoc false
  # Persistence row for `Dripstone.Tracker.Decision`.
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  schema "tracker_decisions" do
    field :alert_id, :string
    field :network_id, :string
    field :action, :string
    field :by, :string
    field :at, :utc_datetime
    field :note, :string
    field :previous_alert_status, :string
    field :previous_network_status, :string
    field :resulting_network_status, :string
  end
end
