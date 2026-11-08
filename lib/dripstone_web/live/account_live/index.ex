defmodule DripstoneWeb.AccountLive.Index do
  @moduledoc """
  Tracked accounts: search by handle or name, filter by platform, risk level and
  network membership, sort by risk or last seen, 50 per page. All of it lives in the
  URL, so reloading or sharing a link restores the same view.
  """
  use DripstoneWeb, :live_view

  alias Dripstone.Feeds
  alias Dripstone.Tracker

  @risks %{"low" => :low, "medium" => :medium, "high" => :high}
  @sorts %{"risk" => :risk, "last_seen" => :last_seen}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Accounts")
     |> stream_configure(:accounts, dom_id: &"account-row-#{&1.account.id}")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    options = Tracker.list_network_options()
    network_ids = MapSet.new(options, &elem(&1, 1))

    filters = %{
      q: params |> Map.get("q", "") |> String.trim() |> String.slice(0, 100),
      platform: if(Feeds.get(params["platform"]), do: params["platform"]),
      risk: Map.get(@risks, params["risk"]),
      network: network_param(params["network"], network_ids),
      sort: Map.get(@sorts, params["sort"], :risk),
      page: page_param(params["page"])
    }

    {:noreply,
     socket
     |> assign(filters: filters, networks: options)
     |> assign(:form, to_form(form_params(filters), as: :filters))
     |> load()}
  end

  defp network_param(value, _ids) when value in ["any", "none"], do: value
  defp network_param(value, ids) when is_binary(value), do: if(value in ids, do: value)
  defp network_param(_value, _ids), do: nil

  defp page_param(value) when is_binary(value) do
    case Integer.parse(value) do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  defp page_param(_value), do: 1

  defp load(socket) do
    filters = socket.assigns.filters

    page =
      filters
      |> Map.update!(:q, &if(&1 == "", do: nil, else: &1))
      |> Map.reject(fn {_k, v} -> is_nil(v) end)
      |> Tracker.list_accounts()

    socket
    |> assign(total: page.total, page: page.page, pages: page.pages)
    |> stream(:accounts, page.entries, reset: true)
  end

  @impl true
  def handle_event("filter", %{"filters" => params}, socket) do
    query =
      params
      |> Map.take(["q", "platform", "risk", "network", "sort"])
      |> Enum.reject(fn {key, value} ->
        value in [nil, ""] or (key == "sort" and value == "risk")
      end)

    {:noreply, push_patch(socket, to: ~p"/accounts?#{query}")}
  end

  defp form_params(filters) do
    %{
      "q" => filters.q,
      "platform" => filters.platform || "",
      "risk" => (filters.risk && Atom.to_string(filters.risk)) || "",
      "network" => filters.network || "",
      "sort" => Atom.to_string(filters.sort)
    }
  end

  # Current filters as query params, without defaults, for links and pages.
  defp query(filters, overrides) do
    filters
    |> Map.merge(Map.new(overrides))
    |> Enum.flat_map(fn
      {:q, ""} -> []
      {:sort, :risk} -> []
      {:page, 1} -> []
      {_key, nil} -> []
      {key, value} when is_atom(value) -> [{key, Atom.to_string(value)}]
      {key, value} -> [{key, value}]
    end)
    |> Enum.sort()
  end

  defp filtered?(filters),
    do: filters.q != "" or Enum.any?([filters.platform, filters.risk, filters.network])

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} nav={@nav} current_scope={@current_scope}>
      <.page_header title="Accounts">
        <:subtitle>Every tracked account across the feeds.</:subtitle>
        <:actions>
          <span id="account-total" class="text-sm tabular-nums text-ink-muted">
            {format_number(@total)} {if @total == 1, do: "account", else: "accounts"}
          </span>
        </:actions>
      </.page_header>

      <.card padded={false}>
        <.filter_bar id="account-filters" for={@form} clear={filtered?(@filters) && ~p"/accounts"}>
          <div class="w-full sm:w-64">
            <.input
              field={@form[:q]}
              type="search"
              label="Search"
              placeholder="Handle or name"
              phx-debounce="250"
              autocomplete="off"
            />
          </div>
          <div class="w-[calc(50%-0.375rem)] sm:w-36">
            <.input
              field={@form[:platform]}
              type="select"
              label="Platform"
              prompt="Any"
              options={Enum.map(Feeds.all(), &{&1.name(), &1.id()})}
            />
          </div>
          <div class="w-[calc(50%-0.375rem)] sm:w-32">
            <.input
              field={@form[:risk]}
              type="select"
              label="Risk"
              prompt="Any"
              options={[{"High", "high"}, {"Medium", "medium"}, {"Low", "low"}]}
            />
          </div>
          <div class="w-[calc(50%-0.375rem)] sm:w-48">
            <.input
              field={@form[:network]}
              type="select"
              label="Network"
              prompt="Any"
              options={[
                {"In any network", "any"},
                {"Not in a network", "none"} | @networks
              ]}
            />
          </div>
          <div class="w-[calc(50%-0.375rem)] sm:w-40">
            <.input
              field={@form[:sort]}
              type="select"
              label="Sort"
              options={[{"Highest risk", "risk"}, {"Last seen", "last_seen"}]}
            />
          </div>
        </.filter_bar>

        <.table
          id="accounts"
          rows={@streams.accounts}
          row_click={fn {_id, entry} -> JS.navigate(~p"/accounts/#{entry.account.id}") end}
        >
          <:col :let={{_id, entry}} label="Account">
            <.link
              navigate={~p"/accounts/#{entry.account.id}"}
              class="block font-mono text-sm text-ink hover:text-accent"
            >
              {handle(entry.account)}
            </.link>
            <span class="text-xs text-ink-muted">{entry.account.display_name}</span>
          </:col>
          <:col :let={{_id, entry}} label="Platform">
            <.platform_badge feed_id={entry.account.feed_id} />
          </:col>
          <:col :let={{_id, entry}} label="Risk">
            <.risk_badge score={entry.account.risk_score} />
          </:col>
          <:col :let={{_id, entry}} label="Network" class="max-w-56">
            <span :if={entry.networks == []} class="text-ink-faint">—</span>
            <span :for={network <- entry.networks} class="flex items-center gap-2">
              <span class="truncate text-ink">{network.name}</span>
              <.status_pill status={network.status} />
            </span>
          </:col>
          <:col :let={{_id, entry}} label="Last seen" class="whitespace-nowrap text-ink-muted">
            <.relative_time :if={entry.account.last_seen_at} at={entry.account.last_seen_at} />
          </:col>
          <:empty>
            <.empty_state
              id="accounts-empty-state"
              title="No accounts match these filters"
              icon="hero-funnel"
            >
              <:actions><.button patch={~p"/accounts"} size="sm">Clear filters</.button></:actions>
            </.empty_state>
          </:empty>
        </.table>

        <.pager
          id="account-pager"
          page={@page}
          pages={@pages}
          path={&~p"/accounts?#{query(@filters, page: &1)}"}
        />
      </.card>
    </Layouts.app>
    """
  end

  defp handle(account) do
    case Feeds.get(account.feed_id) do
      nil -> account.handle
      feed -> feed.format_handle(account)
    end
  end
end
