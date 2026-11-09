defmodule Dripstone.Tracker.Link do
  @moduledoc """
  An undirected link between two accounts, e.g. both posting near-duplicate text.
<<<<<<< Updated upstream
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
=======
  `account_ids` is a sorted pair so each link is stored once.
  Kinds follow the scorer's `relation` answer set (issue #44): `repost_ring`,
  `shared_link` (`shared-link`), `timing_sync` (`timing-sync`),
  `audience_overlap` (`audience-overlap`) and `none` (stored as `:other`).
  Legacy kinds (`near_duplicate`, `synced_posting`, `created_together`) remain
  for older corpora.
  """

  @kinds [
    :repost_ring,
    :shared_link,
    :timing_sync,
    :audience_overlap,
    :near_duplicate,
    :synced_posting,
>>>>>>> Stashed changes
    :created_together
  ]
  @strengths [:weak, :moderate, :strong]

  @enforce_keys [:account_ids, :kind, :strength]
  defstruct [:account_ids, :kind, :strength, provenance: []]

  @type kind ::
<<<<<<< Updated upstream
          :shared_link
          | :repost_ring
          | :timing_sync
          | :audience_overlap
          | :near_duplicate
=======
          :repost_ring
          | :shared_link
          | :timing_sync
          | :audience_overlap
          | :near_duplicate
          | :synced_posting
>>>>>>> Stashed changes
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

  @doc "Scorer `relation` label (e.g. `shared-link`) for a link kind."
  @spec relation_label(kind() | atom()) :: String.t()
  def relation_label(:repost_ring), do: "repost-ring"
  def relation_label(:timing_sync), do: "timing-sync"
  def relation_label(:audience_overlap), do: "audience-overlap"
  def relation_label(:shared_link), do: "shared-link"
  def relation_label(kind) when is_atom(kind), do: kind |> Atom.to_string() |> String.replace("_", "-")

  @doc "Link kind for a scorer `relation` label (`none` and unknown become `:other`)."
  @spec relation_kind(String.t() | atom() | nil) :: kind() | :other
  def relation_kind("repost-ring"), do: :repost_ring
  def relation_kind("shared-link"), do: :shared_link
  def relation_kind("timing-sync"), do: :timing_sync
  def relation_kind("audience-overlap"), do: :audience_overlap
  def relation_kind(:repost_ring), do: :repost_ring
  def relation_kind(:shared_link), do: :shared_link
  def relation_kind(:timing_sync), do: :timing_sync
  def relation_kind(:audience_overlap), do: :audience_overlap
  def relation_kind(_label), do: :other
CUT 1*
