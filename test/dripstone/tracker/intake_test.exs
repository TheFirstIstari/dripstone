defmodule Dripstone.Tracker.IntakeTest do
  use ExUnit.Case, async: true

  import Dripstone.TrackerFixtures

  alias Dripstone.Tracker.{Alert, Evidence, HistoryEntry, Intake, Network}

  defp run!(state, attrs, now) do
    assert {:ok, result, state} = Intake.run(state, attrs, now)
    {result, state}
  end

  defp history(state, network_id),
    do: for(%HistoryEntry{network_id: ^network_id} = h <- state.history, do: h)

  describe "new networks" do
    test "creates a Suspected network, an open alert and a system history entry" do
      {result, state} = run!(state_with_accounts(), new_network_finding(), t0())

      assert %{action: :created, network_id: "net-1", skipped: [], reason: nil} = result

      assert %Network{status: :suspected, confidence: 86, member_ids: ["a1", "a2", "a3"]} =
               state.networks["net-1"]

      assert %Alert{status: :open, trigger_id: "new_network", severity: :high} = result.alert
      assert state.alerts[result.alert.id] == result.alert

      assert [%HistoryEntry{actor: :system, by: "Detection", summary: summary}] =
               history(state, "net-1")

      assert summary =~ "3 members"
    end
  end

  describe "findings for an existing network" do
    test "a valid finding creates an open alert and reports it" do
      state = state_with_network()

      {result, state} =
        run!(state, finding("net-1", %{trigger: "promotion_shift", severity: "high"}), at(2))

      assert %{action: :created, alert: %Alert{status: :open, network_id: "net-1"}} = result
      assert map_size(state.alerts) == 2
    end

    test "carries the AI rationale and before/after values onto the alert" do
      attrs =
        finding("net-1", %{
          trigger: "promotion_shift",
          ai_rationale: %{text: "Same operator, new domain.", generated_at: at(1)},
          comparison: %{
            label: "Main promoted domain",
            before: "deals-a.example (62%)",
            after: "deals-b.example (55%)"
          }
        })

      {%{alert: alert}, _state} = run!(state_with_network(), attrs, at(2))
      assert alert.comparison.before == "deals-a.example (62%)"
      assert alert.comparison.after == "deals-b.example (55%)"
      assert alert.ai_rationale.text == "Same operator, new domain."
    end

    test "applies network updates and records them as system changes" do
      attrs =
        finding("net-1", %{
          network_updates: %{
            add_member_ids: ["a4", "a1"],
            confidence: 91,
            main_domain: "deals-b.example"
          }
        })

      state =
        Map.update!(
          state_with_network(),
          :accounts,
          &Map.merge(&1, state_with_accounts(attrs).accounts)
        )

      {_result, state} = run!(state, attrs, at(2))
      network = state.networks["net-1"]

      assert network.member_ids == ["a1", "a2", "a3", "a4"]
      assert network.joined_at["a4"] == at(1)
      assert network.confidence == 91
      assert network.main_domain == "deals-b.example"
      assert network.last_activity_at == at(1)

      summaries = state |> history("net-1") |> Enum.map(& &1.summary)
      assert "Added 1 member" in summaries
      assert "Confidence 86% → 91%" in summaries
      assert Enum.all?(history(state, "net-1"), &(&1.actor == :system))
    end
  end

  describe "no duplicate open alerts" do
    for {first, second, expected} <- [
          {"medium", "medium", :medium},
          {"medium", "high", :high},
          {"high", "low", :high}
        ] do
      test "two #{first}/#{second} findings merge into one #{expected} alert" do
        state = state_with_network()

        {%{action: :created, alert: %{id: id}}, state} =
          run!(state, finding("net-1", %{severity: unquote(first)}), at(1))

        second =
          finding("net-1", %{
            severity: unquote(second),
            observed_at: at(3),
            evidence: [evidence(%{explanation: "3 more members joined.", account_ids: ["a7"]})]
          })

        {%{action: :merged, alert: alert}, state} = run!(state, second, at(4))

        assert alert.id == id
        assert alert.severity == unquote(expected)
        assert alert.observed_at == at(3)
        assert length(alert.evidence) == 2
        assert Enum.count(state.alerts, fn {_, a} -> a.trigger_id == "network_growth" end) == 1
      end
    end

    test "a different trigger gets its own alert" do
      {%{action: :created}, state} = run!(state_with_network(), finding("net-1"), at(1))

      {%{action: :created}, state} =
        run!(state, finding("net-1", %{trigger: "network_reactivation"}), at(2))

      assert map_size(state.alerts) == 3
    end

    test "a decided alert is not merged into; a new one is opened" do
      {%{alert: alert}, state} = run!(state_with_network(), finding("net-1"), at(1))
      state = %{state | alerts: Map.put(state.alerts, alert.id, %{alert | status: :confirmed})}

      {%{action: :created, alert: new_alert}, _state} = run!(state, finding("net-1"), at(2))
      refute new_alert.id == alert.id
    end

    test "identical evidence is not duplicated when merging" do
      {_, state} = run!(state_with_network(), finding("net-1"), at(1))
      {%{alert: alert}, _state} = run!(state, finding("net-1"), at(2))
      assert [%Evidence{}] = alert.evidence
    end

    test "repeat findings keep merged evidence bounded" do
      {_, state} = run!(state_with_network(), finding("net-1"), at(1))

      state =
        Enum.reduce(1..150, state, fn n, acc ->
          attrs =
            finding("net-1", %{
              evidence: [evidence(%{explanation: "sighting #{n}", account_ids: ["a#{n}"]})]
            })

          {_, next} = run!(acc, attrs, DateTime.add(at(1), n, :second))
          next
        end)

      alert = state.alerts |> Map.values() |> Enum.find(&(&1.trigger_id == "network_growth"))
      assert length(alert.evidence) == 100
      explanations = Enum.map(alert.evidence, & &1.explanation)
      assert "sighting 150" in explanations
      refute "sighting 1" in explanations
    end
  end

  describe "re-alerting after dismissal" do
    setup do
      state = state_with_network() |> dismiss("net-1", at(10))
      dismissed = state.alerts |> Map.values() |> hd()
      %{state: state, dismissed: dismissed}
    end

    test "a finding observed after the dismissal re-alerts and reopens the network",
         %{state: state, dismissed: dismissed} do
      {result, state} = run!(state, finding("net-1", %{observed_at: at(12)}), at(13))

      assert %{action: :created, alert: alert} = result
      assert alert.previously_dismissed_alert_id == dismissed.id
      assert state.networks["net-1"].status == :suspected

      assert Enum.any?(
               history(state, "net-1"),
               &(&1.summary =~ "Re-alerted after dismissal" and &1.actor == :system)
             )
    end

    test "a finding observed before the dismissal is ignored and changes nothing",
         %{state: state} do
      attrs =
        finding("net-1", %{observed_at: at(5), network_updates: %{add_member_ids: ["a9"]}})

      state = Map.update!(state, :accounts, &Map.merge(&1, state_with_accounts(attrs).accounts))

      assert {:ok, %{action: :ignored, alert: nil, reason: :predates_dismissal}, ^state} =
               Intake.run(state, attrs, at(20))
    end

    test "a finding observed exactly at the dismissal counts as stale", %{state: state} do
      assert {:ok, %{action: :ignored}, ^state} =
               Intake.run(state, finding("net-1", %{observed_at: at(10)}), at(20))
    end
  end

  describe "analyst changes are respected" do
    test "a member removed by an analyst is not re-added and is reported as skipped" do
      state =
        state_with_network()
        |> update_network("net-1", fn n ->
          %{n | member_ids: ["a1", "a2"], removed_account_ids: ["a3"]}
        end)

      attrs = finding("net-1", %{network_updates: %{add_member_ids: ["a3", "a5"]}})
      state = Map.update!(state, :accounts, &Map.merge(&1, state_with_accounts(attrs).accounts))
      {result, state} = run!(state, attrs, at(2))

      assert state.networks["net-1"].member_ids == ["a1", "a2", "a5"]
      assert result.skipped == [%{account_id: "a3", reason: :removed_by_analyst}]
    end

    test "an analyst-set name is kept and reported as skipped" do
      state =
        state_with_network()
        |> update_network("net-1", fn n ->
          %{n | name: "Discount Spam Ring", detected_name: "Cluster #1"}
        end)

      attrs = finding("net-1", %{network_updates: %{name: "Cluster #1b"}})
      {result, state} = run!(state, attrs, at(2))

      assert state.networks["net-1"].name == "Discount Spam Ring"
      assert result.skipped == [%{field: :name, reason: :set_by_analyst}]
    end

    test "a name detection gave can still be updated by detection" do
      attrs = finding("net-1", %{network_updates: %{name: "Cluster #1b"}})
      {%{skipped: []}, state} = run!(state_with_network(), attrs, at(2))
      assert state.networks["net-1"].name == "Cluster #1b"
    end
  end
end
