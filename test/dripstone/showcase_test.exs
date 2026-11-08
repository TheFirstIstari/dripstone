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

  test "a typo observed_at halts with an error instead of raising" do
    dir = Path.join(System.tmp_dir!(), "showcase-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    try do
      raw = Jason.decode!(File.read!(Showcase.corpus_path("v1.json")))
      # Missing timezone: Ecto casts it fine, but DateTime.from_iso8601 rejects it,
      # so this reaches observed_at/1 (a garbage month like "2026-13-40" is caught by cast).
      bad = put_in(raw, ["findings", Access.at(0), "observed_at"], "2026-11-06T09:00:00")
      File.write!(Path.join(dir, "typo.json"), Jason.encode!(bad))
      assert {:error, :invalid_observed_at} = Showcase.load("typo.json", showcase_dir: dir)
    after
      File.rm_rf!(dir)
    end
  end
end
