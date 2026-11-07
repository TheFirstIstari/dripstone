defmodule DripstoneWeb.AccountLive.IndexTest do
  # Reads the app-wide tracker store, so it must not run alongside tests that change it.
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

  defp row_ids(view),
    do:
      view
      |> render()
      |> LazyHTML.from_document()
      |> LazyHTML.query("#accounts > tr[id^=account-row]")
      |> LazyHTML.attribute("id")

  defp expected(params),
    do: Enum.map(Tracker.list_accounts(params).entries, &"account-row-#{&1.account.id}")

  test "default: highest risk first, 50 rows, with the total", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/accounts")

    assert row_ids(view) == expected(%{})
    assert length(row_ids(view)) == 50
    assert has_element?(view, "#account-total", "1,300 accounts")
    assert has_element?(view, "#account-pager", "Page 1 of 26")
  end

  test "rows show handle, name, platform, risk level and score, network and last seen", %{
    conn: conn
  } do
    [%{account: account, networks: [network | _]} | _] = Tracker.list_accounts(%{}).entries
    {:ok, view, _html} = live(conn, "/accounts")
    row = "#account-row-#{account.id}"

    assert has_element?(view, ~s(#{row} a[href="/accounts/#{account.id}"]))
    assert has_element?(view, row, account.display_name)
    assert has_element?(view, "#{row} [data-risk]", "#{account.risk_score}")
    assert has_element?(view, row, network.name)
    assert has_element?(view, "#{row} time")
  end

  test "page 2 shows rows 51-100 and is in the URL", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/accounts")

    view |> element("#account-pager-next") |> render_click()
    assert_patch(view, "/accounts?page=2")

    assert row_ids(view) == expected(%{page: 2})
    assert has_element?(view, "#account-pager", "Page 2 of 26")
    assert has_element?(view, "#account-pager-prev")
  end

  test "filters combine with AND and go into the URL", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/accounts")

    view
    |> form("#account-filters", filters: %{platform: "reddit", risk: "high", sort: "risk"})
    |> render_change()

    assert_patch(view, "/accounts?platform=reddit&risk=high")
    assert row_ids(view) == expected(%{platform: "reddit", risk: :high})

    for %{account: a} <- Tracker.list_accounts(%{platform: "reddit", risk: :high}).entries do
      assert a.feed_id == "reddit" and a.risk_score >= 70
    end
  end

  test "filters and sort are restored from the URL", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/accounts?risk=high&sort=last_seen")

    assert row_ids(view) == expected(%{risk: :high, sort: :last_seen})

    assert has_element?(
             view,
             "#account-filters select[name='filters[sort]'] option[selected][value=last_seen]"
           )

    assert has_element?(
             view,
             "#account-filters select[name='filters[risk]'] option[selected][value=high]"
           )
  end

  test "search and network membership filters", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/accounts?network=net-sunrise")
    assert row_ids(view) == expected(%{network: "net-sunrise"})

    {:ok, view, _html} = live(conn, "/accounts?network=none")
    assert row_ids(view) == expected(%{network: "none"})

    [%{account: target} | _] = Tracker.list_accounts(%{}).entries
    {:ok, view, _html} = live(conn, "/accounts?q=#{URI.encode_www_form(target.handle)}")
    assert "account-row-#{target.id}" in row_ids(view)
  end

  test "unknown params are ignored and the page still loads", %{conn: conn} do
    {:ok, view, _html} =
      live(conn, "/accounts?platform=myspace&risk=extreme&network=net-nope&sort=random&page=abc")

    assert row_ids(view) == expected(%{})
  end

  test "no matches show an empty state with a way to clear filters", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/accounts?q=zzz-no-such-account")

    assert row_ids(view) == []
    assert has_element?(view, "#accounts-empty-state", "No accounts match these filters")
    assert has_element?(view, ~s(#account-filters-clear[href="/accounts"]))
    assert has_element?(view, "#account-total", "0 accounts")
  end

  test "the top bar search lands here filtered", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/accounts?q=swift")
    assert has_element?(view, "#account-filters input[name='filters[q]'][value=swift]")
    assert row_ids(view) == expected(%{q: "swift"})
  end
end
