defmodule Dripstone.TrackerFixtures do
  @moduledoc false
  # Finding payloads and states for intake tests. Payloads use atom keys; tests
  # that need JSON-style string keys convert them with `stringify/1`.

  alias Dripstone.Tracker.{Account, Decision, Intake, Network, State}

  @t0 ~U[2026-11-01 12:00:00Z]

  def t0, do: @t0
  def at(hours), do: DateTime.add(@t0, hours * 3600, :second)

  def evidence(overrides \\ %{}) do
    Map.merge(
      %{
        kind: "shared_link",
        strength: "strong",
        explanation: "10 members share a link.",
        account_ids: ["a1", "a2"]
      },
      overrides
    )
  end

  def new_network_finding(overrides \\ %{}) do
    Map.merge(
      %{
        trigger: "new_network",
        severity: "high",
        title: "Network detected",
        observed_at: @t0,
        new_network: %{
          id: "net-1",
          name: "Cluster #1",
          member_ids: ["a1", "a2", "a3"],
          confidence: 86,
          platforms: ["x"]
        },
        evidence: [evidence()]
      },
      overrides
    )
  end

  def finding(network_id, overrides \\ %{}) do
    Map.merge(
      %{
        trigger: "network_growth",
        severity: "medium",
        title: "Network grew",
        observed_at: at(1),
        network_id: network_id,
        evidence: [evidence(%{explanation: "New members joined.", account_ids: ["a4"]})]
      },
      overrides
    )
  end

  @doc "A state containing network `net-1` (created via the intake) and its alert."
  def state_with_network(overrides \\ %{}) do
    founding = new_network_finding(overrides)
    {:ok, _result, state} = Intake.run(state_with_accounts(founding), founding, @t0)
    state
  end

  @doc "A state pre-seeded with accounts covering every member id in `finding`."
  def state_with_accounts(finding \\ new_network_finding()) do
    ids =
      List.flatten([
        get_in(finding, [:new_network, :member_ids]) || [],
        get_in(finding, [:network_updates, :add_member_ids]) || []
      ])

    %State{accounts: Map.new(ids, &{&1, %Account{id: &1, feed_id: "x", handle: &1}})}
    |> State.reindex()
  end

  def update_network(state, id, fun),
    do: %{state | networks: Map.update!(state.networks, id, fun)}

  @doc "Marks network `id` and its open alerts dismissed at `dismissed_at`."
  def dismiss(state, id, dismissed_at) do
    alert = state.alerts |> Map.values() |> Enum.find(&(&1.network_id == id))

    decision = %Decision{
      id: "dec-1",
      alert_id: alert.id,
      network_id: id,
      action: :dismiss,
      by: "Unattributed",
      at: dismissed_at
    }

    state
    |> State.put_alert(%{alert | status: :dismissed, decision_id: "dec-1"})
    |> State.put_decision(decision)
    |> update_network(id, fn %Network{} = n -> %{n | status: :dismissed} end)
  end

  @doc "Recursively converts atom keys to strings and DateTimes to ISO 8601 (like JSON)."
  def stringify(%DateTime{} = at), do: DateTime.to_iso8601(at)

  def stringify(map) when is_map(map),
    do: Map.new(map, fn {k, v} -> {to_string(k), stringify(v)} end)

  def stringify(list) when is_list(list), do: Enum.map(list, &stringify/1)
  def stringify(value), do: value
end
