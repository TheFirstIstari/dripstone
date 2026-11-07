defmodule Dripstone.Tracker.Link do
  @moduledoc """
  An undirected link between two accounts, e.g. both posting near-duplicate text.
  `account_ids` is a sorted pair so each link is stored once per kind.

  The first four kinds are the decision model's `relation` labels. `:near_duplicate`
  and `:created_together` only come from sample data for now. `provenance` lists the
  findings that produced or confirmed the link, newest first
  (`%{finding_id, question, model, at}`).
  """

  @kinds [
    :shared_link,
    :repost_ring,
    :timing_sync,
    :audience_overlap,
    :near_duplicate,
    :created_together
  ]
  @strengths [:weak, :moderate, :strong]

  @enforce_keys [:account_ids, :kind, :strength]
  defstruct [:account_ids, :kind, :strength, provenance: []]

  @type kind ::
          :shared_link
          | :repost_ring
          | :timing_sync
          | :audience_overlap
          | :near_duplicate
          | :created_together
  @type t :: %__MODULE__{
          account_ids: {String.t(), String.t()},
          kind: kind(),
          strength: :weak | :moderate | :strong,
          provenance: [map()]
        }

  @doc "All link kinds, in legend order."
  @spec kinds() :: [kind()]
  def kinds, do: @kinds

  @doc "All strengths, weakest first."
  @spec strengths() :: [atom()]
  def strengths, do: @strengths
end
