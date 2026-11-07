defmodule Dripstone.Tracker.Note do
  @moduledoc "An analyst note on a network."

  @enforce_keys [:id, :network_id, :body, :by, :at]
  defstruct [:id, :network_id, :body, :by, :at]

  @type t :: %__MODULE__{
          id: String.t(),
          network_id: String.t(),
          body: String.t(),
          by: String.t(),
          at: DateTime.t()
        }
end
