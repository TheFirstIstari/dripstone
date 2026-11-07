defmodule Dripstone.Tracker.HistoryEntry do
  @moduledoc """
  One recorded change to a network. `actor` is `:analyst` for manual changes and
  `:system` for changes made by detection.
  """

  @enforce_keys [:id, :network_id, :actor, :by, :at, :summary]
  defstruct [:id, :network_id, :actor, :by, :at, :summary]

  @type t :: %__MODULE__{
          id: String.t(),
          network_id: String.t(),
          actor: :analyst | :system,
          by: String.t(),
          at: DateTime.t(),
          summary: String.t()
        }
end
