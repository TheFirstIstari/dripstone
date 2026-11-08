defmodule DripstoneWeb.AlertLive.Show do
  @moduledoc """
  Alert detail: the alert, its network, the evidence (strongest first), before/after
  values and the AI rationale, with Confirm / Dismiss (optional note), Undo for the
  last decision, and `j`/`k` to move through the inbox it was opened from.

  Keyboard: `c` confirm, `d` dismiss, `j` previous, `k` next (each key on the same
  side as its arrow: `j` is the left key, `k` the right), via the colocated
  `.AlertShortcuts` hook, which ignores keys typed into text fields.
  """
  use DripstoneWeb, :live_view

  alias Dripstone.Tracker
  alias DripstoneWeb.AlertLive.Filters

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok, assign(socket, alert_id: id, last_decision: nil, note_form: note_form())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = Filters.parse(params)

    {:noreply,
     socket
     |> assign(filters: filters, query: Filters.to_query(filters))
     |> load()}
  end

  defp load(socket) do
    %{alert_id: id, filters: filters} = socket.assigns

    case Tracker.get_alert(id) do
      nil ->
        assign(socket, detail: nil, neighbors: nil, page_title: "Alert not found")

      detail ->
        assign(socket,
          detail: detail,
          neighbors: Tracker.alert_neighbors(id, Filters.to_tracker(filters)),
          page_title: detail.alert.title
        )
    end
  end

  defp note_form(changeset \\ Tracker.decision_note_changeset()),
    do: to_form(changeset, as: :decision)

  @impl true
  def handle_event("validate_note", %{"decision" => params}, socket) do
    changeset = params |> Tracker.decision_note_changeset() |> Map.put(:action, :validate)
    {:noreply, assign(socket, :note_form, note_form(changeset))}
  end

  def handle_event("decide", %{"action" => action} = params, socket)
      when action in ["confirm", "dismiss"] do
    note = Map.get(params, "decision", %{})
    by = socket.assigns.current_scope.user.email

    result =
      case action do
        "confirm" -> Tracker.confirm_alert(socket.assigns.alert_id, note, by)
        "dismiss" -> Tracker.dismiss_alert(socket.assigns.alert_id, note, by)
      end

    case result do
      {:ok, %{decision: decision}} ->
        {:noreply, socket |> assign(last_decision: decision, note_form: note_form()) |> load()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :note_form, note_form(changeset))}

      {:error, :not_open} ->
        {:noreply, socket |> put_flash(:error, "This alert has already been decided.") |> load()}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "That alert no longer exists.")}
    end
  end

  def handle_event("undo", _params, %{assigns: %{last_decision: %{id: id}}} = socket) do
    case Tracker.undo_decision(id, socket.assigns.current_scope.user.email) do
      {:ok, _} ->
        {:noreply, socket |> assign(:last_decision, nil) |> load()}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:last_decision, nil)
         |> put_flash(:error, "That decision can no longer be undone.")
         |> load()}
    end
  end

  def handle_event("undo", _params, socket), do: {:noreply, socket}

  def handle_event("navigate", %{"to" => to}, %{assigns: %{neighbors: %{} = neighbors}} = socket) do
    case Map.get(neighbors, if(to == "prev", do: :prev, else: :next)) do
      nil -> {:noreply, socket}
      id -> {:noreply, push_navigate(socket, to: ~p"/alerts/#{id}?#{socket.assigns.query}")}
    end
  end

  def handle_event("navigate", _params, socket), do: {:noreply, socket}

  @doc false
  # Called by DripstoneWeb.Nav for every tracker change.
  def handle_tracker_event(_message, socket), do: load(socket)

  @impl true
  def render(%{detail: nil} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} nav={@nav} current_scope={@current_scope}>
      <.not_found title="Alert not found" back={~p"/alerts"} back_label="Back to alerts" />
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} nav={@nav} current_scope={@current_scope}>
      <div
        id="alert-shortcuts"
        phx-hook=".AlertShortcuts"
        data-open={to_string(@detail.alert.status == :open)}
        class="hidden"
      >
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".AlertShortcuts">
        // c / d decide, j / k move through the inbox. Ignored while typing in a field or
        // with a modifier key held, so typing "c" in the note never confirms.
        export default {
          mounted() {
            this.onKey = (event) => {
              if (event.defaultPrevented || event.repeat) return
              if (event.metaKey || event.ctrlKey || event.altKey) return
              const target = event.target
              if (target && target.closest && target.closest("input, textarea, select, [contenteditable='true']")) return

              const key = event.key.toLowerCase()
              if (key === "c" || key === "d") {
                if (this.el.dataset.open !== "true") return
                const note = document.getElementById("decision-note")
                this.pushEvent("decide", {
                  action: key === "c" ? "confirm" : "dismiss",
                  decision: {note: note ? note.value : ""}
                })
              } else if (key === "j" || key === "k") {
                // j is the left key (previous, ←), k the right key (next, →).
                this.pushEvent("navigate", {to: key === "j" ? "prev" : "next"})
              } else {
                return
              }
              event.preventDefault()
            }
            window.addEventListener("keydown", this.onKey)
          },
          destroyed() {
            window.removeEventListener("keydown", this.onKey)
          }
        }
      </script>

      <.page_header title={@detail.alert.title} back={~p"/alerts?#{@query}"} back_label="Alerts">
        <:meta>
          <.severity_badge severity={@detail.alert.severity} />
          <span class="text-ink">{trigger_name(@detail)}</span>
          <.status_pill status={@detail.alert.status} />
          <span>raised <.relative_time at={@detail.alert.raised_at} /></span>
          <.link
            :if={@detail.previously_dismissed}
            id="previously-dismissed"
            navigate={~p"/alerts/#{@detail.previously_dismissed.id}"}
            class="inline-flex items-center gap-1 text-status-suspected hover:underline"
          >
            <.icon name="hero-arrow-uturn-left-mini" class="size-4" /> Previously dismissed
          </.link>
        </:meta>
        <:actions>
          <nav
            id="alert-neighbors"
            class="flex items-center gap-1 text-sm"
            aria-label="Alerts in this list"
          >
            <.link
              :if={@neighbors.prev}
              id="prev-alert"
              navigate={~p"/alerts/#{@neighbors.prev}?#{@query}"}
              class="inline-flex items-center gap-1 rounded-lg px-2 py-1 text-ink-muted hover:bg-surface-raised hover:text-ink"
            >
              <.icon name="hero-chevron-left-mini" />
              <.kbd>j</.kbd>
            </.link>
            <span
              :if={@neighbors.position}
              id="alert-position"
              class="px-1 tabular-nums text-ink-muted"
            >
              {@neighbors.position} of {@neighbors.total}
            </span>
            <.link
              :if={@neighbors.next}
              id="next-alert"
              navigate={~p"/alerts/#{@neighbors.next}?#{@query}"}
              class="inline-flex items-center gap-1 rounded-lg px-2 py-1 text-ink-muted hover:bg-surface-raised hover:text-ink"
            >
              <.kbd>k</.kbd>
              <.icon name="hero-chevron-right-mini" />
            </.link>
          </nav>
        </:actions>
      </.page_header>

      <div class="grid grid-cols-1 gap-4 lg:grid-cols-3 lg:gap-6">
        <div class="space-y-4 lg:col-span-2 lg:space-y-6">
          <.card :if={@detail.alert.comparison} id="comparison" title="What changed">
            <dl class="grid gap-3 sm:grid-cols-2">
              <div class="rounded-lg border border-line bg-surface-raised p-3">
                <dt class="text-xs font-medium uppercase tracking-wide text-ink-faint">
                  Before · {@detail.alert.comparison.label}
                </dt>
                <dd id="comparison-before" class="mt-1 font-medium text-ink-muted">
                  {@detail.alert.comparison.before}
                </dd>
              </div>
              <div class="rounded-lg border border-accent/40 bg-accent-soft p-3">
                <dt class="text-xs font-medium uppercase tracking-wide text-accent-strong">
                  After · {@detail.alert.comparison.label}
                </dt>
                <dd id="comparison-after" class="mt-1 font-medium text-ink">
                  {@detail.alert.comparison.after}
                </dd>
              </div>
            </dl>
          </.card>

          <.card id="evidence" title="Evidence" padded={false}>
            <ol class="divide-y divide-line">
              <li
                :for={{item, i} <- Enum.with_index(@detail.alert.evidence)}
                id={"evidence-#{i}"}
                class="space-y-2 px-4 py-3"
              >
                <div class="flex items-start gap-3">
                  <.strength_badge strength={item.strength} class="mt-0.5" />
                  <p class="flex-1 text-sm text-ink">{item.explanation}</p>
                </div>
                <div
                  :if={item.account_ids != []}
                  class="flex flex-wrap items-center gap-1.5 pl-[5.5rem] text-xs"
                >
                  <span class="text-ink-faint">{length(item.account_ids)} accounts:</span>
                  <.link
                    :for={
                      account <-
                        Enum.take(item.account_ids, 6)
                        |> Enum.map(&Map.get(@detail.accounts, &1))
                        |> Enum.reject(&is_nil/1)
                    }
                    navigate={~p"/accounts/#{account.id}"}
                    class="rounded bg-surface-raised px-1.5 py-0.5 font-mono text-ink-muted hover:text-accent"
                  >
                    {format_handle(account)}
                  </.link>
                  <span :if={length(item.account_ids) > 6} class="text-ink-faint">
                    +{length(item.account_ids) - 6} more
                  </span>
                </div>
              </li>
            </ol>
          </.card>

          <.answers_panel
            :if={@detail.alert.finding_id}
            id="alert-answers"
            answers={@detail.alert.answers}
            model={@detail.alert.model}
            observed_at={@detail.alert.observed_at}
          />

          <.card id="ai-rationale">
            <%= if @detail.alert.ai_rationale do %>
              <.ai_label generated_at={@detail.alert.ai_rationale.generated_at} />
              <p class="mt-2 text-sm leading-relaxed text-ink">{@detail.alert.ai_rationale.text}</p>
            <% else %>
              <p id="no-rationale" class="text-sm text-ink-muted">
                No AI-written rationale is available. The decision model answers typed
                questions and doesn't write text.
              </p>
            <% end %>
          </.card>
        </div>

        <div class="space-y-4 lg:space-y-6">
          <.card id="network-card" title="Network">
            <.link
              navigate={~p"/networks/#{@detail.network.id}"}
              class="group inline-flex items-center gap-1 font-medium text-ink hover:text-accent"
            >
              {@detail.network.name}
              <.icon
                name="hero-arrow-right-mini"
                class="size-4 transition-transform group-hover:translate-x-0.5"
              />
            </.link>
            <div class="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-ink-muted">
              <.status_pill status={@detail.network.status} />
              <span class="tabular-nums">{@detail.network.confidence}% confidence</span>
              <span class="tabular-nums">{length(@detail.network.member_ids)} accounts</span>
            </div>
            <div class="mt-2 flex flex-wrap gap-1.5">
              <.platform_badge :for={feed <- @detail.network.platforms} feed_id={feed} />
            </div>
            <p :if={@detail.network.main_domain} class="mt-2 text-xs text-ink-faint">
              Main domain <span class="font-mono text-ink-muted">{@detail.network.main_domain}</span>
            </p>
          </.card>

          <.card :if={@detail.alert.status == :open} id="decision-panel" title="Your decision">
            <.form for={@note_form} id="decision-form" phx-change="validate_note" phx-submit="decide">
              <.input
                field={@note_form[:note]}
                id="decision-note"
                type="textarea"
                label="Note (optional)"
                rows="3"
                maxlength="600"
                placeholder="Why? e.g. same copy across every account"
              />
              <p class="-mt-1 mb-3 text-right text-xs tabular-nums text-ink-faint">
                {String.length(@note_form[:note].value || "")}/500
              </p>
              <div class="grid grid-cols-2 gap-2">
                <.button
                  id="confirm-alert"
                  type="submit"
                  name="action"
                  value="confirm"
                  variant="primary"
                >
                  <.icon name="hero-check-mini" class="size-4" /> Confirm
                  <.kbd class="border-accent-ink/30 bg-accent-ink/15 text-accent-ink">c</.kbd>
                </.button>
                <.button
                  id="dismiss-alert"
                  type="submit"
                  name="action"
                  value="dismiss"
                >
                  <.icon name="hero-x-mark-mini" class="size-4" /> Dismiss
                  <.kbd>d</.kbd>
                </.button>
              </div>
              <p class="mt-3 text-xs text-ink-faint">
                Confirm marks the network as a bot farm. Dismiss records a false positive; new evidence can still re-alert it.
              </p>
            </.form>
          </.card>

          <.card
            :if={@detail.alert.status != :open && @detail.decision}
            id="decision-made"
            title="Decision"
          >
            <p class="flex items-center gap-2 text-sm font-medium text-ink">
              <.icon
                name={
                  if @detail.decision.action == :confirm,
                    do: "hero-check-circle",
                    else: "hero-x-circle"
                }
                class={[
                  "size-5",
                  if(@detail.decision.action == :confirm,
                    do: "text-status-confirmed",
                    else: "text-status-dismissed"
                  )
                ]}
              />
              {if @detail.decision.action == :confirm, do: "Confirmed", else: "Dismissed"}
            </p>
            <p class="mt-1 text-xs text-ink-muted">
              by {@detail.decision.by} · <.relative_time at={@detail.decision.at} />
            </p>
            <blockquote
              :if={@detail.decision.note}
              id="decision-note-text"
              class="mt-3 border-l-2 border-line pl-3 text-sm text-ink-muted"
            >
              {@detail.decision.note}
            </blockquote>
            <div
              :if={@last_decision && @last_decision.id == @detail.decision.id}
              class="mt-4 flex items-center gap-2"
            >
              <.button id="undo-decision" phx-click="undo" size="sm">
                <.icon name="hero-arrow-uturn-left-mini" class="size-4" /> Undo
              </.button>
              <.button
                :if={@neighbors.next}
                navigate={~p"/alerts/#{@neighbors.next}?#{@query}"}
                size="sm"
                variant="ghost"
              >
                Next alert <.icon name="hero-arrow-right-mini" class="size-4" />
              </.button>
            </div>
          </.card>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :class, :any, default: nil
  slot :inner_block, required: true

  defp kbd(assigns) do
    ~H"""
    <kbd class={[
      "inline-flex h-5 min-w-5 items-center justify-center rounded border border-line bg-surface-raised px-1 font-mono text-[11px] font-medium text-ink-muted",
      @class
    ]}>{render_slot(@inner_block)}</kbd>
    """
  end
end
