defmodule Dripstone.Alerts.TriggerType do
  @moduledoc """
  A kind of alert detection can raise, such as `"promotion_shift"`.

  This is metadata only (id, display name, one-sentence description), used for
  labels and filters. The detection logic for a trigger type lives on the
  detection side, which reports findings tagged with the type's `id`.
  """

  @enforce_keys [:id, :name, :description]
  defstruct [:id, :name, :description]

  @type t :: %__MODULE__{id: String.t(), name: String.t(), description: String.t()}
end
