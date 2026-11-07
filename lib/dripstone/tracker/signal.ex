defmodule Dripstone.Tracker.Signal do
  @moduledoc """
  One contribution to an account's risk score, with a plain-language explanation.
  Detection blends AI analysis and heuristics, so a signal has no "source" field.
  `contribution` is `nil` when detection gives no breakdown; `value` then carries a
  short display value such as `"81%"`, if there is one.
  """

  @enforce_keys [:name, :explanation]
  defstruct [:name, :explanation, :contribution, :value]

  @type t :: %__MODULE__{
          name: String.t(),
          explanation: String.t(),
          contribution: integer() | nil,
          value: String.t() | nil
        }
end
