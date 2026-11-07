defmodule Dripstone.Tracker.Evidence do
  @moduledoc """
  One piece of evidence behind an alert or a network: what was found, how strong it
  is, and which accounts it involves. `kind` matches `Dripstone.Tracker.Link` kinds
  where it applies (e.g. `:shared_link`), or `:other`.
  """

  @enforce_keys [:explanation, :strength]
  defstruct [:explanation, :strength, kind: :other, account_ids: []]

  @type t :: %__MODULE__{
          explanation: String.t(),
          strength: :weak | :moderate | :strong,
          kind: atom(),
          account_ids: [String.t()]
        }
end
