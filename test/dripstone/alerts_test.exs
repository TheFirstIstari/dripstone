defmodule Dripstone.AlertsTest do
  use ExUnit.Case, async: true

  alias Dripstone.Alerts
  alias Dripstone.Alerts.TriggerType

  describe "trigger catalog" do
    test "contains the five initial trigger types in order" do
      assert [
               %TriggerType{id: "new_network", name: "New network"},
               %TriggerType{id: "network_growth", name: "Network growth"},
               %TriggerType{id: "network_reactivation", name: "Network reactivation"},
               %TriggerType{id: "promotion_shift", name: "Promotion shift"},
               %TriggerType{id: "coordination_rising", name: "Coordination rising"}
             ] = Alerts.trigger_types()
    end

    test "every trigger type has a unique id and a one-sentence description" do
      types = Alerts.trigger_types()
      ids = Enum.map(types, & &1.id)
      assert ids == Enum.uniq(ids)

      for %TriggerType{description: description} <- types do
        assert is_binary(description) and String.ends_with?(description, ".")
      end
    end

    test "get_trigger_type/1 looks up by string id" do
      assert %TriggerType{name: "Promotion shift"} = Alerts.get_trigger_type("promotion_shift")
    end

    test "get_trigger_type/1 returns nil for unknown or non-string ids" do
      assert Alerts.get_trigger_type("does-not-exist") == nil
      assert Alerts.get_trigger_type(nil) == nil
      assert Alerts.get_trigger_type(:new_network) == nil
    end
  end
end
