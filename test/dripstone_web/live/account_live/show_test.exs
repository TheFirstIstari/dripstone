defmodule DripstoneWeb.AccountLive.ShowTest do
  # Changes the app-wide tracker store, so it must not run alongside other tests.
  use DripstoneWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  alias Dripstone.Tracker
  alias Dripstone.Tracker.SampleStore

  setup do
    Ecto.Adapters.SQL.Sandbox.allow(
      Dripstone.Repo,
      self(),
      Process.whereis(Dripstone.Tracker.SampleStore)
    )

    previous = SampleStore.get_state()
    on_exit(fn -> SampleStore.put_state(previous) end)
    Tracker.reset_sample_data!()
    %{state: SampleStore.get_state()}
  end

  defp sunrise_member, do: hd(Tracker.get_network("net-sunrise").members).account

  defp ids(view, selector),
    do:
      view
      |> render()
      |> LazyHTML.from_document()
      |> LazyHTML.query(selector)
      |> LazyHTML.attribute("id")

  test "the header shows handle, name, platform, dates, risk and an external profile link", %{
    conn: conn
  } do
    account = sunrise_member()
    feed = Dripstone.Feeds.get(account.feed_id)
    {:ok, view, html} = live(conn, "/accounts/#{account.id}")

    assert html =~ "#{feed.format_handle(account)} · Dripstone"
    assert has_element?(view, "#page-title", feed.format_handle(account))
    assert has_element?(view, "header", account.display_name)
    assert has_element?(view, "header [data-risk]", "#{account.risk_score}")

    assert has_element?(
             view,
             ~s(#profile-link[href="#{feed.profile_url(account)}"][target=_blank][rel="noopener noreferrer"])
           )
  end

  test "a Mastodon account shows @user@instance and links to its instance", %{
    conn: conn,
    state: state
  } do
    account = state.accounts |> Map.values() |> Enum.find(&(&1.feed_id == "mastodon"))
    {:ok, view, _html} = live(conn, "/accounts/#{account.id}")

    assert has_element?(view, "#page-title", "@#{account.handle}@#{account.instance}")

    assert has_element?(
             view,
             ~s(#profile-link[href="https://#{account.instance}/@#{account.handle}"])
           )
  end

  test "signals are listed largest contribution first with explanations", %{conn: conn} do
    account = sunrise_member()
    {:ok, view, _html} = live(conn, "/accounts/#{account.id}")

    [first | _] = account.signals
    assert has_element?(view, "#signal-0", first.name)
    assert has_element?(view, "#signal-0", "+#{first.contribution}")
    assert has_element?(view, "#signal-0", first.explanation)
    assert has_element?(view, "#signals", "Why it scores high")
  end

  test "linked accounts show link types and strength, strongest first", %{conn: conn} do
    account = sunrise_member()
    %{links: [top | _] = links} = Tracker.get_account(account.id)
    {:ok, view, _html} = live(conn, "/accounts/#{account.id}")

    assert ids(view, "#links > li[id^=linked-]") == Enum.map(links, &"linked-#{&1.account.id}")
    assert has_element?(view, "#linked-#{top.account.id} [data-strength=#{top.strength}]")
    assert has_element?(view, "#linked-#{top.account.id} [data-kind=#{hd(top.kinds)}]")
    assert has_element?(view, ~s(#linked-#{top.account.id} a[href="/accounts/#{top.account.id}"]))
  end

  test "networks link to their pages", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/accounts/#{sunrise_member().id}")

    assert has_element?(
             view,
             ~s(#account-network-net-sunrise a[href="/networks/net-sunrise"]),
             "Discount Spam Ring"
           )
  end

  test "recent posts show their promoted domain and link to the original", %{conn: conn} do
    account = sunrise_member()
    %{posts: [post | _]} = Tracker.get_account(account.id)
    {:ok, view, _html} = live(conn, "/accounts/#{account.id}")

    assert has_element?(view, "#post-#{post.id}", post.text)
    assert has_element?(view, "#post-#{post.id} [data-domain]", post.domain)
    assert has_element?(view, ~s(#post-#{post.id} a[target=_blank][rel="noopener noreferrer"]))
  end

  test "empty states: no links, no networks, no posts", %{conn: conn, state: state} do
    loner =
      state.accounts
      |> Map.values()
      |> Enum.find(fn a ->
        Map.get(state.posts, a.id, []) == [] and Tracker.get_account(a.id).links == [] and
          Tracker.get_account(a.id).networks == []
      end)

    {:ok, view, _html} = live(conn, "/accounts/#{loner.id}")

    assert has_element?(view, "#links-empty", "No linked accounts")
    assert has_element?(view, "#no-networks", "Not part of any network")
    assert has_element?(view, "#posts-empty", "No recorded posts")
  end

  test "the account can be added to a network from its page", %{conn: conn, state: state} do
    loner =
      state.accounts |> Map.values() |> Enum.find(&(Tracker.get_account(&1.id).networks == []))

    {:ok, view, _html} = live(conn, "/accounts/#{loner.id}")

    view |> element("#open-network-picker") |> render_click()
    assert has_element?(view, "#network-picker-form option[value=net-c0421]")

    view |> form("#network-picker-form", picker: %{network: "net-c0421"}) |> render_submit()

    assert has_element?(view, ~s(#account-network-net-c0421 a[href="/networks/net-c0421"]))
    refute has_element?(view, "#network-picker")
    assert loner.id in Tracker.get_network("net-c0421").network.member_ids
  end

  test "networks the account already belongs to are not offered again", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/accounts/#{sunrise_member().id}")

    view |> element("#open-network-picker") |> render_click()
    refute has_element?(view, "#network-picker-form option[value=net-sunrise]")
  end
end
