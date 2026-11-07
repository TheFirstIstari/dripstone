defmodule Dripstone.Tracker.GraphTest do
  use ExUnit.Case, async: true

  alias Dripstone.Tracker.{Graph, Network, SampleLoader}

  @now ~U[2026-11-07 17:00:00Z]

  setup_all do
    state = SampleLoader.load(@now)
    %{state: state, large: Graph.build(state.networks["net-lumen"], state.links)}
  end

  test "a 400-member network draws the 150 most-linked members", %{large: graph} do
    assert length(graph.nodes) == 150
    assert graph.total == 400
    assert graph.omitted == 250
  end

  test "the drawn members are the most-linked ones", %{state: state, large: graph} do
    network = state.networks["net-lumen"]
    members = MapSet.new(network.member_ids)

    degree =
      for %{account_ids: {a, b}} <- state.links, a in members and b in members, reduce: %{} do
        acc -> acc |> Map.update(a, 1, &(&1 + 1)) |> Map.update(b, 1, &(&1 + 1))
      end

    lowest_drawn = graph.nodes |> Enum.map(& &1.degree) |> Enum.min()
    drawn = MapSet.new(graph.nodes, & &1.id)

    for id <- network.member_ids, id not in drawn do
      assert Map.get(degree, id, 0) <= lowest_drawn
    end
  end

  test "every edge joins two drawn nodes", %{large: graph} do
    drawn = MapSet.new(graph.nodes, & &1.id)
    assert graph.edges != []
    assert Enum.all?(graph.edges, &(&1.a in drawn and &1.b in drawn))
  end

  test "the layout is deterministic and inside the canvas", %{state: state, large: graph} do
    assert Graph.build(state.networks["net-lumen"], state.links) == graph
    assert Enum.all?(graph.nodes, &(&1.x >= 0.0 and &1.x <= 1.0 and &1.y >= 0.0 and &1.y <= 1.0))
  end

  test "small networks are drawn whole", %{state: state} do
    graph = Graph.build(state.networks["net-c0422"], state.links)
    assert length(graph.nodes) == 14
    assert graph.omitted == 0
  end

  test "degenerate networks don't crash" do
    one = Graph.build(%Network{id: "n1", name: "One", member_ids: ["a"]}, [])
    assert [%{id: "a", x: 0.5, y: 0.5}] = one.nodes
    assert Graph.build(%Network{id: "n0", name: "None", member_ids: []}, []).nodes == []
  end

  test "the cache key changes when membership changes", %{state: state} do
    network = state.networks["net-c0422"]

    refute Graph.cache_key(network) ==
             Graph.cache_key(%{network | member_ids: tl(network.member_ids)})
  end
end
