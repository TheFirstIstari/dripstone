defmodule Dripstone.Tracker.Store.Finding do
  @moduledoc false
  # Persistence row for the state's findings log: the latest reported findings
  # (newest first, capped by `Dripstone.Tracker.Rules` config), so link
  # provenance can be traced back to the finding that produced it. `accounts`
  # holds the finding's account refs; `answers` its raw answers map. `position`
  # is the index in the newest-first list, so the order round-trips exactly.
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  schema "tracker_findings" do
    field :kind, :string
    field :observed_at, :utc_datetime
    field :model, :string
    field :network_id, :string
    field :accounts, {:array, :map}, default: []
    field :answers, :map
    field :position, :integer, default: 0
  end
end
