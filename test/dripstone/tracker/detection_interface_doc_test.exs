defmodule Dripstone.Tracker.DetectionInterfaceDocTest do
  # Reports the examples from openspec/docs/DETECTION_INTERFACE.md through the shared store,
  # so the doc can't drift from the code. Uses the app-wide store: not async.
  use ExUnit.Case, async: false

  alias Dripstone.Alerts
  alias Dripstone.Tracker
  alias Dripstone.Tracker.{SampleStore, State}

  @doc_path Path.expand(
              "../../../openspec/docs/DETECTION_INTERFACE.md",
              __DIR__
            )
  @external_resource @doc_path

  setup do
    previous = SampleStore.get_state()
    # The doc examples run against an empty app; acc-0001..acc-0006 are the
    # members those examples report, so seed them as tracked accounts first.
    accounts =
      for id <- ~w(acc-0001 acc-0002 acc-0003 acc-0004 acc-0005 acc-0006),
          into: %{},
          do: {id, %Dripstone.Tracker.Account{id: id, feed_id: "x", handle: id}}

    :ok = SampleStore.put_state(%State{accounts: accounts})
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

    # scorer_assessment is raised by Tracker.record_assessment/1 (interim), not
    # reported as a finding, so the doc describes it without a finding example.
    expected =
      for %{id: id} <- Alerts.trigger_types(), id != "scorer_assessment", do: id

    assert Enum.sort(triggers) == Enum.sort(expected)
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
