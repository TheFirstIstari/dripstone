defmodule DripstoneWeb.NetworkLive.Index do
  @moduledoc """
  Suspected bot farms, most recently active first, filtered by status, platform and
  tag (kept in the URL). Networks retired by a merge are not listed. Refreshes live.
  """
  use DripstoneWeb, :live_view

  alias Dripstone.Feeds
  alias Dripstone.Tracker

  @statuses %{"suspected" => :suspected, "confirmed" => :confirmed, "dismissed" => :dismissed}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Networks")
     |> stream_configure(:networks, dom_id: &"network-row-#{&1.network.id}")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tags = Tracker.list_tags()

    filters = %{
      status: Map.get(@statuses, params["status"]),
      platform: if(Feeds.get(params["platform"]), do: params["platform"]),
      tag: if(params["tag"] in tags, do: params["tag"])
    }

    {:noreply,
     socket
     |> assign(filters: filters, tags: tags)
     |> assign(:form, to_form(form_params(filters), as: :filters))
     |> load()}
  end

  defp load(socket) do
    entries = entries(socket)

    socket
    |> assign(:count, length(entries))
    |> assign(:tags, tags(entries, socket.assigns.filters[:tag]))
    |> stream(:networks, entries, reset: true)
  end

  defp entries(socket),
    do:
      socket.assigns.filters
      |> Map.reject(fn {_k, v} -> is_nil(v) end)
      |> Tracker.list_networks()

  # Tags ride on the already-loaded entries, so broadcasts never pay for a
  # second `list_tags` scan; the URL-selected tag is kept even with no match.
  defp tags(entries, selected) do
    tags = entries |> Enum.flat_map(& &1.network.tags) |> Enum.uniq() |> Enum.sort()
    if selected in tags or is_nil(selected), do: tags, else: [selected | tags] |> Enum.sort()
  end

  @impl true
  def handle_event("filter", %{"filters" => params}, socket) do
    query =
      params
      |> Map.take(["status", "platform", "tag"])
      |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)

    {:noreply, push_patch(socket, to: ~p"/networks?#{query}")}
  end

  @doc false
  # Called by DripstoneWeb.Nav for every tracker change. One `list_networks`
  # scan refreshes both rows and tags; other messages need no tag refresh.
  def handle_tracker_event({:network_updated, _id}, socket), do: load(socket)

  def handle_tracker_event(_message, socket), do: socket

  defp form_params(filters) do
    %{
      "status" => (filters.status && Atom.to_string(filters.status)) || "",
      "platform" => filters.platform || "",
      "tag" => filters.tag || ""
    }
  end

  defp filtered?(filters), do: Enum.any?(filters, fn {_k, v} -> v end)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} nav={@nav} current_scope={@current_scope}>
      <.page_header title="Networks">
        <:subtitle>Suspected bot farms, and the evidence linking their accounts.</:subtitle>
        <:actions>
          <span id="network-count" class="text-sm tabular-nums text-ink-muted">
            {@count} {if @count == 1, do: "network", else: "networks"}
          </span>
        </:actions>
      </.page_header>

      <.card padded={false}>
        <.filter_bar id="network-filters" for={@form} clear={filtered?(@filters) && ~p"/networks"}>
          <div class="w-[calc(50%-0.375rem)] sm:w-40">
            <.input
              field={@form[:status]}
              type="select"
              label="Status"
              prompt="Any"
              options={[
                {"Suspected", "suspected"},
                {"Confirmed", "confirmed"},
                {"Dismissed", "dismissed"}
              ]}
            />
          </div>
          <div class="w-[calc(50%-0.375rem)] sm:w-40">
            <.input
              field={@form[:platform]}
              type="select"
              label="Platform"
              prompt="Any"
              options={Enum.map(Feeds.all(), &{&1.name(), &1.id()})}
            />
          </div>
          <div class="w-[calc(50%-0.375rem)] sm:w-48">
            <.input
              field={@form[:tag]}
              type="select"
              label="Tag"
              prompt="Any"
              options={Enum.map(@tags, &{"##{&1}", &1})}
            />
          </div>
        </.filter_bar>

        <ul id="networks" phx-update="stream" class="divide-y divide-line">
          <li id="networks-empty" class="hidden only:block">
            <.empty_state
              :if={filtered?(@filters)}
              title="No networks match these filters"
              icon="hero-funnel"
            >
              <:actions><.button patch={~p"/networks"} size="sm">Clear filters</.button></:actions>
            </.empty_state>
            <.empty_state :if={!filtered?(@filters)} title="No networks yet" icon="hero-share">
              Networks appear here as detection finds them.
            </.empty_state>
          </li>
          <li :for={{dom_id, entry} <- @streams.networks} id={dom_id}>
            <.link
              navigate={~p"/networks/#{entry.network.id}"}
              class="group flex flex-col gap-2 px-4 py-3.5 transition-colors hover:bg-surface-raised lg:flex-row lg:items-center lg:gap-6"
            >
              <div class="min-w-0 flex-1">
                <p class="flex flex-wrap items-center gap-2">
                  <span class="font-medium text-ink group-hover:text-accent-strong">{entry.network.name}</span>
                  <.tag_chip :for={tag <- entry.network.tags} tag={tag} />
                </p>
                <p class="mt-1 flex flex-wrap items-center gap-1.5 text-xs text-ink-muted">
                  <.platform_badge :for={feed <- entry.network.platforms} feed_id={feed} />
                  <span :if={entry.network.main_domain} class="font-mono">{entry.network.main_domain}</span>
                </p>
              </div>
              <div class="flex flex-wrap items-center gap-x-5 gap-y-1 text-sm text-ink-muted lg:justify-end">
                <.status_pill status={entry.network.status} class="w-24" />
                <span class="w-14 tabular-nums">{entry.network.confidence}%</span>
                <span class="w-24 tabular-nums">{length(entry.network.member_ids)} accounts</span>
                <span
                  data-open-alerts={entry.open_alerts}
                  class={[
                    "w-24 tabular-nums",
                    entry.open_alerts > 0 && "font-medium text-sev-high"
                  ]}
                >
                  {entry.open_alerts} open {if entry.open_alerts == 1, do: "alert", else: "alerts"}
                </span>
                <span class="w-36 text-xs text-ink-faint">
                  <span :if={entry.network.first_activity_at}>
                    {Calendar.strftime(entry.network.first_activity_at, "%b %-d")} –
                  </span>
                  <.relative_time :if={entry.last_activity_at} at={entry.last_activity_at} />
                </span>
              </div>
            </.link>
          </li>
        </ul>
      </.card>
    </Layouts.app>
    """
  end
end
