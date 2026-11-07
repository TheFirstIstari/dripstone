defmodule Dripstone.Tracker.Store.Link do
  @moduledoc false
  # Persistence row for `Dripstone.Tracker.Link`. `provenance` is the spec's edge
  # provenance chain: which finding and question produced or confirmed the edge,
  # with which model, and when (`[%{finding_id, question, model, at}]`, newest
  # first, capped). Seed rows predate provenance tracking, so it is empty there.
  # The `{account_a, account_b, kind}` triple is the logical key (unique index);
  # the serial `id` is only so Ecto has a generated primary key to return.
  use Ecto.Schema

  schema "tracker_links" do
    field :account_a_id, :string
    field :account_b_id, :string
    field :kind, :string
    field :strength, :string
    field :provenance, {:array, :map}, default: []
  end
end
