defmodule Dripstone.ShowcaseTest do
  use ExUnit.Case, async: true

  alias Dripstone.Showcase
  alias Dripstone.Tracker.{Link, Queries}

  test "loads the hand-built corpus through the real intake" do
    assert {:ok, state} = Showcase.load()

    assert map_size(state.accounts) == 6
    assert %{"net-showcase-ring" => ring, "net-showcase-lone" => lone} = state.networks

    assert Enum.sort(ring.member_ids) ==
             Enum.sort([
               "show-ring-1",
               "show-ring-2",
               "show-link-1",
               "show-timer-1",
               "show-timer-2"
             ])

    assert lone.member_ids == ["show-lone-1"]

    kinds = state.links |> Enum.map(& &1.kind) |> Enum.sort()
    assert kinds == [:repost_ring, :shared_link, :timing_sync]

    # Evidence carries the scorer relation labels the links were built from.
    relations =
      state.alerts
      |> Map.values()
      |> Enum.flat_map(& &1.evidence)
      |> Enum.flat_map(&Map.get(&1, :account_ids, []))

    assert "show-ring-1" in relations
  end

  test "overview runs on the showcase corpus and renders linked networks" do
    assert {:ok, state} = Showcase.load()
    overview = Queries.overview(state, DateTime.utc_now())

    assert overview.tracked_accounts == 6
    assert overview.suspected_networks == 2
    assert overview.open_alerts == 3

    names = Enum.map(overview.recent_networks, & &1.network.name)
    assert "Sunrise Repost Ring" in names
  end

  test "relation labels round-trip through the link enum" do
    assert Link.relation_kind("repost-ring") == :repost_ring
    assert Link.relation_kind("shared-link") == :shared_link
    assert Link.relation_kind("timing-sync") == :timing_sync
    assert Link.relation_kind("audience-overlap") == :audience_overlap
    assert Link.relation_kind("none") == :other

    assert Link.relation_label(:repost_ring) == "repost-ring"
    assert Link.relation_label(:timing_sync) == "timing-sync"
    assert Link.relation_label(:audience_overlap) == "audience-overlap"
  end
end
