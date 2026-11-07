defmodule Dripstone.ShowcaseTest do
  use ExUnit.Case, async: true

  alias Dripstone.Showcase
  alias Dripstone.Tracker.{Link, Queries}

  test "loads the hand-built corpus through the real Report/Rules path" do
    assert {:ok, state} = Showcase.load()

    assert map_size(state.accounts) == 6

    kinds = state.links |> Enum.map(& &1.kind) |> Enum.sort() |> Enum.uniq()
    assert :repost_ring in kinds
    assert :shared_link in kinds
    assert :timing_sync in kinds

    # The `none` relation creates no link.
    for %Link{account_ids: {a, b}} <- state.links do
      refute "casual_reader" in [state.accounts[a].handle, state.accounts[b].handle]
    end

    # Link provenance records the group finding that produced it.
    assert Enum.all?(state.links, &(&1.provenance != []))
  end

  test "overview runs on the showcase corpus and renders linked networks" do
    assert {:ok, state} = Showcase.load()
    overview = Queries.overview(state, DateTime.utc_now())

    assert overview.tracked_accounts == 6
    assert overview.suspected_networks >= 1
    assert overview.open_alerts >= 1
  end

  test "relation labels round-trip through the Answers relation set" do
    assert Map.has_key?(Dripstone.Tracker.Answers.relations(), "repost-ring")
    assert Map.has_key?(Dripstone.Tracker.Answers.relations(), "shared-link")
    assert Map.has_key?(Dripstone.Tracker.Answers.relations(), "timing-sync")
    assert Map.has_key?(Dripstone.Tracker.Answers.relations(), "audience-overlap")
    assert Dripstone.Tracker.Answers.relations()["none"] == :none
  end
end
