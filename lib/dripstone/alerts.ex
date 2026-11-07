defmodule Dripstone.Alerts do
  @moduledoc """
  The trigger catalog: the kinds of alert detection can raise.

  Trigger types are listed in order in config, as keyword lists:

      config :dripstone, Dripstone.Alerts,
        trigger_types: [
          [id: "new_network", name: "New network", description: "..."],
          ...
        ]

  Adding a trigger type is one entry in that list; it then appears in alert
  labels and filters. See `docs/TRIGGERS.md`.
  """

  alias Dripstone.Alerts.TriggerType

  @doc "All trigger types, in configured order."
  @spec trigger_types() :: [TriggerType.t()]
  def trigger_types do
    :dripstone
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:trigger_types, [])
    |> Enum.map(&struct!(TriggerType, &1))
  end

  @doc "The trigger type with the given string id, or `nil`."
  @spec get_trigger_type(term()) :: TriggerType.t() | nil
  def get_trigger_type(id) when is_binary(id), do: Enum.find(trigger_types(), &(&1.id == id))
  def get_trigger_type(_id), do: nil
end
