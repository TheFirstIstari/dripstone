defmodule DripstoneWeb.FeedLive.Index do
  @moduledoc """
  Health of every registered platform feed: status, last item, items in the last
  24 hours, tracked accounts and the most recent error. Read-only: feeds are added in
  code (see `openspec/changes/add-tracker-ui/docs/FEEDS.md`).
  """
  use DripstoneWeb, :live_view

  alias Dripstone.Tracker

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Feeds")
     |> stream_configure(:feeds, dom_id: &"feed-#{&1.feed.id()}")
     |> load()}
  end

  defp load(socket), do: stream(socket, :feeds, Tracker.feed_health(), reset: true)

  @doc false
  # Called by DripstoneWeb.Nav for every tracker change.
  def handle_tracker_event(_message, socket), do: load(socket)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} nav={@nav} current_scope={@current_scope}>
      <.page_header title="Feeds">
        <:subtitle>Health of each platform feed.</:subtitle>
      </.page_header>

      <p
        id="feeds-how-to-add"
        class="mb-4 flex items-start gap-2 rounded-card border border-line bg-surface-raised px-4 py-3 text-sm text-ink-muted"
      >
        <.icon name="hero-code-bracket" class="mt-0.5 size-4 shrink-0 text-ink-faint" />
        <span>
          Feeds are added in code, not here. See
          <code class="font-mono text-ink">openspec/changes/add-tracker-ui/docs/FEEDS.md</code>
          in the repository: one module plus one line of config.
        </span>
      </p>

      <.card padded={false}>
        <.table id="feeds" rows={@streams.feeds}>
          <:col :let={{_id, entry}} label="Platform">
            <span class="font-medium text-ink">{entry.feed.name()}</span>
          </:col>
          <:col :let={{_id, entry}} label="Status">
            <.status_pill status={entry.health.status} />
          </:col>
          <:col :let={{_id, entry}} label="Last item" class="whitespace-nowrap text-ink-muted">
            <.relative_time :if={entry.health.last_item_at} at={entry.health.last_item_at} />
            <span :if={!entry.health.last_item_at} class="text-ink-faint">—</span>
          </:col>
          <:col :let={{_id, entry}} label="Items (24h)" class="tabular-nums text-ink">
            {format_number(entry.health.items_24h)}
          </:col>
          <:col :let={{_id, entry}} label="Accounts" class="tabular-nums text-ink">
            {format_number(entry.accounts)}
          </:col>
          <:col :let={{_id, entry}} label="Last error">
            <span :if={entry.health.last_error} class="text-sev-high" data-last-error>
              {entry.health.last_error}
              <span :if={entry.health.last_error_at} class="text-xs text-ink-faint">
                · <.relative_time at={entry.health.last_error_at} />
              </span>
            </span>
            <span :if={!entry.health.last_error} class="text-ink-faint">—</span>
          </:col>
        </.table>
      </.card>
    </Layouts.app>
    """
  end
end
