defmodule DripstoneWeb.OverviewLive do
  @moduledoc """
  The root screen. Logged-in analysts get the overview dashboard: headline counts,
  the 30-day alert trend, newest open alerts, recently active networks and feed
  health (refreshes live on tracker changes). Logged-out visitors get a public
  landing page, so deploy checks see a 200.
  """
  use DripstoneWeb, :live_view

  alias Dripstone.Tracker

  @impl true
  def mount(
        _params,
        _session,
        %{assigns: %{current_scope: %{user: %Dripstone.Accounts.User{}}}} = socket
      ) do
    {:ok,
     socket
     |> assign(:page_title, "Overview")
     |> stream_configure(:alerts, dom_id: &"overview-alert-#{&1.alert.id}")
     |> stream_configure(:networks, dom_id: &"overview-network-#{&1.network.id}")
     |> stream_configure(:feeds, dom_id: &"feed-strip-#{&1.feed.id()}")
     |> load()}
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Dripstone")}
  end

  @doc false
  # Overview aggregates open alerts, networks and feeds; only alert and network
  # events can change it. Account findings without an alert leave it alone (#248).
  def handle_tracker_event({event, _}, socket)
      when event in [:alert_raised, :alert_updated, :network_updated],
      do: load(socket)

  def handle_tracker_event(_message, socket), do: socket

  defp load(socket) do
    overview = Tracker.overview()

    socket
    |> assign(
      :counts,
      Map.take(overview, [:open_alerts, :open_high_alerts, :suspected_networks, :tracked_accounts])
    )
    |> assign(:trend, overview.trend)
    |> assign(:trend_total, overview.trend_total)
    |> stream(:alerts, overview.newest_open_alerts, reset: true)
    |> stream(:networks, overview.recent_networks, reset: true)
    |> stream(:feeds, overview.feeds, reset: true)
  end

  # Full class names so Tailwind can find them in the source.
  defp feed_border(:down), do: "border-status-down/50"
  defp feed_border(:degraded), do: "border-status-degraded/50"
  defp feed_border(_status), do: "border-line"

  @impl true
  # Logged-out visitors see a public landing page (200 for deploy checks);
  # analysts see the dashboard below.
  def render(%{current_scope: %{user: %Dripstone.Accounts.User{}}} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} nav={@nav} current_scope={@current_scope}>
      <.page_header title="Overview">
        <:subtitle>What needs attention, and what Dripstone is tracking.</:subtitle>
      </.page_header>

      <div id="headline-counts" class="grid grid-cols-2 gap-3 lg:grid-cols-4 lg:gap-4">
        <.stat_tile
          id="count-open-alerts"
          label="Open alerts"
          value={@counts.open_alerts}
          navigate={~p"/alerts"}
        />
        <.stat_tile
          id="count-high-alerts"
          label="Open high severity"
          value={@counts.open_high_alerts}
          navigate={~p"/alerts?#{[status: "open", severity: "high"]}"}
          tone={if @counts.open_high_alerts > 0, do: :alert, else: :neutral}
        />
        <.stat_tile
          id="count-suspected-networks"
          label="Suspected networks"
          value={@counts.suspected_networks}
          navigate={~p"/networks?#{[status: "suspected"]}"}
        />
        <.stat_tile
          id="count-tracked-accounts"
          label="Tracked accounts"
          value={@counts.tracked_accounts}
          navigate={~p"/accounts"}
        />
      </div>

      <div class="mt-4 grid grid-cols-1 gap-4 lg:mt-6 lg:grid-cols-3 lg:gap-6">
        <div class="space-y-4 lg:col-span-2 lg:space-y-6">
          <.card id="alert-trend" title="Alerts raised · last 30 days">
            <:header_actions>
              <span class="text-2xl font-semibold tabular-nums text-ink">{@trend_total}</span>
            </:header_actions>
            <.sparkline
              id="alert-trend-chart"
              points={@trend}
              summary={"#{@trend_total} #{if @trend_total == 1, do: "alert", else: "alerts"} raised in the last 30 days."}
              empty_title="No alerts raised in the last 30 days"
            />
          </.card>

          <.card id="recent-networks" title="Recently active networks" padded={false}>
            <:header_actions>
              <.link
                navigate={~p"/networks"}
                id="see-all-networks"
                class="text-accent hover:underline"
              >
                See all
              </.link>
            </:header_actions>
            <ul id="recent-network-list" phx-update="stream" class="divide-y divide-line">
              <li id="recent-networks-empty" class="hidden only:block">
                <.empty_state title="No networks yet" icon="hero-share">
                  Networks appear here as detection finds them.
                </.empty_state>
              </li>
              <li :for={{dom_id, entry} <- @streams.networks} id={dom_id}>
                <.link
                  navigate={~p"/networks/#{entry.network.id}"}
                  class="flex flex-wrap items-center gap-x-4 gap-y-1 px-4 py-3 transition-colors hover:bg-surface-raised"
                >
                  <span class="w-full min-w-0 truncate font-medium text-ink sm:w-auto sm:flex-1">{entry.network.name}</span>
                  <.status_pill status={entry.network.status} />
                  <span class="w-12 text-right text-sm tabular-nums text-ink-muted">
                    {entry.network.confidence}%
                  </span>
                  <span class="w-24 text-right text-sm tabular-nums text-ink-muted">
                    {length(entry.network.member_ids)} accounts
                  </span>
                </.link>
              </li>
            </ul>
          </.card>
        </div>

        <.card id="newest-alerts" title="Newest open alerts" padded={false} class="self-start">
          <ul id="newest-alert-list" phx-update="stream" class="divide-y divide-line">
            <li id="newest-alerts-empty" class="hidden only:block">
              <.empty_state
                id="queue-clear"
                title="Nothing waiting for review"
                icon="hero-check-circle"
              >
                New alerts will show up here as detection raises them.
              </.empty_state>
            </li>
            <li :for={{dom_id, entry} <- @streams.alerts} id={dom_id}>
              <.link
                navigate={~p"/alerts/#{entry.alert.id}"}
                class="block space-y-1.5 px-4 py-3 transition-colors hover:bg-surface-raised"
              >
                <div class="flex items-center justify-between gap-2">
                  <.severity_badge severity={entry.alert.severity} />
                  <.relative_time at={entry.alert.raised_at} class="text-xs text-ink-faint" />
                </div>
                <p class="line-clamp-2 text-sm font-medium text-ink">{entry.alert.title}</p>
                <p class="truncate text-xs text-ink-muted">{entry.network.name}</p>
              </.link>
            </li>
          </ul>
          <div class="border-t border-line px-4 py-3">
            <.link
              navigate={~p"/alerts"}
              id="open-inbox"
              class="inline-flex items-center gap-1 text-sm font-medium text-accent hover:underline"
            >
              Open inbox <.icon name="hero-arrow-right-mini" class="size-4" />
            </.link>
          </div>
        </.card>
      </div>

      <section id="feed-strip" class="mt-4 lg:mt-6" aria-label="Feed health">
        <div class="flex flex-wrap items-center gap-2">
          <.link
            navigate={~p"/feeds"}
            class="mr-1 text-xs font-medium uppercase tracking-wide text-ink-faint hover:text-ink"
          >
            Feeds
          </.link>
          <div id="feed-strip-list" phx-update="stream" class="contents">
            <.link
              :for={{dom_id, entry} <- @streams.feeds}
              id={dom_id}
              navigate={~p"/feeds"}
              data-feed-status={entry.health.status}
              class={[
                "inline-flex items-center gap-2 rounded-full border bg-surface px-3 py-1 text-sm shadow-card transition-colors hover:border-line-strong",
                feed_border(entry.health.status)
              ]}
            >
              <span class="font-medium text-ink">{entry.feed.name()}</span>
              <.status_pill status={entry.health.status} class="text-ink-muted" />
            </.link>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <main id="landing" class="mx-auto max-w-2xl px-6 py-24 text-center">
      <h1 class="text-3xl font-semibold tracking-tight text-ink">Dripstone</h1>
      <p class="mt-3 text-ink-muted">Coordinated-activity detection for analysts.</p>
      <.link
        navigate={~p"/users/log-in"}
        id="landing-log-in"
        class="mt-8 inline-block rounded-lg bg-accent px-4 py-2 font-medium text-accent-ink hover:bg-accent-strong"
      >
        Log in
      </.link>
    </main>
    """
  end
end
