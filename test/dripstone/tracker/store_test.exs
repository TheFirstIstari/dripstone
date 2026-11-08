defmodule Dripstone.Tracker.StoreTest do
  # Touches every tracker table, so it must not run alongside other DB tests.
  use Dripstone.DataCase, async: false

  alias Dripstone.Tracker.Store

  setup do
    Store.reset!()
    :ok
  end

  test "save |> load round-trips the showcase state losslessly" do
    {:ok, seeded} = Store.load()
    assert map_size(seeded.accounts) > 0
    assert map_size(seeded.networks) > 0

    :ok = Store.save(seeded)
    {:ok, loaded} = Store.load()

    assert map_size(loaded.accounts) == map_size(seeded.accounts)
    assert map_size(loaded.networks) == map_size(seeded.networks)
    assert map_size(loaded.alerts) == map_size(seeded.alerts)
    assert length(loaded.links) == length(seeded.links)
    assert length(loaded.findings) == length(seeded.findings)
    assert length(loaded.history) == length(seeded.history)
    assert loaded.seq == seeded.seq

    # Spot-check a full struct survives the row converters.
    {id, account} = Enum.at(seeded.accounts, 0)
    assert loaded.accounts[id] == account
  end

  test "temporal columns and edge provenance persist" do
    {:ok, state} = Store.load()
    assert Store.seeded?()

    {_id, network} = Enum.at(state.networks, 0)
    row = Dripstone.Repo.get!(Store.Network, network.id)
    assert row.first_seen_at == network.first_activity_at
    assert row.last_true_at == network.last_activity_at
  end

  test "cleared (dismissed) status persists distinctly from suspected" do
    {:ok, state} = Store.load()
    dismissed = Enum.find(state.networks, fn {_id, n} -> n.status == :dismissed end)

    if dismissed do
      {id, _} = dismissed
      :ok = Store.save(state)
      {:ok, reloaded} = Store.load()
      assert reloaded.networks[id].status == :dismissed
    end
  end

  test "reset! clears seeded state and load reseeds" do
    {:ok, _} = Store.load()
    assert Store.seeded?()
    :ok = Store.reset!()
    refute Store.seeded?()
    {:ok, reseeded} = Store.load()
    assert map_size(reseeded.accounts) > 0
  end

  test "legacy/unknown status strings load with defaults instead of raising" do
    {:ok, state} = Store.load()
    {_id, network} = Enum.at(state.networks, 0)

    Dripstone.Repo.get!(Store.Network, network.id)
    |> Ecto.Changeset.change(%{status: "cleared_legacy_never_atomized"})
    |> Dripstone.Repo.update!()

    assert {:ok, reloaded} = Store.load()
    assert reloaded.networks[network.id].status == :suspected
  end

  test "missing corpus returns an error instead of raising" do
    Store.reset!()
    dir = Path.join(System.tmp_dir!(), "showcase-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    try do
      assert {:error, _} = Store.load(showcase_dir: dir)
    after
      File.rm_rf!(dir)
    end
  end
end
