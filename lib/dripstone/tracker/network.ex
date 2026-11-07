defmodule Dripstone.Tracker.Network do
  @moduledoc """
  A suspected bot farm: a group of linked accounts.

  `name` is what analysts see; `detected_name` keeps the name detection gave it and
  is non-nil only once an analyst has renamed it (which protects the name from
  detection updates). `removed_account_ids` lists members an analyst removed, which
  later findings must not re-add. A network merged into another has `retired_into`.
  `assessment` is the latest decision-model assessment from group and trend findings
  (coordination, relation, trajectory), or `nil` if never assessed.
  """

  alias Dripstone.Tracker.Evidence

  @enforce_keys [:id, :name]
  defstruct [
    :id,
    :name,
    :detected_name,
    :main_domain,
    :summary,
    :first_activity_at,
    :last_activity_at,
    :retired_into,
    :inserted_at,
    :assessment,
    status: :suspected,
    confidence: 0,
    member_ids: [],
    joined_at: %{},
    platforms: [],
    evidence: [],
    tags: [],
    removed_account_ids: [],
    related_ids: []
  ]

  @type status :: :suspected | :confirmed | :dismissed
  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          detected_name: String.t() | nil,
          status: status(),
          confidence: 0..100,
          member_ids: [String.t()],
          joined_at: %{String.t() => DateTime.t()},
          platforms: [String.t()],
          main_domain: String.t() | nil,
          summary: %{text: String.t(), generated_at: DateTime.t()} | nil,
          evidence: [Evidence.t()],
          first_activity_at: DateTime.t() | nil,
          last_activity_at: DateTime.t() | nil,
          tags: [String.t()],
          removed_account_ids: [String.t()],
          related_ids: [String.t()],
          retired_into: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          assessment: map() | nil
        }
end
