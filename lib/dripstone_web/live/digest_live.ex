defmodule DripstoneWeb.DigestLive do
  @moduledoc """
  The weekly change digest: important new edges, flipped labels and re-alerts
  since the cutoff, newest first. Live-updates on tracker changes. Low-importance
  changes stay silent (same high-severity rule as alert toasts) and never appear.
  """
  use DripstoneWeb, :live_view

  alias Dripstone.Tracker

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Digest")
     |> stream_configure(:items,
       dom_id: &"digest-#{&1.kind}-#{&1.network_id}-#{&1.id}"
     )
     |> load()}
  end

  @doc false
  # Only history/digest-relevant events re-run the digest: decisions (flips),
  # new-edge findings (intake) and re-alerts. Feed ticks and unrelated
  # account updates stay silent instead of resetting scroll (#248).
  def handle_tracker_event({event, _} = message, socket)
      when event in [:alert_raised, :alert_updated, :network_updated] do
    if digest_relevant?(message), do: load(socket), else: socket
  end

  def handle_tracker_event(_message, socket), do: socket

  # Decisions record "Confirmed/Dismissed alert …"; intake records new edges
  # ("Added …", "Detected with …", "New evidence on …") or re-alerts. Other
  # network updates (curation moves, feed ticks) leave the digest alone.
  defp digest_relevant?({:alert_raised, _}), do: true
  defp digest_relevant?({:alert_updated, _}), do: true
  defp digest_relevant?({:network_updated, id}), do: digest_network_relevant?(id)

  defp digest_network_relevant?(id) do
    {:ok, state} = Dripstone.Tracker.Store.load()
    Enum.any?(state.history, &(&1.network_id == id and digest_entry?(&1.summary)))
  rescue
    _ -> true
  end

  defp digest_entry?(summary) when is_binary(summary) do
    String.starts_with?(summary, [
      "Added ",
      "Detected with ",
      "New evidence on ",
      "Confirmed alert ",
      "Dismissed alert ",
      "Re-alerted after dismissal"
    ])
  end

  defp load(socket), do: stream(socket, :items, Tracker.change_digest(), reset: true)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} nav={@nav} current_scope={@current_scope}>
      <.page_header title="Change digest">
        <:subtitle>Important changes in the last 7 days. Quieter updates stay silent.</:subtitle>
      </.page_header>

      <.card padded={false}>
        <ol id="digest" phx-update="stream" class="divide-y divide-line px-4">
          <li
            id="digest-empty"
            class="hidden only:block py-6 text-center text-sm text-ink-muted"
          >
            No important changes in the last 7 days.
          </li>
          <li
            :for={{dom_id, item} <- @streams.items}
            id={dom_id}
            class="flex items-start gap-3 py-3"
          >
            <.severity_badge severity={item.severity} />
            <div class="min-w-0 flex-1 text-sm">
              <p class="text-ink">
                <.link
                  navigate={~p"/networks/#{item.network_id}"}
                  class="font-medium hover:text-accent"
                >
                  {item.summary}
                </.link>
              </p>
              <p class="mt-0.5 text-xs capitalize text-ink-faint">
                {label(item.kind)} · <.relative_time at={item.at} />
              </p>
            </div>
          </li>
        </ol>
      </.card>
    </Layouts.app>
    """
  end

  defp label(:new_edge), do: "new edge"
  defp label(:flipped_label), do: "flipped label"
  defp label(:re_alert), do: "re-alert"
end
