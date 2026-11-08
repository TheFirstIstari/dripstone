defmodule Dripstone.Tracker.Store.Alert do
  @moduledoc false
  # Persistence row for `Dripstone.Tracker.Alert`. `answers` is the parsed
  # decision-model answers behind the latest finding that raised or updated the
  # alert (nil when it had heuristics only); `finding_id` is that finding's id.
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  schema "tracker_alerts" do
    field :trigger_id, :string
    field :network_id, :string
    field :severity, :string
    field :status, :string
    field :title, :string
    field :raised_at, :utc_datetime
    field :observed_at, :utc_datetime
    field :updated_at, :utc_datetime
    field :evidence, {:array, :map}, default: []
    field :ai_rationale, :map
    field :comparison, :map
    field :previously_dismissed_id, :string
    field :decision_id, :string
    field :answers, :map
    field :model, :string
    field :finding_id, :string
  end
end
