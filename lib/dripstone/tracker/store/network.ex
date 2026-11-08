defmodule Dripstone.Tracker.Store.Network do
  @moduledoc false
  # Persistence row for `Dripstone.Tracker.Network`. Membership lives in
  # `tracker_memberships` (ordered by `position`); the rest mirrors the struct.
  # `status` persists the Cleared state: a dismissed network is investigated and
  # false, distinct from suspected, and re-enters evaluation on fresh evidence.
  # `assessment` is the decision model's latest (coordination, relation,
  # trajectory) with observation times.
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  schema "tracker_networks" do
    field :name, :string
    field :detected_name, :string
    field :status, :string
    field :confidence, :integer, default: 0
    field :main_domain, :string
    field :summary_text, :string
    field :summary_generated_at, :utc_datetime
    field :platforms, {:array, :string}, default: []
    field :tags, {:array, :string}, default: []
    field :related_ids, {:array, :string}, default: []
    field :evidence, {:array, :map}, default: []
    field :removed_account_ids, {:array, :string}, default: []
    field :retired_into_id, :string
    # `first_seen_at`/`last_true_at`/`last_checked_at` are the spec's temporal
    # triple; `inserted_at` is when the row was first stored.
    field :first_seen_at, :utc_datetime
    field :last_true_at, :utc_datetime
    field :last_checked_at, :utc_datetime
    field :inserted_at, :utc_datetime
    field :assessment, :map
  end
end
