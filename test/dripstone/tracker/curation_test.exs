defmodule Dripstone.Tracker.CurationTest do
  # Changes the app-wide store, so it must not run alongside other tests.
  use Dripstone.DataCase, async: false

  alias Dripstone.Tracker
  alias Dripstone.Tracker.Store

  setup do
    {:ok, previous} = Store.load()
    on_exit(fn -> :ok = Store.save(previous) end)
    Tracker.reset_sample_data!()
    :ok = Tracker.subscribe()
    :ok
  end

  defp network(id), do: Tracker.get_network(id).network
  defp members(id), do: network(id).member_ids
  defp latest_history(id), do: hd(Tracker.get_network(id).history)

  defp error_on(%Ecto.Changeset{errors: errors}, field),
    do: errors |> Keyword.fetch!(field) |> elem(0)

  describe "rename" do
    test "renames a network and keeps the detected name" do
      assert {:ok, renamed} =
               Tracker.rename_network("net-c0421", %{"name" => "Discount Spam Ring 2"})

      assert renamed.name == "Discount Spam Ring 2"
      assert renamed.detected_name == "Cluster #0421"

      {:ok, again} = Tracker.rename_network("net-c0421", %{"name" => "Rally Bots"})
      assert again.detected_name == "Cluster #0421", "the original detected name is kept"

      assert %{
               actor: :analyst,
               by: "Detection",
               summary: "Renamed Discount Spam Ring 2 → Rally Bots"
             } =
               latest_history("net-c0421")

      assert_receive {:network_updated, "net-c0421"}
    end

    test "an empty or over-long name is refused and nothing changes" do
      assert {:error, changeset} = Tracker.rename_network("net-c0421", %{"name" => "   "})
      assert error_on(changeset, :name) == "can't be blank"

      assert {:error, changeset} =
               Tracker.rename_network("net-c0421", %{"name" => String.duplicate("a", 81)})

      assert error_on(changeset, :name) =~ "at most"
      assert network("net-c0421").name == "Cluster #0421"
    end
  end

  describe "tags" do
    test "tags are normalized to lowercase with hyphens" do
      assert {:ok, tagged} = Tracker.add_tag("net-c0421", %{"tag" => "  Crypto Scam "})
      assert "crypto-scam" in tagged.tags
      assert latest_history("net-c0421").summary == "Tagged #crypto-scam"
    end

    test "invalid tags are refused" do
      assert {:error, changeset} = Tracker.add_tag("net-c0421", %{"tag" => "no!good"})
      assert error_on(changeset, :tag) =~ "lowercase letters"
      assert {:error, _} = Tracker.add_tag("net-c0421", %{"tag" => String.duplicate("a", 33)})
    end

    test "at most 20 tags per network, and duplicates are ignored" do
      for n <- 1..20, do: {:ok, _} = Tracker.add_tag("net-c0421", %{"tag" => "t#{n}"})
      assert {:ok, %{tags: tags}} = Tracker.add_tag("net-c0421", %{"tag" => "t1"})
      assert length(tags) == 20

      assert {:error, changeset} = Tracker.add_tag("net-c0421", %{"tag" => "t21"})
      assert error_on(changeset, :tag) == "a network can have at most 20 tags"
    end

    test "tags can be removed and are suggested by prefix" do
      {:ok, _} = Tracker.add_tag("net-c0421", %{"tag" => "crypto-scam"})
      assert Tracker.list_tags("cry") == ["crypto-scam"]

      {:ok, untagged} = Tracker.remove_tag("net-c0421", "crypto-scam")
      refute "crypto-scam" in untagged.tags
      assert Tracker.list_tags("cry") == []
    end
  end

  describe "notes" do
    test "notes are stored newest first with author and time" do
      {:ok, _} = Tracker.add_note("net-c0421", %{"body" => "First look."})
      {:ok, note} = Tracker.add_note("net-c0421", %{"body" => "Second look."})

      assert note.by == "Detection"

      assert [%{body: "Second look."}, %{body: "First look."}] =
               Tracker.get_network("net-c0421").notes
    end

    test "notes and renames are attributed to the acting analyst" do
      {:ok, note} =
        Tracker.add_note("net-c0421", %{"body" => "Looking."}, "analyst@example.com")

      assert note.by == "analyst@example.com"

      {:ok, _} =
        Tracker.rename_network(
          "net-c0421",
          %{"name" => "Analyst Name"},
          "analyst@example.com"
        )

      assert %{
               actor: :analyst,
               by: "analyst@example.com",
               summary: "Renamed Cluster #0421 → Analyst Name"
             } = latest_history("net-c0421")
    end

    test "empty and over-long notes are refused" do
      assert {:error, changeset} = Tracker.add_note("net-c0421", %{"body" => ""})
      assert error_on(changeset, :body) == "can't be blank"
      assert {:error, _} = Tracker.add_note("net-c0421", %{"body" => String.duplicate("x", 2001)})
      assert {:ok, _} = Tracker.add_note("net-c0421", %{"body" => String.duplicate("x", 2000)})
    end
  end

  describe "membership" do
    test "removing a member records it so detection can't re-add it" do
      [member | _] = members("net-c0421")
      {:ok, updated} = Tracker.remove_members("net-c0421", [member])

      refute member in updated.member_ids
      assert member in updated.removed_account_ids
      assert latest_history("net-c0421").summary == "Removed 1 member"

      {:ok, %{skipped: [%{account_id: ^member}]}} =
        Tracker.apply_finding(%{
          trigger: "network_growth",
          severity: "low",
          title: "Grew",
          observed_at: DateTime.utc_now(),
          network_id: "net-c0421",
          evidence: [%{explanation: "x", strength: "weak"}],
          network_updates: %{add_member_ids: [member]}
        })

      refute member in members("net-c0421")
    end

    test "adding an account (including from another network) and re-adding a removed one" do
      [other | _] = members("net-c0422")
      {:ok, added} = Tracker.add_members("net-c0421", [other])
      assert other in added.member_ids
      assert other in members("net-c0422"), "an account can belong to more than one network"

      {:ok, _} = Tracker.remove_members("net-c0421", [other])
      {:ok, readded} = Tracker.add_members("net-c0421", [other])
      assert other in readded.member_ids
      refute other in readded.removed_account_ids

      assert Enum.any?(Tracker.get_account(other).networks, &(&1.id == "net-c0421"))
    end

    test "unknown accounts and non-members are refused" do
      assert {:error, :unknown_account} = Tracker.add_members("net-c0421", ["acc-nope"])
      [outsider | _] = members("net-c0422")
      assert {:error, :not_a_member} = Tracker.remove_members("net-c0421", [outsider])
      assert {:error, :no_members_selected} = Tracker.remove_members("net-c0421", [])
    end

    test "moving members takes them out of one network and into another" do
      moving = members("net-c0421") |> Enum.take(3)
      {:ok, %{from: from, to: to}} = Tracker.move_members("net-c0421", "net-c0425", moving)

      assert Enum.all?(moving, &(&1 not in from.member_ids and &1 in to.member_ids))
      assert latest_history("net-c0421").summary == "Moved 3 members to Cluster #0425"
      assert latest_history("net-c0425").summary == "Received 3 members from Cluster #0421"
      assert {:error, :same_network} = Tracker.move_members("net-c0421", "net-c0421", moving)
    end
  end

  describe "merge" do
    test "the target gains members, alerts, notes and tags, and the source is retired" do
      {:ok, _} = Tracker.add_note("net-c0425", %{"body" => "Merging this."})
      {:ok, _} = Tracker.add_tag("net-c0425", %{"tag" => "nft"})
      source = Tracker.get_network("net-c0425")
      target_members = members("net-c0421")

      {:ok, merged} = Tracker.merge_networks("net-c0425", "net-c0421")

      assert Enum.all?(source.network.member_ids ++ target_members, &(&1 in merged.member_ids))
      assert "nft" in merged.tags
      detail = Tracker.get_network("net-c0421")
      assert Enum.any?(detail.notes, &(&1.body == "Merging this."))
      assert Enum.all?(source.alerts, fn a -> Enum.any?(detail.alerts, &(&1.id == a.id)) end)

      retired = Tracker.get_network("net-c0425")
      assert retired.network.retired_into == "net-c0421"
      assert retired.retired_into.id == "net-c0421"
      refute Enum.any?(Tracker.list_networks(), &(&1.network.id == "net-c0425"))
      assert {:error, :retired} = Tracker.rename_network("net-c0425", %{"name" => "x"})
    end

    test "status: Confirmed > Suspected > Dismissed" do
      # c0423 is Dismissed, c0421 is Suspected, c0420 is Confirmed.
      {:ok, %{status: :suspected}} = Tracker.merge_networks("net-c0423", "net-c0421")
      {:ok, %{status: :confirmed}} = Tracker.merge_networks("net-c0421", "net-c0420")
    end

    test "a network can't be merged into itself" do
      assert {:error, :same_network} = Tracker.merge_networks("net-c0421", "net-c0421")
    end

    test "merge rewires back-references pointing at the retired source" do
      {:ok, _} = Tracker.relate_networks("net-c0425", "net-c0422", "Shared infra")
      assert "net-c0425" in network("net-c0422").related_ids
      assert_received {:network_updated, "net-c0425"}
      assert_received {:network_updated, "net-c0422"}

      {:ok, _} = Tracker.merge_networks("net-c0425", "net-c0421")

      assert network("net-c0422").related_ids == ["net-c0421"]
      assert network("net-c0421").related_ids == ["net-c0422"]
      refute "net-c0425" in network("net-c0421").related_ids
      assert_received {:network_updated, "net-c0425"}
      assert_received {:network_updated, "net-c0421"}
      assert_received {:network_updated, "net-c0422"}
    end
  end

  describe "split" do
    test "selected members move into a new Suspected network" do
      picked = members("net-sunrise") |> Enum.take(8)
      remaining = length(members("net-sunrise")) - 8

      {:ok, split} = Tracker.split_network("net-sunrise", picked, %{"name" => "Sunrise Offshoot"})

      assert split.name == "Sunrise Offshoot"
      assert split.status == :suspected
      assert split.detected_name == nil
      assert Enum.sort(split.member_ids) == Enum.sort(picked)
      assert length(members("net-sunrise")) == remaining
      assert Enum.any?(Tracker.list_networks(), &(&1.network.id == split.id))
    end

    test "split fragment inherits a Confirmed source status" do
      picked = members("net-bluewave") |> Enum.take(3)

      {:ok, split} =
        Tracker.split_network("net-bluewave", picked, %{"name" => "Bluewave Offshoot"})

      assert split.status == :confirmed
    end

    test "splitting every member, none, or with no name is refused" do
      all = members("net-c0422")

      assert {:error, :cannot_split_all} =
               Tracker.split_network("net-c0422", all, %{"name" => "All"})

      assert {:error, :no_members_selected} =
               Tracker.split_network("net-c0422", [], %{"name" => "None"})

      assert {:error, %Ecto.Changeset{}} =
               Tracker.split_network("net-c0422", Enum.take(all, 1), %{"name" => ""})
    end
  end

  describe "related networks" do
    test "relations are symmetric and can be removed" do
      {:ok, _} = Tracker.relate_networks("net-c0421", "net-c0425", "Same ticket domain family")

      assert [%{id: "net-c0425"}] = Tracker.get_network("net-c0421").related
      assert [%{id: "net-c0421"}] = Tracker.get_network("net-c0425").related
      assert latest_history("net-c0421").summary =~ "Same ticket domain family"

      {:ok, _} = Tracker.unrelate_networks("net-c0425", "net-c0421")
      assert Tracker.get_network("net-c0421").related == []
      assert Tracker.get_network("net-c0425").related == []
    end
  end

  test "history marks analyst changes and detection changes" do
    {:ok, _} = Tracker.rename_network("net-c0421", %{"name" => "Renamed"})

    {:ok, _} =
      Tracker.apply_finding(%{
        trigger: "network_growth",
        severity: "low",
        title: "Grew",
        observed_at: DateTime.utc_now(),
        network_id: "net-c0421",
        evidence: [%{explanation: "x", strength: "weak"}],
        network_updates: %{add_member_ids: [hd(members("net-c0422"))]}
      })

    [system, analyst | _] = Tracker.get_network("net-c0421").history
    assert system.actor == :system and system.summary == "Added 1 member"
    assert analyst.actor == :analyst and analyst.summary =~ "Renamed"
  end
end
