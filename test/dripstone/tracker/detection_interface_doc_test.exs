defmodule Dripstone.Tracker.DetectionInterfaceDocTest do
  # Reports the examples from docs/DETECTION_INTERFACE.md through the shared store,
  # so the doc can't drift from the code. Uses the app-wide store: not async.
  use ExUnit.Case, async: false

  alias Dripstone.Alerts
  alias Dripstone.Tracker
  alias Dripstone.Tracker.{SampleStore, State}

  @doc_path Path.expand("../../../docs/DETECTION_INTERFACE.md", __DIR__)
  @external_resource @doc_path

  setup do
    previous = SampleStore.get_state()
    :ok = SampleStore.put_state(%State{})
    on_exit(fn -> SampleStore.put_state(previous) end)
    :ok
  end

  defp examples do
    ~r/```json\n(.*?)```/s
    |> Regex.scan(File.read!(@doc_path), capture: :all_but_first)
    |> Enum.map(fn [json] -> Jason.decode!(json) end)
  end

  test "the doc has one example per initial trigger type" do
    triggers = Enum.map(examples(), & &1["trigger"])
    assert Enum.sort(triggers) == Alerts.trigger_types() |> Enum.map(& &1.id) |> Enum.sort()
  end

  test "every example is accepted by report_finding/1, in order" do
    results =
      for example <- examples() do
        assert {:ok, result} = Tracker.report_finding(example),
               "example for #{example["trigger"]} was rejected"

        result
      end

    assert Enum.all?(results, &(&1.action == :created))

    state = SampleStore.get_state()
    network = state.networks["net-example"]
    assert length(network.member_ids) == 6
    assert network.main_domain == "deals-b.example"
    assert network.confidence == 91
    assert map_size(state.alerts) == 4
  end

  test "the documented rejection example matches the real errors" do
    [first | _] = examples()

    assert {:error, errors} =
             Tracker.report_finding(%{first | "trigger" => "does-not-exist", "evidence" => []})

    assert errors.trigger == ["unknown trigger \"does-not-exist\""]
    assert errors.evidence == ["must contain at least one item"]
  end
end
