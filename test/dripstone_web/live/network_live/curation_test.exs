defmodule DripstoneWeb.NetworkLive.CurationTest do
  # Changes the app-wide tracker store, so it must not run alongside other tests.
  use DripstoneWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Dripstone.Tracker
  alias Dripstone.Tracker.SampleStore

  setup do
    previous = SampleStore.get_state()
    on_exit(fn -> SampleStore.put_state(previous) end)
    Tracker.reset_sample_data!()
    :ok
  end

  defp members(id), do: Tracker.get_network(id).network.member_ids

  defp select(view, ids),
    do: Enum.each(ids, &(view |> element("#select-#{&1}") |> render_click()))

  defp pending(view, type, params \\ %{}) do
    view |> element("#open-#{type}") |> render_click()
    if params != %{}, do: view |> form("#pending-form", pending: params) |> render_change()
    view
  end

  defp confirm(view), do: view |> form("#pending-form") |> render_submit()

  describe "rename" do
    test "renames the network and keeps the detected name", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/networks/net-c0421")

      view |> element("#edit-name") |> render_click()
      view |> form("#rename-form", network: %{name: "Rally Ticket Bots"}) |> render_submit()

      assert has_element?(view, "#page-title", "Rally Ticket Bots")
      assert has_element?(view, "#detected-as", "Detected as Cluster #0421")
      assert Tracker.get_network("net-c0421").network.name == "Rally Ticket Bots"
    end

    test "an empty name is refused with an explanation", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/networks/net-c0421")

      view |> element("#edit-name") |> render_click()
      html = view |> form("#rename-form", network: %{name: "  "}) |> render_submit()

      assert html =~ "can&#39;t be blank"
      assert Tracker.get_network("net-c0421").network.name == "Cluster #0421"
    end
  end

  describe "tags" do
    test "a typed tag is normalized and shown", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/networks/net-c0421")

      view |> form("#tag-form", tag: %{tag: "Crypto Scam"}) |> render_submit()

      assert has_element?(view, "#tag-crypto-scam", "#crypto-scam")
    end

    test "existing tags from other networks are suggested and can be picked", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/networks/net-c0421")

      view |> form("#tag-form", tag: %{tag: "disc"}) |> render_change()
      assert has_element?(view, "#tag-suggestions", "#discount-spam")

      view |> element("#tag-suggestions button", "#discount-spam") |> render_click()
      assert has_element?(view, "#tag-discount-spam")
      refute has_element?(view, "#tag-suggestions")
    end

    test "tags can be removed", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/networks/net-sunrise")

      view |> element("#tag-discount-spam button") |> render_click()
      refute has_element?(view, "#tag-discount-spam")
    end

    test "invalid tags show the format rule", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/networks/net-c0421")
      html = view |> form("#tag-form", tag: %{tag: "no!good"}) |> render_submit()
      assert html =~ "lowercase letters"
    end
  end

  test "notes appear newest first with author and time", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/networks/net-c0421?view=notes")

    view |> form("#note-form", note: %{body: "First look."}) |> render_submit()
    view |> form("#note-form", note: %{body: "Second look."}) |> render_submit()

    bodies =
      view
      |> render()
      |> LazyHTML.from_document()
      |> LazyHTML.query("#notes > li[id^=note-] p:first-child")
      |> Enum.map(&LazyHTML.text/1)
      |> Enum.map(&String.trim/1)

    assert bodies == ["Second look.", "First look."]
    assert has_element?(view, "#notes", "Unattributed")
    assert has_element?(view, "#tab-notes", "Notes (2)")
  end

  describe "membership" do
    test "removing selected members asks first, then removes them", %{conn: conn} do
      [a, b | _] = members("net-c0421")
      {:ok, view, _html} = live(conn, "/networks/net-c0421")

      select(view, [a, b])
      assert has_element?(view, "#selection-bar", "2 selected")

      pending(view, "remove")
      assert has_element?(view, "#pending-impact", "Removes 2 members from Cluster #0421")

      confirm(view)
      refute has_element?(view, "#member-#{a}")
      refute has_element?(view, "#member-#{b}")
      assert a in Tracker.get_network("net-c0421").network.removed_account_ids
    end

    test "accounts can be found and added", %{conn: conn} do
      outsider = Tracker.get_account(hd(members("net-c0422"))).account
      {:ok, view, _html} = live(conn, "/networks/net-c0421")

      pending(view, "add", %{q: outsider.handle})
      view |> element("#add-result-#{outsider.id} button") |> render_click()

      assert has_element?(view, "#member-#{outsider.id}")
      assert outsider.id in members("net-c0421")
    end

    test "moving members to another network", %{conn: conn} do
      moving = members("net-c0421") |> Enum.take(3)
      {:ok, view, _html} = live(conn, "/networks/net-c0421")

      select(view, moving)
      pending(view, "move", %{target: "net-c0425"})

      assert has_element?(
               view,
               "#pending-impact",
               "Moves 3 members from Cluster #0421 to Cluster #0425"
             )

      confirm(view)
      assert Enum.all?(moving, &(&1 in members("net-c0425")))
      refute Enum.any?(moving, &(&1 in members("net-c0421")))
    end

    test "splitting selected members into a new network", %{conn: conn} do
      picked = members("net-sunrise") |> Enum.take(8)
      total = length(members("net-sunrise"))
      {:ok, view, _html} = live(conn, "/networks/net-sunrise")

      select(view, picked)
      pending(view, "split", %{name: "Sunrise Offshoot"})

      assert has_element?(
               view,
               "#pending-impact",
               "Creates a new Suspected network with 8 members"
             )

      confirm(view)

      assert [%{network: offshoot}] =
               Tracker.list_networks() |> Enum.filter(&(&1.network.name == "Sunrise Offshoot"))

      assert offshoot.status == :suspected
      assert Enum.sort(offshoot.member_ids) == Enum.sort(picked)
      assert length(members("net-sunrise")) == total - 8
    end

    test "splitting every member is refused with an explanation", %{conn: conn} do
      all = members("net-c0422")
      {:ok, view, _html} = live(conn, "/networks/net-c0422")

      select(view, all)
      pending(view, "split", %{name: "Everything"})
      confirm(view)

      assert has_element?(view, "#pending-error", "Leave at least one member behind")
      assert length(members("net-c0422")) == length(all)
    end
  end

  describe "merge" do
    test "the confirmation states the impact, then merging retires this network", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/networks/net-c0425")

      pending(view, "merge", %{target: "net-c0423"})

      assert has_element?(
               view,
               "#pending-impact",
               "Moves 26 members, 1 alert, 0 notes and 0 tags into Cluster #0423"
             )

      assert {:error, {:live_redirect, %{to: "/networks/net-c0423"}}} = confirm(view)

      # c0425 was Suspected and c0423 Dismissed: the merged network is Suspected.
      assert Tracker.get_network("net-c0423").network.status == :suspected
      assert Tracker.get_network("net-c0425").network.retired_into == "net-c0423"
    end

    test "cancelling a merge leaves everything unchanged", %{conn: conn} do
      before = SampleStore.get_state()
      {:ok, view, _html} = live(conn, "/networks/net-c0425")

      pending(view, "merge", %{target: "net-c0423"})
      assert has_element?(view, "#pending-modal")

      view |> element("#cancel-pending") |> render_click()

      refute has_element?(view, "#pending-modal")
      assert SampleStore.get_state() == before
    end
  end

  test "relating networks lists each on the other", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/networks/net-c0421")

    pending(view, "relate", %{target: "net-c0425", note: "Same ticket domains"})
    confirm(view)

    assert has_element?(view, "#related-net-c0425")
    assert [%{id: "net-c0421"}] = Tracker.get_network("net-c0425").related
  end

  test "the History tab marks analyst and detection changes", %{conn: conn} do
    {:ok, _} = Tracker.rename_network("net-c0421", %{"name" => "Rally Ticket Bots"})
    {:ok, view, _html} = live(conn, "/networks/net-c0421?view=history")

    assert has_element?(view, "#history [data-actor=analyst]", "Analyst")
    assert has_element?(view, "#history [data-actor=system]", "System")
    assert has_element?(view, "#history", "Renamed Cluster #0421 → Rally Ticket Bots")
  end
end
