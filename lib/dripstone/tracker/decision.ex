defmodule Dripstone.Tracker.Decision do
  @moduledoc """
  An analyst's confirm or dismiss on an alert. Keeps the alert's and network's
  previous statuses so the decision can be undone.
  """

  @enforce_keys [:id, :alert_id, :network_id, :action, :by, :at]
  defstruct [
    :id,
    :alert_id,
    :network_id,
    :action,
    :by,
    :at,
    :note,
    :previous_alert_status,
    :previous_network_status,
    :resulting_network_status
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          alert_id: String.t(),
          network_id: String.t(),
          action: :confirm | :dismiss,
          by: String.t(),
          at: DateTime.t(),
          note: String.t() | nil,
          previous_alert_status: atom() | nil,
          previous_network_status: atom() | nil,
          resulting_network_status: atom() | nil
        }
end
