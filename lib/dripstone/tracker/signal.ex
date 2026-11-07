defmodule Dripstone.Tracker.Signal do
  @moduledoc """
  One contribution to an account's risk score, with a plain-language explanation.
  Detection blends AI analysis and heuristics, so a signal has no "source" field.
  `contribution` is `nil` when detection gives no breakdown (the interim scorer
  hookup only gives labels).
  """

  @enforce_keys [:name, :explanation, :contribution]
  defstruct [:name, :explanation, :contribution]

  @type t :: %__MODULE__{name: String.t(), explanation: String.t(), contribution: integer() | nil}
end
