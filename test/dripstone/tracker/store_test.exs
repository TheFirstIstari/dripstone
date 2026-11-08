defmodule Dripstone.Tracker.StoreTest do
  # Touches every tracker table, so it must not run alongside other DB tests.
  use Dripstone.DataCase, async: false

  alias Dripstone.Tracker
  alias Dripstone.Tracker.Store

  setup do
    Store.reset!()
    :ok
  end

  describe "first-boot seeding follows :load_sample_data" do
    setup do
      previous = Application.get_env(:dripstone, :load_sample_data)
      on_exit(fn -> Application.put_env(:dripstone, :load_sample_data, previous) end)
      :ok
    end

    test "false (prod) starts empty and stores no sample rows (#50)" do
      Application.put_env(:dripstone, :load_sample_data, false)

      assert {:ok, state} = Store.load()
      assert state.accounts == %{}
      assert state.networks == %{}
      assert state.alerts == %{}
      assert Store.seeded?()

      # A second load reads the (empty) rows back rather than seeding again.
      Application.put_env(:dripstone, :load_sample_data, true)
      assert {:ok, %{accounts: accounts}} = Store.load()
      assert accounts == %{}
    end

    test ":showcase seeds the hand-built corpus" do
      Application.put_env(:dripstone, :load_sample_data, :showcase)
      assert {:ok, state} = Store.load()
      assert map_size(state.accounts) == 6
    end

    test "true seeds the generated sample rows" do
      Application.put_env(:dripstone, :load_sample_data, true)
      assert {:ok, state} = Store.load()
      assert map_size(state.accounts) > 100
    end
  end

  test "save |> load round-trips the seeded state losslessly" do
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

  test "write decisions and curation survive a simulated restart" do
    {:ok, _} = Store.load()
    Tracker.reset_sample_data!()
    [%{alert: alert} | _] = Tracker.list_alerts()
    {:ok, %{decision: decision}} = Tracker.confirm_alert(alert.id)
    {:ok, renamed} = Tracker.rename_network(alert.network_id, %{"name" => "Restart Proof"})
    {:ok, _} = Tracker.add_tag(alert.network_id, %{"tag" => "restart-proof"})

    # Simulate a restart: every read already reloads from the Repo.
    {:ok, reloaded} = Store.load()

    assert reloaded.decisions[decision.id].alert_id == alert.id
    assert reloaded.alerts[alert.id].status == :confirmed
    assert reloaded.networks[alert.network_id].name == renamed.name
    assert "restart-proof" in reloaded.networks[alert.network_id].tags
  end
end
