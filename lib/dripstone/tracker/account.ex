defmodule Dripstone.Tracker.Account do
  @moduledoc """
  A tracked social account on one platform feed.

  `risk_score` is 0–100; `signals` are the contributions behind it, largest first.
  `assessment` holds the scorer's raw `ai_answers` and `source` for accounts
  recorded through `Dripstone.Tracker.Assessments` (interim), otherwise `nil`.
  `instance` is only used by federated platforms such as Mastodon.
  """

  alias Dripstone.Tracker.Signal

  @enforce_keys [:id, :feed_id, :handle]
  defstruct [
    :id,
    :feed_id,
    :handle,
    :display_name,
    :instance,
    :created_at,
    :first_seen_at,
    :last_seen_at,
    :assessment,
    risk_score: 0,
    signals: []
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          feed_id: String.t(),
          handle: String.t(),
          display_name: String.t() | nil,
          instance: String.t() | nil,
          created_at: DateTime.t() | nil,
          first_seen_at: DateTime.t() | nil,
          last_seen_at: DateTime.t() | nil,
          assessment: %{ai_answers: map() | nil, source: atom()} | nil,
          risk_score: 0..100,
          signals: [Signal.t()]
        }
end
