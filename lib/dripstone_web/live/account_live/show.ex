defmodule DripstoneWeb.AccountLive.Show do
  @moduledoc """
  One tracked account: profile and risk, the signals behind the score (largest
  first), the networks it belongs to (with "Add to network…"), the accounts it is
  linked to (strongest first) and its recent posts. Links to the platform open in a
  new tab and are only shown when the feed can build a safe link.
  """
  use DripstoneWeb, :live_view

  alias Dripstone.Feeds
  alias Dripstone.Tracker

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(account_id: id, picker: nil)
     |> stream_configure(:links, dom_id: &"linked-#{&1.account.id}")
     |> stream_configure(:posts, dom_id: &"post-#{&1.id}")
     |> load()}
  end

  defp load(socket) do
    case Tracker.get_account(socket.assigns.account_id) do
      nil ->
        assign(socket, account: nil, page_title: "Account not found")

      detail ->
        socket
        |> assign(
          account: detail.account,
          feed: Feeds.get(detail.account.feed_id),
          networks: detail.networks,
          link_count: length(detail.links),
          post_count: length(detail.posts),
          page_title: handle(detail.account)
        )
        |> stream(:links, detail.links, reset: true)
        |> stream(:posts, detail.posts, reset: true)
    end
  end

  @doc false
  # Called by DripstoneWeb.Nav for every tracker change.
  def handle_tracker_event({:network_updated, _id}, %{assigns: %{account: %{}}} = socket),
    do: load(socket)

  def handle_tracker_event(_message, socket), do: socket

  @impl true
  def handle_event("open_picker", _params, socket) do
    {:noreply, assign(socket, :picker, to_form(%{"network" => ""}, as: :picker))}
  end

  def handle_event("cancel_picker", _params, socket), do: {:noreply, assign(socket, :picker, nil)}

  def handle_event("add_to_network", %{"picker" => %{"network" => id}}, socket) when id != "" do
    case Tracker.add_members(id, [socket.assigns.account_id]) do
      {:ok, network} ->
        {:noreply,
         socket
         |> assign(:picker, nil)
         |> put_flash(:info, "Added to #{network.name}.")
         |> load()}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't add the account to that network.")}
    end
  end

  def handle_event("add_to_network", _params, socket), do: {:noreply, socket}

  @impl true
  def render(%{account: nil} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} nav={@nav} current_scope={@current_scope}>
      <.not_found title="Account not found" back={~p"/accounts"} back_label="Back to accounts" />
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} nav={@nav} current_scope={@current_scope}>
      <.page_header title={handle(@account)} back={~p"/accounts"} back_label="Accounts">
        <:subtitle>{@account.display_name}</:subtitle>
        <:meta>
          <.platform_badge feed_id={@account.feed_id} />
          <span :if={@account.created_at}>created {Calendar.strftime(
            @account.created_at,
            "%b %-d, %Y"
          )}</span>
          <span :if={@account.first_seen_at}>
            seen {Calendar.strftime(@account.first_seen_at, "%b %-d")} –
            <.relative_time :if={@account.last_seen_at} at={@account.last_seen_at} />
          </span>
          <a
            :if={profile_url(@feed, @account)}
            id="profile-link"
            href={profile_url(@feed, @account)}
            target="_blank"
            rel="noopener noreferrer"
            class="inline-flex items-center gap-1 font-medium text-accent hover:underline"
          >
            View on {@feed.name()} <.icon name="hero-arrow-top-right-on-square-mini" class="size-4" />
          </a>
        </:meta>
        <:actions>
          <.risk_badge score={@account.risk_score} class="px-2.5 py-1 text-sm" />
        </:actions>
      </.page_header>

      <div class="grid grid-cols-1 gap-4 lg:grid-cols-3 lg:gap-6">
        <div class="space-y-4 lg:col-span-2 lg:space-y-6">
          <.card id="signals" title={signals_title(@account.risk_score)}>
            <p :if={@account.signals == []} class="text-sm text-ink-muted">No signals recorded.</p>
            <ol class="space-y-3">
              <li :for={{signal, i} <- Enum.with_index(@account.signals)} id={"signal-#{i}"}>
                <div class="flex items-baseline justify-between gap-3">
                  <span class="text-sm font-medium text-ink">{signal.name}</span>
                  <span
                    :if={signal.contribution}
                    class="text-sm font-semibold tabular-nums text-ink"
                  >
                    +{signal.contribution}
                  </span>
                </div>
                <div
                  class="mt-1 h-1.5 overflow-hidden rounded-full bg-surface-raised"
                  aria-hidden="true"
                >
                  <div
                    class="h-full rounded-full bg-accent"
                    style={"width: #{bar_width(signal.contribution, @account.risk_score)}%"}
                  >
                  </div>
                </div>
                <p class="mt-1 text-xs text-ink-muted">{signal.explanation}</p>
              </li>
            </ol>
          </.card>

          <.card id="linked-accounts" title={"Linked accounts (#{@link_count})"} padded={false}>
            <ul
              id="links"
              phx-update="stream"
              class="max-h-[28rem] divide-y divide-line overflow-y-auto"
            >
              <li id="links-empty" class="hidden only:block">
                <.empty_state title="No linked accounts" icon="hero-link">
                  Detection hasn't linked this account to any other account.
                </.empty_state>
              </li>
              <li
                :for={{dom_id, link} <- @streams.links}
                id={dom_id}
                class="flex flex-wrap items-center gap-x-3 gap-y-1.5 px-4 py-2.5"
              >
                <.link
                  navigate={~p"/accounts/#{link.account.id}"}
                  class="min-w-0 flex-1 truncate font-mono text-sm text-ink hover:text-accent"
                >
                  {handle(link.account)}
                </.link>
                <span class="flex flex-wrap gap-1">
                  <span
                    :for={kind <- link.kinds}
                    data-kind={kind}
                    class="rounded bg-surface-raised px-1.5 py-0.5 text-xs text-ink-muted"
                  >
                    {link_kind_label(kind)}
                  </span>
                </span>
                <.strength_badge strength={link.strength} />
              </li>
            </ul>
          </.card>
        </div>

        <div class="space-y-4 lg:space-y-6">
          <.card id="account-networks" title="Networks" padded={false}>
            <:header_actions>
              <.button id="open-network-picker" phx-click="open_picker" size="sm" variant="ghost">
                <.icon name="hero-plus-mini" class="size-4" /> Add to network…
              </.button>
            </:header_actions>
            <ul class="divide-y divide-line">
              <li
                :if={@networks == []}
                id="no-networks"
                class="px-4 py-6 text-center text-sm text-ink-muted"
              >
                Not part of any network.
              </li>
              <li :for={network <- @networks} id={"account-network-#{network.id}"}>
                <.link
                  navigate={~p"/networks/#{network.id}"}
                  class="block px-4 py-3 hover:bg-surface-raised"
                >
                  <span class="font-medium text-ink">{network.name}</span>
                  <span class="mt-1 flex items-center gap-3 text-sm text-ink-muted">
                    <.status_pill status={network.status} />
                    <span class="tabular-nums">{network.confidence}%</span>
                  </span>
                </.link>
              </li>
            </ul>
          </.card>

          <.card id="recent-activity" title={"Recent activity (#{@post_count})"} padded={false}>
            <ul
              id="posts"
              phx-update="stream"
              class="max-h-[32rem] divide-y divide-line overflow-y-auto"
            >
              <li id="posts-empty" class="hidden only:block">
                <.empty_state title="No recorded posts" icon="hero-chat-bubble-left" />
              </li>
              <li :for={{dom_id, post} <- @streams.posts} id={dom_id} class="space-y-1 px-4 py-3">
                <div class="flex items-center justify-between gap-2 text-xs text-ink-faint">
                  <.relative_time at={post.posted_at} />
                  <a
                    :if={post_url(@feed, @account, post)}
                    href={post_url(@feed, @account, post)}
                    target="_blank"
                    rel="noopener noreferrer"
                    class="inline-flex items-center gap-1 text-accent hover:underline"
                  >
                    Open post <.icon name="hero-arrow-top-right-on-square-mini" class="size-3.5" />
                  </a>
                </div>
                <p :if={post.text} class="text-sm text-ink">{post.text}</p>
                <p :if={post.domain} class="font-mono text-xs text-ink-muted" data-domain>
                  {post.domain}
                </p>
              </li>
            </ul>
          </.card>
        </div>
      </div>

      <.modal :if={@picker} id="network-picker" show on_cancel={JS.push("cancel_picker")}>
        <:title>Add {handle(@account)} to a network</:title>
        <.form for={@picker} id="network-picker-form" phx-submit="add_to_network">
          <.input
            field={@picker[:network]}
            type="select"
            label="Network"
            prompt="Choose a network…"
            options={network_options(@networks)}
          />
        </.form>
        <:actions>
          <.button type="button" phx-click="cancel_picker">Cancel</.button>
          <.button
            id="confirm-add-to-network"
            type="submit"
            form="network-picker-form"
            variant="primary"
          >Add</.button>
        </:actions>
      </.modal>
    </Layouts.app>
    """
  end

  defp network_options(current) do
    current_ids = MapSet.new(current, & &1.id)
    for %{network: n} <- Tracker.list_networks(), n.id not in current_ids, do: {n.name, n.id}
  end

  defp signals_title(score) do
    case Tracker.risk_level(score) do
      :high -> "Why it scores high"
      :medium -> "Why it scores medium"
      :low -> "Why it scores low"
    end
  end

  defp bar_width(nil, _score), do: 0
  defp bar_width(_contribution, 0), do: 0
  defp bar_width(contribution, score), do: round(contribution / score * 100)

  defp profile_url(nil, _account), do: nil
  defp profile_url(feed, account), do: feed.profile_url(account)

  defp post_url(nil, _account, _post), do: nil

  defp post_url(feed, account, post),
    do:
      feed.post_url(%{handle: account.handle, instance: account.instance, post_id: post.post_id})

  defp handle(account) do
    case Feeds.get(account.feed_id) do
      nil -> account.handle
      feed -> feed.format_handle(account)
    end
  end
end
