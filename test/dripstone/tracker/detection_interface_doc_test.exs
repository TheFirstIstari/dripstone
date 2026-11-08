defmodule Dripstone.Tracker.DetectionInterfaceDocTest do
  # Reports the examples from openspec/docs/DETECTION_INTERFACE.md through the shared
  # store, so the doc can't drift from the code. Uses the app-wide store: not async.
  use Dripstone.DataCase, async: false

  alias Dripstone.Alerts
  alias Dripstone.Tracker
  alias Dripstone.Tracker.{Account, Network, State, Store}

  @doc_path Path.expand("../../../openspec/docs/DETECTION_INTERFACE.md", __DIR__)
  @external_resource @doc_path

  # The app the examples run against, as the doc describes it: one known network,
  # net-example, with four members on X.
  setup do
    {:ok, previous} = Store.load()

    members =
      for n <- 1..4, do: %Account{id: "acc-net-#{n}", feed_id: "x", handle: "net_member_#{n}"}

    network = %Network{
      id: "net-example",
      name: "Example network",
      member_ids: Enum.map(members, & &1.id),
      platforms: ["x"],
      main_domain: "deals-a.example",
      confidence: 80,
      assessment: %{trajectory: "fading"}
    }

    :ok =
      Store.save(
        %State{
          accounts: Map.new(members, &{&1.id, &1}),
          networks: %{"net-example" => network}
        }
        |> State.reindex()
      )

    on_exit(fn -> :ok = Store.save(previous) end)
    :ok
  end

  defp examples do
    ~r/```json\n(.*?)```/s
    |> Regex.scan(File.read!(@doc_path), capture: :all_but_first)
    |> Enum.map(fn [json] -> Jason.decode!(json) end)
  end

  test "the doc shows every finding kind" do
    assert examples() |> Enum.map(& &1["kind"]) |> Enum.uniq() |> Enum.sort() ==
             ~w(account group trend)
  end

  test "every example is accepted in order, and together they raise every trigger type" do
    results =
      for example <- examples() do
        assert {:ok, result} = Tracker.report_finding(example),
               "the #{example["kind"]} example at #{example["observed_at"]} was rejected"

        result
      end

    raised = for %{alerts: alerts} <- results, %{alert: alert} <- alerts, do: alert.trigger_id
    assert Enum.sort(raised) == Alerts.trigger_types() |> Enum.map(& &1.id) |> Enum.sort()

    [account | _] = results
    assert account.alerts == []

    {:ok, state} = Store.load()
    network = state.networks["net-example"]
    assert length(network.member_ids) == 6
    assert network.main_domain == "deals-b.example"
    assert network.assessment.trajectory == "stable"

    # just_a_person answered 0.12 on its member question, so the new network has three.
    new_network = Enum.find(Map.values(state.networks), &(&1.id != "net-example"))
    assert length(new_network.member_ids) == 3
  end

  test "the documented rejection example matches the real errors" do
    [_account, group | _] = examples()

    bad = %{
      group
      | "accounts" => Enum.take(group["accounts"], 1),
        "answers" => %{"coordinated" => %{"type" => "noul", "noul" => 1.4}}
    }

    assert {:error, errors} = Tracker.report_finding(bad)

    assert errors == %{
             accounts: ["a group needs at least two different accounts"],
             answers: ["coordinated: noul must be a number from 0 to 1"]
           }
  end
end
