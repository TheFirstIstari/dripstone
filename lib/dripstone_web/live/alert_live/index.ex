defmodule DripstoneWeb.AlertLive.Index do
  @moduledoc """
  The alert inbox: alerts newest first, Open by default, filtered by status,
  severity, trigger and platform (kept in the URL). New alerts that match the
  filters arrive live at the top, highlighted until the filters next change.
  """
  use DripstoneWeb, :live_view

  alias Dripstone.Alerts
  alias Dripstone.Tracker
  alias DripstoneWeb.AlertLive.Filters

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Alerts", new_ids: MapSet.new())
     |> stream_configure(:alerts, dom_id: &"alert-row-#{&1.alert.id}")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = Filters.parse(params)

    {:noreply,
     socket
     |> assign(filters: filters, new_ids: MapSet.new())
     |> assign(:form, to_form(Filters.form_params(filters), as: :filters))
     |> load()}
  end

  defp load(socket) do
    entries = Tracker.list_alerts(Filters.to_tracker(socket.assigns.filters))

    socket
    |> assign(:count, length(entries))
    |> stream(:alerts, entries, reset: true)
  end

  @impl true
  def handle_event("filter", %{"filters" => params}, socket) do
    filters = Filters.parse(params)
    {:noreply, push_patch(socket, to: ~p"/alerts?#{Filters.to_query(filters)}")}
  end

  @doc false
  # Called by DripstoneWeb.Nav for every tracker change.
  def handle_tracker_event({event, %{id: id}}, socket)
      when event in [:alert_raised, :alert_updated] do
    entries = Tracker.list_alerts(Filters.to_tracker(socket.assigns.filters))
    socket = assign(socket, :count, length(entries))

    case Enum.find(entries, &(&1.alert.id == id)) do
      nil ->
        stream_delete_by_dom_id(socket, :alerts, "alert-row-#{id}")

      entry when event == :alert_raised ->
        socket
        |> update(:new_ids, &MapSet.put(&1, id))
        |> stream_insert(:alerts, entry, at: 0)

      entry ->
        stream_insert(socket, :alerts, entry)
    end
  end

  def handle_tracker_event(_message, socket), do: socket

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} nav={@nav} current_scope={@current_scope}>
      <.page_header title="Alerts">
        <:subtitle>
          Alerts raised by detection. Review the evidence, then confirm or dismiss.
        </:subtitle>
        <:actions>
          <span id="alert-count" class="text-sm tabular-nums text-ink-muted">
            {@count} {status_word(@filters.status, @count)}
          </span>
        </:actions>
      </.page_header>

      <.card padded={false}>
        <.filter_bar id="alert-filters" for={@form} clear={Filters.filtered?(@filters) && ~p"/alerts"}>
          <div class="w-[calc(50%-0.375rem)] sm:w-36">
            <.input
              field={@form[:status]}
              type="select"
              label="Status"
              options={Filters.status_options()}
            />
          </div>
          <div class="w-[calc(50%-0.375rem)] sm:w-36">
            <.input
              field={@form[:severity]}
              type="select"
              label="Severity"
              prompt="Any"
              options={Filters.severity_options()}
            />
          </div>
          <div class="w-[calc(50%-0.375rem)] sm:w-48">
            <.input
              field={@form[:trigger]}
              type="select"
              label="Trigger"
              prompt="Any"
              options={Filters.trigger_options()}
            />
          </div>
          <div class="w-[calc(50%-0.375rem)] sm:w-40">
            <.input
              field={@form[:platform]}
              type="select"
              label="Platform"
              prompt="Any"
              options={Filters.platform_options()}
            />
          </div>
        </.filter_bar>

        <ul id="alerts" phx-update="stream" class="divide-y divide-line">
          <li id="alerts-empty" class="hidden only:block">
            <.empty_state
              :if={Filters.filtered?(@filters)}
              title="No alerts match these filters"
              icon="hero-funnel"
            >
              <:actions><.button patch={~p"/alerts"} size="sm">Clear filters</.button></:actions>
            </.empty_state>
            <.empty_state
              :if={!Filters.filtered?(@filters)}
              title="Nothing waiting for review"
              icon="hero-check-circle"
            >
              New alerts appear here as detection raises them.
            </.empty_state>
          </li>
          <li
            :for={{dom_id, entry} <- @streams.alerts}
            id={dom_id}
            data-new={MapSet.member?(@new_ids, entry.alert.id)}
          >
            <.link
              navigate={~p"/alerts/#{entry.alert.id}?#{Filters.to_query(@filters)}"}
              class={[
                "group flex flex-col gap-2 px-4 py-3.5 transition-colors hover:bg-surface-raised sm:flex-row sm:items-start sm:gap-4",
                MapSet.member?(@new_ids, entry.alert.id) && "bg-accent-soft/60"
              ]}
            >
              <div class="flex shrink-0 items-center gap-2 sm:w-32">
                <span
                  :if={MapSet.member?(@new_ids, entry.alert.id)}
                  class="rounded bg-accent px-1.5 py-0.5 text-[10px] font-bold uppercase tracking-wider text-accent-ink"
                >
                  New
                </span>
                <.severity_badge severity={entry.alert.severity} />
              </div>
              <div class="min-w-0 flex-1">
                <p class="font-medium text-ink group-hover:text-accent-strong">{entry.alert.title}</p>
                <p class="mt-1 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-ink-muted">
                  <span class="font-medium text-ink-muted">{entry.network.name}</span>
                  <.platform_badge :for={feed <- entry.network.platforms} feed_id={feed} />
                  <span
                    :if={entry.alert.previously_dismissed_alert_id}
                    class="inline-flex items-center gap-1 text-status-suspected"
                    data-previously-dismissed
                  >
                    <.icon name="hero-arrow-uturn-left-mini" class="size-3.5" /> Previously dismissed
                  </span>
                  <.status_pill :if={entry.alert.status != :open} status={entry.alert.status} />
                </p>
              </div>
              <div class="flex shrink-0 items-center justify-between gap-4 text-xs text-ink-muted sm:flex-col sm:items-end sm:gap-1">
                <span>{trigger_name(entry.alert.trigger_id)}</span>
                <.relative_time at={entry.alert.raised_at} class="text-ink-faint" />
              </div>
            </.link>
          </li>
        </ul>
      </.card>
    </Layouts.app>
    """
  end

  defp trigger_name(id) do
    case Alerts.get_trigger_type(id) do
      nil -> id
      type -> type.name
    end
  end

  defp status_word(:all, 1), do: "alert"
  defp status_word(:all, _n), do: "alerts"
  defp status_word(status, _n), do: Atom.to_string(status)
end
