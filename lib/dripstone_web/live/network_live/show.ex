defmodule DripstoneWeb.NetworkLive.Show do
  @moduledoc """
  A network (suspected bot farm) in detail, with four views kept in the URL
  (`?view=summary|graph|notes|history`):

    * Summary: AI summary, shared evidence, posting heatmap, members, alert history,
      related networks
    * Graph: linked-account graph with link-type toggles and a node panel
    * Notes and History

  Curation tools: rename, tags (with suggestions), notes, add / remove / move
  members, split, merge into another network and relate networks. Destructive
  actions (merge, move, split, remove) go through a confirmation that states the
  impact first. Refreshes live on tracker changes.
  """
  use DripstoneWeb, :live_view

  alias Dripstone.Alerts
  alias Dripstone.Feeds
  alias Dripstone.Tracker
  alias Dripstone.Tracker.Link

  @views %{"summary" => :summary, "graph" => :graph, "notes" => :notes, "history" => :history}
  @kinds Map.new(Link.kinds(), &{Atom.to_string(&1), &1})
  @strength_rank %{weak: 1, moderate: 2, strong: 3}

  ## Lifecycle

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(
       network_id: id,
       selected: MapSet.new(),
       hidden_kinds: MapSet.new(),
       selected_node: nil,
       rename_form: nil,
       pending: nil,
       tag_suggestions: [],
       tag_form: tag_form(),
       note_form: note_form()
     )
     |> stream_configure(:members, dom_id: &"member-#{&1.account.id}")
     |> stream_configure(:alerts, dom_id: &"network-alert-#{&1.id}")
     |> stream_configure(:notes, dom_id: &"note-#{&1.id}")
     |> stream_configure(:history, dom_id: &"history-#{&1.id}")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    view = Map.get(@views, params["view"], :summary)
    {:noreply, socket |> assign(:view, view) |> load()}
  end

  defp load(socket) do
    case Tracker.get_network(socket.assigns.network_id) do
      nil ->
        assign(socket, network: nil, page_title: "Network not found")

      detail ->
        socket
        |> assign(
          network: detail.network,
          page_title: detail.network.name,
          retired_into: detail.retired_into,
          related: detail.related,
          heatmap: detail.heatmap,
          last_activity_at: detail.last_activity_at,
          open_alerts: Enum.count(detail.alerts, &(&1.status == :open)),
          alert_count: length(detail.alerts),
          note_count: length(detail.notes),
          member_accounts: Map.new(detail.members, &{&1.account.id, &1.account})
        )
        |> update(:selected, &MapSet.intersection(&1, MapSet.new(detail.network.member_ids)))
        |> stream(:members, detail.members, reset: true)
        |> stream(:alerts, detail.alerts, reset: true)
        |> stream(:notes, detail.notes, reset: true)
        |> stream(:history, detail.history, reset: true)
        |> load_graph()
    end
  end

  defp load_graph(%{assigns: %{view: :graph, network: %{retired_into: nil}}} = socket),
    do: assign(socket, :graph, Tracker.network_graph(socket.assigns.network_id))

  defp load_graph(socket), do: assign(socket, :graph, nil)

  @doc false
  # Called by DripstoneWeb.Nav for every tracker change.
  def handle_tracker_event({:network_updated, id}, %{assigns: %{network_id: id}} = socket),
    do: load(socket)

  def handle_tracker_event({_event, %{network_id: id}}, %{assigns: %{network_id: id}} = socket),
    do: load(socket)

  def handle_tracker_event(_message, socket), do: socket

  ## Forms

  defp tag_form(changeset \\ Tracker.tag_changeset()), do: to_form(changeset, as: :tag)
  defp note_form(changeset \\ Tracker.note_changeset()), do: to_form(changeset, as: :note)
  defp name_form(changeset), do: to_form(changeset, as: :network)

  ## Events: name, tags, notes

  @impl true
  def handle_event("edit_name", _params, socket) do
    changeset = Tracker.name_changeset(%{"name" => socket.assigns.network.name})
    {:noreply, assign(socket, :rename_form, name_form(changeset))}
  end

  def handle_event("cancel_name", _params, socket),
    do: {:noreply, assign(socket, :rename_form, nil)}

  def handle_event("save_name", %{"network" => params}, socket) do
    case Tracker.rename_network(
           socket.assigns.network_id,
           params,
           socket.assigns.current_scope.user.email
         ) do
      {:ok, _network} ->
        {:noreply, socket |> assign(:rename_form, nil) |> load()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :rename_form, name_form(changeset))}

      {:error, reason} ->
        {:noreply, error(socket, reason)}
    end
  end

  def handle_event("tag_input", %{"tag" => %{"tag" => text}}, socket) do
    current = socket.assigns.network.tags

    suggestions =
      if String.trim(text) == "",
        do: [],
        else: text |> Tracker.list_tags() |> Enum.reject(&(&1 in current)) |> Enum.take(5)

    {:noreply, assign(socket, :tag_suggestions, suggestions)}
  end

  def handle_event("add_tag", %{"tag" => params}, socket), do: add_tag(socket, params)
  def handle_event("use_tag", %{"tag" => tag}, socket), do: add_tag(socket, %{"tag" => tag})

  def handle_event("remove_tag", %{"tag" => tag}, socket) do
    {:ok, _} =
      Tracker.remove_tag(socket.assigns.network_id, tag, socket.assigns.current_scope.user.email)

    {:noreply, load(socket)}
  end

  def handle_event("validate_note", %{"note" => params}, socket) do
    {:noreply,
     assign(
       socket,
       :note_form,
       params |> Tracker.note_changeset() |> Map.put(:action, :validate) |> note_form()
     )}
  end

  def handle_event("add_note", %{"note" => params}, socket) do
    case Tracker.add_note(
           socket.assigns.network_id,
           params,
           socket.assigns.current_scope.user.email
         ) do
      {:ok, _note} ->
        {:noreply, socket |> assign(:note_form, note_form()) |> load()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :note_form, note_form(changeset))}

      {:error, reason} ->
        {:noreply, error(socket, reason)}
    end
  end

  ## Events: members and graph

  def handle_event("toggle_member", %{"id" => id}, socket) do
    case Map.fetch(socket.assigns.member_accounts, id) do
      {:ok, account} ->
        selected = socket.assigns.selected

        selected =
          if id in selected, do: MapSet.delete(selected, id), else: MapSet.put(selected, id)

        entry = %{account: account, joined_at: socket.assigns.network.joined_at[id]}
        {:noreply, socket |> assign(:selected, selected) |> stream_insert(:members, entry)}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("clear_selection", _params, socket) do
    entries =
      Enum.map(socket.assigns.selected, fn id ->
        %{
          account: socket.assigns.member_accounts[id],
          joined_at: socket.assigns.network.joined_at[id]
        }
      end)

    {:noreply,
     Enum.reduce(
       entries,
       assign(socket, :selected, MapSet.new()),
       &stream_insert(&2, :members, &1)
     )}
  end

  def handle_event("toggle_kind", %{"kind" => kind}, socket) do
    case Map.fetch(@kinds, kind) do
      {:ok, kind} ->
        hidden = socket.assigns.hidden_kinds

        hidden =
          if kind in hidden, do: MapSet.delete(hidden, kind), else: MapSet.put(hidden, kind)

        {:noreply, assign(socket, :hidden_kinds, hidden)}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("select_node", %{"id" => id}, socket) do
    selected = if socket.assigns.selected_node == id, do: nil, else: id
    {:noreply, assign(socket, :selected_node, selected)}
  end

  ## Events: pending actions (modal)

  def handle_event("open_pending", %{"type" => type}, socket) do
    {:noreply, assign(socket, :pending, new_pending(type, socket.assigns))}
  end

  def handle_event("cancel_pending", _params, socket),
    do: {:noreply, assign(socket, :pending, nil)}

  def handle_event(
        "pending_change",
        %{"pending" => params},
        %{assigns: %{pending: %{} = pending}} = socket
      ) do
    pending = %{pending | params: Map.merge(pending.params, params), error: nil}
    {:noreply, assign(socket, :pending, refresh_pending(pending, socket.assigns))}
  end

  def handle_event("pending_change", _params, socket), do: {:noreply, socket}

  def handle_event("add_member", %{"id" => account_id}, socket) do
    case Tracker.add_members(
           socket.assigns.network_id,
           [account_id],
           socket.assigns.current_scope.user.email
         ) do
      {:ok, _} ->
        socket = load(socket)

        {:noreply,
         assign(
           socket,
           :pending,
           socket.assigns.pending && refresh_pending(socket.assigns.pending, socket.assigns)
         )}

      {:error, reason} ->
        {:noreply, error(socket, reason)}
    end
  end

  def handle_event("confirm_pending", _params, %{assigns: %{pending: %{} = pending}} = socket) do
    run_pending(pending, socket)
  end

  def handle_event("confirm_pending", _params, socket), do: {:noreply, socket}

  defp add_tag(socket, params) do
    case Tracker.add_tag(
           socket.assigns.network_id,
           params,
           socket.assigns.current_scope.user.email
         ) do
      {:ok, _} ->
        {:noreply, socket |> assign(tag_form: tag_form(), tag_suggestions: []) |> load()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :tag_form, tag_form(changeset))}

      {:error, reason} ->
        {:noreply, error(socket, reason)}
    end
  end

  ## Pending actions

  defp new_pending(type, assigns) when type in ~w(merge move split remove relate add) do
    defaults = %{
      "merge" => %{"target" => ""},
      "move" => %{"target" => ""},
      "split" => %{"name" => ""},
      "remove" => %{},
      "relate" => %{"target" => "", "note" => ""},
      "add" => %{"q" => ""}
    }

    refresh_pending(
      %{type: String.to_existing_atom(type), params: defaults[type], error: nil},
      assigns
    )
  end

  defp new_pending(_type, _assigns), do: nil

  defp refresh_pending(pending, assigns) do
    Map.merge(pending, %{
      form: to_form(pending.params, as: :pending),
      impact: impact(pending, assigns),
      results:
        if(pending.type == :add, do: search_accounts(pending.params["q"], assigns), else: [])
    })
  end

  defp impact(%{type: :merge, params: %{"target" => target_id}}, assigns) do
    with %{network: target} <- target_id != "" && Tracker.get_network(target_id) do
      n = assigns.network

      "Moves #{plural(length(n.member_ids), "member")}, #{plural(assigns.alert_count, "alert")}, " <>
        "#{plural(assigns.note_count, "note")} and #{plural(length(n.tags), "tag")} into #{target.name}. " <>
        "#{n.name} will be retired and its page will point to #{target.name}."
    else
      _ -> nil
    end
  end

  defp impact(%{type: :move, params: %{"target" => target_id}}, assigns) do
    with %{network: target} <- target_id != "" && Tracker.get_network(target_id) do
      "Moves #{plural(MapSet.size(assigns.selected), "member")} from #{assigns.network.name} to #{target.name}. " <>
        "Detection won't add them back to #{assigns.network.name}."
    else
      _ -> nil
    end
  end

  defp impact(%{type: :split}, assigns) do
    count = MapSet.size(assigns.selected)
    remaining = length(assigns.network.member_ids) - count

    "Creates a new Suspected network with #{plural(count, "member")}. " <>
      "#{assigns.network.name} keeps #{plural(remaining, "member")}."
  end

  defp impact(%{type: :remove}, assigns) do
    "Removes #{plural(MapSet.size(assigns.selected), "member")} from #{assigns.network.name}. " <>
      "Detection won't add them back."
  end

  defp impact(_pending, _assigns), do: nil

  defp search_accounts(q, assigns) when is_binary(q) and q != "" do
    members = MapSet.new(assigns.network.member_ids)

    Tracker.list_accounts(%{q: q}).entries
    |> Enum.map(& &1.account)
    |> Enum.reject(&(&1.id in members))
    |> Enum.take(8)
  end

  defp search_accounts(_q, _assigns), do: []

  defp run_pending(%{type: :merge, params: %{"target" => target}} = pending, socket) do
    case Tracker.merge_networks(
           socket.assigns.network_id,
           target,
           socket.assigns.current_scope.user.email
         ) do
      {:ok, merged} ->
        {:noreply,
         socket
         |> put_flash(:info, "Merged #{socket.assigns.network.name} into #{merged.name}.")
         |> push_navigate(to: ~p"/networks/#{merged.id}")}

      {:error, reason} ->
        {:noreply, assign(socket, :pending, %{pending | error: message(reason)})}
    end
  end

  defp run_pending(%{type: :move, params: %{"target" => target}} = pending, socket) do
    ids = MapSet.to_list(socket.assigns.selected)

    case Tracker.move_members(
           socket.assigns.network_id,
           target,
           ids,
           socket.assigns.current_scope.user.email
         ) do
      {:ok, %{to: to}} ->
        {:noreply, done(socket, "Moved #{plural(length(ids), "member")} to #{to.name}.")}

      {:error, reason} ->
        {:noreply, assign(socket, :pending, %{pending | error: message(reason)})}
    end
  end

  defp run_pending(%{type: :split, params: params} = pending, socket) do
    ids = MapSet.to_list(socket.assigns.selected)

    case Tracker.split_network(
           socket.assigns.network_id,
           ids,
           params,
           socket.assigns.current_scope.user.email
         ) do
      {:ok, split} ->
        {:noreply, done(socket, "Split #{plural(length(ids), "member")} into #{split.name}.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :pending, %{pending | error: changeset_message(changeset)})}

      {:error, reason} ->
        {:noreply, assign(socket, :pending, %{pending | error: message(reason)})}
    end
  end

  defp run_pending(%{type: :remove} = pending, socket) do
    ids = MapSet.to_list(socket.assigns.selected)

    case Tracker.remove_members(
           socket.assigns.network_id,
           ids,
           socket.assigns.current_scope.user.email
         ) do
      {:ok, _} ->
        {:noreply, done(socket, "Removed #{plural(length(ids), "member")}.")}

      {:error, reason} ->
        {:noreply, assign(socket, :pending, %{pending | error: message(reason)})}
    end
  end

  defp run_pending(%{type: :relate, params: %{"target" => target} = params} = pending, socket) do
    case Tracker.relate_networks(
           socket.assigns.network_id,
           target,
           params["note"],
           socket.assigns.current_scope.user.email
         ) do
      {:ok, _} ->
        {:noreply, socket |> assign(:pending, nil) |> load()}

      {:error, reason} ->
        {:noreply, assign(socket, :pending, %{pending | error: message(reason)})}
    end
  end

  defp run_pending(%{type: :add}, socket), do: {:noreply, assign(socket, :pending, nil)}

  defp done(socket, flash) do
    socket |> assign(pending: nil, selected: MapSet.new()) |> put_flash(:info, flash) |> load()
  end

  defp error(socket, reason), do: put_flash(socket, :error, message(reason))

  defp message(:retired), do: "That network has been merged into another one."
  defp message(:not_found), do: "Pick a network first."
  defp message(:same_network), do: "Pick a different network."
  defp message(:cannot_split_all), do: "Leave at least one member behind, or merge instead."
  defp message(:no_members_selected), do: "Select at least one member first."
  defp message(:not_a_member), do: "Some selected accounts are no longer members."
  defp message(:unknown_account), do: "That account doesn't exist."
  defp message(_reason), do: "That didn't work. Try again."

  defp changeset_message(changeset) do
    changeset.errors
    |> Enum.map(fn {field, error} ->
      "#{String.capitalize(to_string(field))} #{translate_error(error)}"
    end)
    |> Enum.join(". ")
  end

  defp plural(1, noun), do: "1 #{noun}"
  defp plural(n, noun), do: "#{n} #{noun}s"

  ## Render

  @impl true
  def render(%{network: nil} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} nav={@nav} current_scope={@current_scope}>
      <.not_found title="Network not found" back={~p"/networks"} back_label="Back to networks" />
    </Layouts.app>
    """
  end

  def render(%{network: %{retired_into: target}} = assigns) when not is_nil(target) do
    ~H"""
    <Layouts.app flash={@flash} nav={@nav} current_scope={@current_scope}>
      <.page_header title={@network.name} back={~p"/networks"} back_label="Networks" />
      <.card id="merged-notice" class="max-w-xl">
        <p class="flex items-center gap-2 font-medium text-ink">
          <.icon name="hero-arrows-pointing-in" class="size-5 text-accent" /> This network was merged
        </p>
        <p class="mt-1 text-sm text-ink-muted">
          Its members, alerts, notes and tags now belong to <.link
            :if={@retired_into}
            id="merged-into"
            navigate={~p"/networks/#{@retired_into.id}"}
            class="font-medium text-accent hover:underline"
          >
            {@retired_into.name}
          </.link>.
        </p>
      </.card>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} nav={@nav} current_scope={@current_scope}>
      <.link
        navigate={~p"/networks"}
        class="mb-3 inline-flex items-center gap-1 text-sm text-ink-muted hover:text-ink"
      >
        <.icon name="hero-arrow-left-mini" class="size-4" /> Networks
      </.link>

      <header id="network-header" class="mb-5">
        <div class="flex flex-wrap items-start justify-between gap-4">
          <div class="min-w-0">
            <%= if @rename_form do %>
              <.form
                for={@rename_form}
                id="rename-form"
                phx-submit="save_name"
                class="flex items-start gap-2"
              >
                <.input
                  field={@rename_form[:name]}
                  id="rename-input"
                  autofocus
                  maxlength="80"
                  class="h-10 w-80 max-w-full rounded-lg border border-accent bg-surface px-3 text-xl font-semibold text-ink focus:outline-none focus:ring-2 focus:ring-accent/25"
                />
                <.button type="submit" variant="primary">Save</.button>
                <.button type="button" phx-click="cancel_name" variant="ghost">Cancel</.button>
              </.form>
            <% else %>
              <h1
                id="page-title"
                class="flex items-center gap-2 text-xl font-semibold tracking-tight text-ink sm:text-2xl"
              >
                {@network.name}
                <button
                  id="edit-name"
                  type="button"
                  phx-click="edit_name"
                  class="rounded p-1 text-ink-faint hover:bg-surface-raised hover:text-ink cursor-pointer"
                  aria-label="Rename network"
                >
                  <.icon name="hero-pencil-square" class="size-5" />
                </button>
              </h1>
            <% end %>
            <div class="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1.5 text-sm text-ink-muted">
              <.status_pill status={@network.status} />
              <span class="tabular-nums">{@network.confidence}% confidence</span>
              <span class="tabular-nums">{length(@network.member_ids)} accounts</span>
              <.link
                :if={@open_alerts > 0}
                id="open-alerts-link"
                patch={~p"/networks/#{@network.id}" <> "#alert-history"}
                class="font-medium text-sev-high hover:underline"
              >
                {plural(@open_alerts, "open alert")}
              </.link>
            </div>
            <div class="mt-1.5 flex flex-wrap items-center gap-x-3 gap-y-1.5 text-xs text-ink-faint">
              <span :if={@network.detected_name} id="detected-as">Detected as {@network.detected_name}</span>
              <span class="flex gap-1"><.platform_badge
                :for={feed <- @network.platforms}
                feed_id={feed}
              /></span>
              <span :if={@network.first_activity_at}>
                active {Calendar.strftime(@network.first_activity_at, "%b %-d")} –
                <.relative_time :if={@last_activity_at} at={@last_activity_at} />
              </span>
              <span :if={@network.main_domain}>main domain
              <span id="main-domain" class="font-mono text-ink-muted">{@network.main_domain}</span></span>
            </div>
          </div>
          <div class="flex flex-wrap gap-2">
            <.button id="open-relate" phx-click="open_pending" phx-value-type="relate" size="sm">
              <.icon name="hero-link-mini" class="size-4" /> Relate…
            </.button>
            <.button id="open-merge" phx-click="open_pending" phx-value-type="merge" size="sm">
              <.icon name="hero-arrows-pointing-in-mini" class="size-4" /> Merge into…
            </.button>
          </div>
        </div>

        <div id="tags" class="mt-3 flex flex-wrap items-center gap-1.5">
          <.tag_chip :for={tag <- @network.tags} id={"tag-#{tag}"} tag={tag} remove="remove_tag" />
          <.form
            for={@tag_form}
            id="tag-form"
            phx-change="tag_input"
            phx-submit="add_tag"
            class="relative"
          >
            <input
              type="text"
              name={@tag_form[:tag].name}
              id="tag-input"
              value={@tag_form[:tag].value}
              placeholder="+ tag"
              autocomplete="off"
              phx-debounce="150"
              class="h-6 w-28 rounded-full border border-dashed border-line-strong bg-transparent px-2.5 text-xs text-ink placeholder:text-ink-faint focus:w-40 focus:border-accent focus:outline-none transition-all"
            />
            <div
              :if={@tag_suggestions != []}
              id="tag-suggestions"
              class="absolute top-7 left-0 z-10 w-44 rounded-lg border border-line bg-surface p-1 shadow-pop"
            >
              <button
                :for={tag <- @tag_suggestions}
                type="button"
                phx-click="use_tag"
                phx-value-tag={tag}
                class="block w-full rounded px-2 py-1 text-left text-xs text-ink hover:bg-surface-raised cursor-pointer"
              >
                #{tag}
              </button>
            </div>
            <p
              :for={msg <- Enum.map(@tag_form[:tag].errors, &translate_error/1)}
              class="mt-1 text-xs text-sev-high"
            >
              {msg}
            </p>
          </.form>
        </div>
      </header>

      <nav id="network-tabs" class="mb-5 flex gap-1 border-b border-line" aria-label="Network views">
        <.link
          :for={
            {key, label} <- [
              summary: "Summary",
              graph: "Graph",
              notes: "Notes (#{@note_count})",
              history: "History"
            ]
          }
          id={"tab-#{key}"}
          patch={~p"/networks/#{@network.id}?#{if key == :summary, do: [], else: [view: key]}"}
          aria-current={if @view == key, do: "page"}
          class={[
            "-mb-px border-b-2 px-3 py-2 text-sm font-medium transition-colors",
            if(@view == key,
              do: "border-accent text-ink",
              else: "border-transparent text-ink-muted hover:text-ink"
            )
          ]}
        >
          {label}
        </.link>
      </nav>

      <div
        :if={@view == :summary}
        id="summary-view"
        class="grid grid-cols-1 gap-4 lg:grid-cols-3 lg:gap-6"
      >
        <div class="space-y-4 lg:col-span-2 lg:space-y-6">
          <.card id="network-summary">
            <%= if @network.summary do %>
              <.ai_label generated_at={@network.summary.generated_at} />
              <p class="mt-2 text-sm leading-relaxed text-ink">{@network.summary.text}</p>
            <% else %>
              <p id="no-summary" class="text-sm text-ink-muted">
                No summary has been generated for this network yet.
              </p>
            <% end %>
          </.card>

          <.network_assessment id="network-assessment" assessment={@network.assessment} />

          <.card id="posting-heatmap" title="When members post (UTC)">
            <.heatmap id="network-heatmap" heatmap={@heatmap} />
          </.card>

          <.card id="members" title={"Members (#{length(@network.member_ids)})"} padded={false}>
            <:header_actions>
              <.button
                id="open-add"
                phx-click="open_pending"
                phx-value-type="add"
                size="sm"
                variant="ghost"
              >
                <.icon name="hero-plus-mini" class="size-4" /> Add account
              </.button>
            </:header_actions>
            <div
              :if={MapSet.size(@selected) > 0}
              id="selection-bar"
              class="sticky top-14 z-10 flex flex-wrap items-center gap-2 border-y border-accent/30 bg-accent-soft px-4 py-2 text-sm"
            >
              <span class="font-medium text-accent-strong">{MapSet.size(@selected)} selected</span>
              <.button id="open-move" phx-click="open_pending" phx-value-type="move" size="sm">Move to…</.button>
              <.button id="open-split" phx-click="open_pending" phx-value-type="split" size="sm">Split…</.button>
              <.button id="open-remove" phx-click="open_pending" phx-value-type="remove" size="sm">Remove</.button>
              <button
                type="button"
                phx-click="clear_selection"
                class="ml-auto text-ink-muted hover:text-ink cursor-pointer"
              >Clear</button>
            </div>
            <ul
              id="member-list"
              phx-update="stream"
              class="max-h-[32rem] divide-y divide-line overflow-y-auto"
            >
              <li id="members-empty" class="hidden only:block">
                <.empty_state title="No members" icon="hero-user-group" />
              </li>
              <li
                :for={{dom_id, entry} <- @streams.members}
                id={dom_id}
                class="flex items-center gap-3 px-4 py-2.5 hover:bg-surface-raised"
              >
                <input
                  type="checkbox"
                  id={"select-#{entry.account.id}"}
                  checked={entry.account.id in @selected}
                  phx-click="toggle_member"
                  phx-value-id={entry.account.id}
                  class="size-4 rounded accent-[var(--color-accent)] cursor-pointer"
                  aria-label={"Select #{handle(entry.account)}"}
                />
                <.link
                  navigate={~p"/accounts/#{entry.account.id}"}
                  class="min-w-0 flex-1 truncate font-mono text-sm text-ink hover:text-accent"
                >
                  {handle(entry.account)}
                </.link>
                <.platform_badge feed_id={entry.account.feed_id} />
                <.risk_badge score={entry.account.risk_score} />
                <span class="hidden w-24 text-right text-xs text-ink-faint sm:block">
                  <span :if={entry.joined_at}>joined <.relative_time at={entry.joined_at} /></span>
                </span>
              </li>
            </ul>
          </.card>
        </div>

        <div class="space-y-4 lg:space-y-6">
          <.card id="shared-evidence" title="Shared evidence" padded={false}>
            <ul class="divide-y divide-line">
              <li :if={@network.evidence == []} class="px-4 py-6 text-center text-sm text-ink-muted">
                No shared evidence recorded.
              </li>
              <li
                :for={{item, i} <- Enum.with_index(sort_evidence(@network.evidence))}
                id={"shared-evidence-#{i}"}
                class="space-y-1.5 px-4 py-3"
              >
                <.strength_badge strength={item.strength} />
                <p class="text-sm text-ink">{item.explanation}</p>
                <p class="text-xs text-ink-faint">
                  involving {plural(length(item.account_ids), "member")}
                </p>
              </li>
            </ul>
          </.card>

          <.card id="alert-history" title="Alert history" padded={false}>
            <ul id="network-alerts" phx-update="stream" class="divide-y divide-line">
              <li
                id="network-alerts-empty"
                class="hidden only:block px-4 py-6 text-center text-sm text-ink-muted"
              >
                No alerts yet.
              </li>
              <li :for={{dom_id, alert} <- @streams.alerts} id={dom_id}>
                <.link
                  navigate={~p"/alerts/#{alert.id}"}
                  class="block space-y-1 px-4 py-3 hover:bg-surface-raised"
                >
                  <div class="flex items-center gap-2">
                    <.severity_badge severity={alert.severity} />
                    <span class="text-sm font-medium text-ink">{trigger_name(alert.trigger_id)}</span>
                    <.status_pill status={alert.status} class="ml-auto" />
                  </div>
                  <p class="flex flex-wrap items-center gap-x-2 text-xs text-ink-faint">
                    <.relative_time at={alert.raised_at} />
                    <span
                      :if={alert.previously_dismissed_alert_id}
                      class="text-status-suspected"
                      data-previously-dismissed
                    >
                      · Previously dismissed
                    </span>
                  </p>
                </.link>
              </li>
            </ul>
          </.card>

          <.card id="related-networks" title="Related networks" padded={false}>
            <ul class="divide-y divide-line">
              <li :if={@related == []} class="px-4 py-6 text-center text-sm text-ink-muted">
                None marked yet.
              </li>
              <li
                :for={other <- @related}
                id={"related-#{other.id}"}
                class="flex items-center gap-2 px-4 py-2.5"
              >
                <.link
                  navigate={~p"/networks/#{other.id}"}
                  class="flex-1 truncate text-sm font-medium text-ink hover:text-accent"
                >{other.name}</.link>
                <.status_pill status={other.status} />
              </li>
            </ul>
          </.card>
        </div>
      </div>

      <div
        :if={@view == :graph && @graph}
        id="graph-view"
        class="grid grid-cols-1 gap-4 lg:grid-cols-3 lg:gap-6"
      >
        <div class="lg:col-span-2">
          <.card padded={false}>
            <div id="graph-legend" class="flex flex-wrap gap-2 border-b border-line px-4 py-3">
              <button
                :for={kind <- link_kinds()}
                id={"toggle-#{kind}"}
                type="button"
                phx-click="toggle_kind"
                phx-value-kind={kind}
                aria-pressed={to_string(kind not in @hidden_kinds)}
                class={[
                  "inline-flex items-center gap-2 rounded-full border px-2.5 py-1 text-xs font-medium transition-colors cursor-pointer",
                  if(kind in @hidden_kinds,
                    do: "border-line text-ink-faint line-through",
                    else: "border-line-strong text-ink"
                  )
                ]}
              >
                <span
                  class="h-0.5 w-4 rounded-full"
                  style={"background: var(--color-link-#{kind_slug(kind)})"}
                ></span>
                {link_kind_label(kind)}
              </button>
            </div>
            <div class="p-2 sm:p-4">
              <.network_graph
                id="network-graph"
                graph={@graph}
                selected={@selected_node}
                hidden_kinds={@hidden_kinds}
                labels={Map.new(@graph.nodes, &{&1.id, handle(@member_accounts[&1.id])})}
              />
            </div>
            <p
              :if={@graph.omitted > 0}
              id="graph-omitted"
              class="border-t border-line px-4 py-3 text-sm text-ink-muted"
            >
              Showing the {length(@graph.nodes)} most-linked members; {@graph.omitted} members are not shown.
              <.link patch={~p"/networks/#{@network.id}"} class="text-accent hover:underline">See the full member list</.link>
            </p>
          </.card>
        </div>
        <.card id="node-panel" title="Account" class="self-start">
          <%= if account = @selected_node && @member_accounts[@selected_node] do %>
            <p class="font-mono text-sm font-medium text-ink">{handle(account)}</p>
            <div class="mt-2 flex items-center gap-2">
              <.platform_badge feed_id={account.feed_id} />
              <.risk_badge score={account.risk_score} />
            </div>
            <dl class="mt-3 space-y-1 text-sm">
              <div
                :for={{kind, count} <- node_links(@graph, @selected_node)}
                class="flex justify-between gap-2"
              >
                <dt class="text-ink-muted">{link_kind_label(kind)}</dt>
                <dd class="tabular-nums text-ink">{count}</dd>
              </div>
            </dl>
            <.link
              id="node-account-link"
              navigate={~p"/accounts/#{account.id}"}
              class="mt-3 inline-flex items-center gap-1 text-sm font-medium text-accent hover:underline"
            >
              Open account <.icon name="hero-arrow-right-mini" class="size-4" />
            </.link>
          <% else %>
            <p class="text-sm text-ink-muted">
              Select an account in the graph to see how it's linked.
            </p>
          <% end %>
        </.card>
      </div>

      <div :if={@view == :notes} id="notes-view" class="max-w-2xl space-y-4">
        <.card>
          <.form for={@note_form} id="note-form" phx-change="validate_note" phx-submit="add_note">
            <.input
              field={@note_form[:body]}
              type="textarea"
              label="Add a note"
              rows="3"
              placeholder="What did you find?"
            />
            <div class="flex justify-end">
              <.button type="submit" variant="primary" size="sm">Add note</.button>
            </div>
          </.form>
        </.card>
        <ul id="notes" phx-update="stream" class="space-y-3">
          <li id="notes-empty" class="hidden only:block text-center text-sm text-ink-muted">
            No notes yet.
          </li>
          <li
            :for={{dom_id, note} <- @streams.notes}
            id={dom_id}
            class="rounded-card border border-line bg-surface p-4 shadow-card"
          >
            <p class="whitespace-pre-line text-sm text-ink">{note.body}</p>
            <p class="mt-2 text-xs text-ink-faint">{note.by} · <.relative_time at={note.at} /></p>
          </li>
        </ul>
      </div>

      <div :if={@view == :history} id="history-view" class="max-w-2xl">
        <.card padded={false}>
          <ol id="history" phx-update="stream" class="divide-y divide-line px-4">
            <li id="history-empty" class="hidden only:block py-6 text-center text-sm text-ink-muted">
              No changes recorded yet.
            </li>
            <li
              :for={{dom_id, entry} <- @streams.history}
              id={dom_id}
              class="flex items-start gap-3 py-3"
            >
              <span
                data-actor={entry.actor}
                class={[
                  "mt-0.5 inline-flex shrink-0 rounded px-1.5 py-0.5 text-[11px] font-semibold uppercase tracking-wide",
                  if(entry.actor == :analyst,
                    do: "bg-accent-soft text-accent-strong",
                    else: "bg-surface-raised text-ink-muted"
                  )
                ]}
              >
                {if entry.actor == :analyst, do: "Analyst", else: "System"}
              </span>
              <div class="min-w-0 flex-1 text-sm">
                <p class="text-ink">{entry.summary}</p>
                <p class="mt-0.5 text-xs text-ink-faint">
                  {entry.by} · <.relative_time at={entry.at} />
                </p>
              </div>
            </li>
          </ol>
        </.card>
      </div>

      <.modal :if={@pending} id="pending-modal" show on_cancel={JS.push("cancel_pending")}>
        <:title>{pending_title(@pending, @network)}</:title>
        <.form
          for={@pending.form}
          id="pending-form"
          phx-change="pending_change"
          phx-submit="confirm_pending"
          class="space-y-3"
        >
          <.input
            :if={@pending.type in [:merge, :move, :relate]}
            field={@pending.form[:target]}
            type="select"
            label={
              if @pending.type == :merge,
                do: "Merge into",
                else: if(@pending.type == :move, do: "Move to", else: "Related network")
            }
            prompt="Choose a network…"
            options={network_options(@network.id)}
          />
          <.input
            :if={@pending.type == :split}
            field={@pending.form[:name]}
            label="New network name"
            maxlength="80"
            placeholder="e.g. Sunrise Offshoot"
          />
          <.input
            :if={@pending.type == :relate}
            field={@pending.form[:note]}
            label="Note (optional)"
            placeholder="Why are they related?"
          />
          <.input
            :if={@pending.type == :add}
            field={@pending.form[:q]}
            type="search"
            label="Search accounts"
            placeholder="Handle or name"
            phx-debounce="200"
            autocomplete="off"
          />
        </.form>

        <ul
          :if={@pending.type == :add}
          id="add-results"
          class="mt-3 max-h-64 divide-y divide-line overflow-y-auto rounded-lg border border-line"
        >
          <li :if={@pending.results == []} class="px-3 py-4 text-center text-sm text-ink-muted">
            {if @pending.params["q"] in [nil, ""],
              do: "Type to search accounts.",
              else: "No matching accounts outside this network."}
          </li>
          <li
            :for={account <- @pending.results}
            id={"add-result-#{account.id}"}
            class="flex items-center gap-2 px-3 py-2"
          >
            <span class="min-w-0 flex-1 truncate font-mono text-sm text-ink">{handle(account)}</span>
            <.platform_badge feed_id={account.feed_id} />
            <.button phx-click="add_member" phx-value-id={account.id} size="sm">Add</.button>
          </li>
        </ul>

        <p
          :if={@pending.impact}
          id="pending-impact"
          class="mt-4 rounded-lg border border-line bg-surface-raised p-3 text-sm text-ink"
        >
          {@pending.impact}
        </p>
        <p :if={@pending.error} id="pending-error" class="mt-3 text-sm text-sev-high">
          {@pending.error}
        </p>

        <:actions>
          <.button id="cancel-pending" type="button" phx-click="cancel_pending">
            {if @pending.type == :add, do: "Done", else: "Cancel"}
          </.button>
          <.button
            :if={@pending.type != :add}
            id="confirm-pending"
            type="submit"
            form="pending-form"
            variant={if @pending.type in [:remove, :merge], do: "danger", else: "primary"}
          >
            {confirm_label(@pending.type)}
          </.button>
        </:actions>
      </.modal>
    </Layouts.app>
    """
  end

  ## Render helpers

  defp pending_title(%{type: :merge}, network), do: "Merge #{network.name} into another network"
  defp pending_title(%{type: :move}, _network), do: "Move selected members"
  defp pending_title(%{type: :split}, _network), do: "Split selected members into a new network"
  defp pending_title(%{type: :remove}, _network), do: "Remove selected members?"
  defp pending_title(%{type: :relate}, _network), do: "Mark a related network"
  defp pending_title(%{type: :add}, network), do: "Add accounts to #{network.name}"

  defp confirm_label(:merge), do: "Merge"
  defp confirm_label(:move), do: "Move"
  defp confirm_label(:split), do: "Split"
  defp confirm_label(:remove), do: "Remove"
  defp confirm_label(:relate), do: "Mark related"

  defp network_options(current_id) do
    for %{network: n} <- Tracker.list_networks(), n.id != current_id, do: {n.name, n.id}
  end

  defp sort_evidence(evidence), do: Enum.sort_by(evidence, &@strength_rank[&1.strength], :desc)

  defp node_links(graph, id) do
    graph.edges
    |> Enum.filter(&(id in [&1.a, &1.b]))
    |> Enum.frequencies_by(& &1.kind)
    |> Enum.sort_by(fn {_kind, n} -> -n end)
  end

  defp trigger_name(id) do
    case Alerts.get_trigger_type(id) do
      nil -> id
      type -> type.name
    end
  end

  defp handle(nil), do: "unknown"

  defp handle(account) do
    case Feeds.get(account.feed_id) do
      nil -> account.handle
      feed -> feed.format_handle(account)
    end
  end
end
