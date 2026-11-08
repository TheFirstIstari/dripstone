defmodule Dripstone.Tracker.Store.Account do
  @moduledoc false
  # Persistence row for `Dripstone.Tracker.Account`. Temporal columns follow the
  # spec names (`first_seen_at`, `last_true_at`, `last_checked_at`); the domain
  # struct keeps its `last_seen_at` name. `assessment` is the latest account
  # finding's answers, model and observation time; `topic` is its topic label.
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  schema "tracker_accounts" do
    field :feed_id, :string
    field :handle, :string
    field :display_name, :string
    field :instance, :string
    field :external_id, :string
    field :risk_score, :integer, default: 0
    field :signals, {:array, :map}, default: []
    field :first_seen_at, :utc_datetime
    field :last_seen_at, :utc_datetime
    field :last_checked_at, :utc_datetime
    field :assessment, :map
    field :topic, :string
  end
end
