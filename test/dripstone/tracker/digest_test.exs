defmodule Dripstone.Tracker.DigestTest do
  use ExUnit.Case, async: true

  import Dripstone.TrackerFixtures

  alias Dripstone.Tracker.{Digest, Intake}

  defp run!(state, attrs, now) do
    assert {:ok, result, state} = Intake.run(state, attrs, now)
    {result, state}
  end

  # One flipped label in a week: confirm the network's high-severity alert,
  # then the digest holds exactly that flip.
  test "a week with one flipped label produces a one-item digest" do
    state = state_with_network()
    alert = state.alerts |> Map.values() |> hd()
    now = at(2)

    {:ok, %{network: _}, decided, _} =
      Dripstone.Tracker.Decisions.confirm(state, alert.id, %{}, now)

    assert [%{kind: :flipped_label, network_id: "net-1"}] =
             Digest.build(decided, now, Digest.week_ago(now))

    # Older than the window: silent.
    assert Digest.build(decided, now, DateTime.add(now, 3600, :second)) == []
  end

  test "only important changes count: low-severity edges stay silent" do
    state = state_with_accounts(new_network_finding(%{severity: "low"}))
    {_, state} = run!(state, new_network_finding(%{severity: "low"}), t0())

    assert Digest.build(state, at(2), t0()) == []
  end

  test "a high-severity new edge and a re-alert appear, newest first" do
    accounts = %{
      "a1" => %Dripstone.Tracker.Account{id: "a1", feed_id: "x", handle: "a1"},
      "a2" => %Dripstone.Tracker.Account{id: "a2", feed_id: "x", handle: "a2"},
      "a3" => %Dripstone.Tracker.Account{id: "a3", feed_id: "x", handle: "a3"},
      "a4" => %Dripstone.Tracker.Account{id: "a4", feed_id: "x", handle: "a4"}
    }

    state = %Dripstone.Tracker.State{accounts: accounts}
    {_, state} = run!(state, new_network_finding(), t0())

    {_, state} =
      run!(
        state,
        finding("net-1", %{
          trigger: "network_growth",
          severity: "high",
          title: "Grew",
          network_updates: %{add_member_ids: ["a4"]}
        }),
        at(3)
      )

    items = Digest.build(state, at(4), t0())
    assert Enum.map(items, & &1.kind) == [:new_edge, :new_edge]
    assert [%{at: first} | [%{at: second} | _]] = items
    assert DateTime.compare(first, second) != :lt
  end
end
