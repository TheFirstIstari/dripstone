defmodule Dripstone.Tracker.Account do
  @moduledoc """
  A tracked social account on one platform feed.

  `risk_score` is 0–100; `signals` are the contributions behind it, largest first.
  `assessment` holds the latest account finding's parsed answers, model and time
  (`nil` until one arrives); `topic` is its `topic` answer label, if any.
  `instance` is only used by federated platforms such as Mastodon. `external_id` is
  the platform's permanent account id where it has one (a Bluesky DID), since
  handles can change.
  """

  alias Dripstone.Tracker.Signal

  @enforce_keys [:id, :feed_id, :handle]
  defstruct [
    :id,
    :feed_id,
    :handle,
    :display_name,
    :instance,
    :external_id,
    :created_at,
    :first_seen_at,
    :last_seen_at,
    :assessment,
    :topic,
    risk_score: 0,
    signals: []
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          feed_id: String.t(),
          handle: String.t(),
          display_name: String.t() | nil,
          instance: String.t() | nil,
          external_id: String.t() | nil,
          created_at: DateTime.t() | nil,
          first_seen_at: DateTime.t() | nil,
          last_seen_at: DateTime.t() | nil,
          assessment:
            %{answers: map() | nil, model: String.t() | nil, observed_at: DateTime.t()} | nil,
          topic: String.t() | nil,
          risk_score: 0..100,
          signals: [Signal.t()]
        }
end
