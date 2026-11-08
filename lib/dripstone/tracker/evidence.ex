defmodule Dripstone.Tracker.Evidence do
  @moduledoc """
  One piece of evidence behind an alert or a network: what was found, how strong it
  is, and which accounts it involves. `kind` matches `Dripstone.Tracker.Link` kinds
  where it applies (e.g. `:shared_link`), or `:other`. `source` is `:answers` for
  evidence the app wrote from decision-model answers, which a newer finding replaces
  rather than adds to; it is internal and never shown.
  """

  @enforce_keys [:explanation, :strength]
  defstruct [:explanation, :strength, :source, kind: :other, account_ids: []]
  @strength_rank %{weak: 1, moderate: 2, strong: 3}

  @doc "Strongest first. Stable, so ties keep their written order."
  def sort(evidence), do: Enum.sort_by(evidence, &@strength_rank[&1.strength], :desc)

  @type t :: %__MODULE__{
          explanation: String.t(),
          strength: :weak | :moderate | :strong,
          kind: atom(),
          account_ids: [String.t()],
          source: :answers | nil
        }
end
