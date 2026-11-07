defmodule Dripstone.Tracker.Alert do
  @moduledoc """
  An alert raised from one or more findings for a network.

  `status` is `:open` until an analyst confirms or dismisses it. `comparison` holds
  before/after values for alerts that compare a network over time.
  `previously_dismissed_alert_id` is set when the alert re-raises a dismissed network.
  `answers` and `model` are the decision-model answers (parsed, keyed by question
  name) and model behind the latest finding that raised or updated the alert.
  """

  alias Dripstone.Tracker.Evidence

  @enforce_keys [:id, :trigger_id, :network_id, :severity, :title, :raised_at]
  defstruct [
    :id,
    :trigger_id,
    :network_id,
    :severity,
    :title,
    :raised_at,
    :observed_at,
    :updated_at,
    :ai_rationale,
    :comparison,
    :previously_dismissed_alert_id,
    :decision_id,
    :answers,
    :model,
    status: :open,
    evidence: []
  ]

  @type severity :: :low | :medium | :high
  @type status :: :open | :confirmed | :dismissed
  @type t :: %__MODULE__{
          id: String.t(),
          trigger_id: String.t(),
          network_id: String.t(),
          severity: severity(),
          status: status(),
          title: String.t(),
          raised_at: DateTime.t(),
          observed_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil,
          evidence: [Evidence.t()],
          ai_rationale: %{text: String.t(), generated_at: DateTime.t()} | nil,
          comparison: %{label: String.t(), before: String.t(), after: String.t()} | nil,
          previously_dismissed_alert_id: String.t() | nil,
          decision_id: String.t() | nil,
          answers: map() | nil,
          model: String.t() | nil
        }
end
