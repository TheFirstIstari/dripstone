defmodule DripstoneWeb.NetworkLive.GraphViewTest do
  # Uses the app-wide tracker store, so it must not run alongside other tests.
  use DripstoneWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  alias Dripstone.Tracker
  alias Dripstone.Tracker.SampleStore

  setup do
    previous = SampleStore.get_state()
    on_exit(fn -> SampleStore.put_state(previous) end)
    Tracker.reset_sample_data!()
    :ok
  end

  defp count(view, selector),
    do: view |> render() |> LazyHTML.from_document() |> LazyHTML.query(selector) |> Enum.count()

  test "the Graph view is kept in the URL", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/networks/net-c0421")

    view |> element("#tab-graph") |> render_click()
    assert_patch(view, "/networks/net-c0421?view=graph")
    assert has_element?(view, "#network-graph")

    {:ok, view, _html} = live(conn, "/networks/net-c0421?view=graph")
    assert has_element?(view, "#network-graph")
    assert has_element?(view, "#tab-graph[aria-current=page]")
    refute has_element?(view, "#summary-view")
  end

  test "edges are drawn per link kind, with a legend for every kind", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/networks/net-c0421?view=graph")
    graph = Tracker.network_graph("net-c0421")

    assert count(view, "#network-graph line") == length(graph.edges)
    assert count(view, "#network-graph g[id^=network-graph-node-]") == length(graph.nodes)

    for kind <- ~w(shared_link near_duplicate synced_posting created_together) do
      assert has_element?(view, "#toggle-#{kind}[aria-pressed=true]")
    end
  end

  test "hiding a link kind removes its lines and dims nodes left unlinked", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/networks/net-c0421?view=graph")
    graph = Tracker.network_graph("net-c0421")
    shared = Enum.count(graph.edges, &(&1.kind == :shared_link))
    assert shared > 0

    view |> element("#toggle-shared_link") |> render_click()

    assert has_element?(view, "#toggle-shared_link[aria-pressed=false]")
    assert count(view, "#network-graph line[data-kind=shared_link]") == 0
    assert count(view, "#network-graph line") == length(graph.edges) - shared

    for kind <- ~w(shared_link near_duplicate synced_posting created_together) do
      view |> element("#toggle-#{kind}") |> render_click()
    end

    view |> element("#toggle-shared_link") |> render_click()
    assert count(view, "#network-graph line") == 0
    assert count(view, "#network-graph circle.opacity-30") == length(graph.nodes)
  end

  test "selecting a node highlights it and shows its account panel", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/networks/net-c0421?view=graph")
    [node | _] = Tracker.network_graph("net-c0421").nodes

    view |> element("#network-graph-node-#{node.id}") |> render_click()

    assert has_element?(view, "#network-graph-node-#{node.id}[data-selected]")
    assert has_element?(view, ~s(#node-account-link[href="/accounts/#{node.id}"]))
    assert has_element?(view, "#node-panel [data-risk]")

    view |> element("#network-graph-node-#{node.id}") |> render_click()
    refute has_element?(view, "#node-account-link")
  end

  test "a 400-member network draws 150 members and says 250 are not shown", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/networks/net-lumen?view=graph")

    assert count(view, "#network-graph g[id^=network-graph-node-]") == 150
    assert has_element?(view, "#graph-omitted", "250 members are not shown")
  end

  test "small networks are drawn whole with no notice", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/networks/net-c0422?view=graph")
    refute has_element?(view, "#graph-omitted")
  end
end
