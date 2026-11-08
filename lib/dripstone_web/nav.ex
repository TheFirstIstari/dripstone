defmodule DripstoneWeb.Nav do
  @moduledoc """
  `on_mount` hook for every tracker LiveView (`live_session :tracker`).

  Assigns `@nav` for `Layouts.app/1`: the active section, the open alert count and
  live toasts. It subscribes to tracker changes once per LiveView and keeps `@nav`
  current:

    * `{:alert_raised, alert}`: recount open alerts; toast if severity is High
    * `{:alert_updated, alert}`: recount open alerts
    * `{:network_updated, id}`: nothing for the nav
    * `{:account_updated, id}`: nothing for the nav

  After that, the message is passed to the LiveView's optional
  `handle_tracker_event(message, socket) :: socket` callback, so a screen that wants
  live updates implements just that (and doesn't subscribe itself). Screens without
  the callback never see tracker messages.

  It also handles the shell's own events: `global_search` (top bar) and
  `dismiss_toast`.
  """
  use DripstoneWeb, :verified_routes

  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3, update: 3]

  alias Dripstone.Tracker

  @max_toasts 3

  @sections %{
    DripstoneWeb.OverviewLive => :overview,
    DripstoneWeb.AlertLive.Index => :alerts,
    DripstoneWeb.AlertLive.Show => :alerts,
    DripstoneWeb.NetworkLive.Index => :networks,
    DripstoneWeb.NetworkLive.Show => :networks,
    DripstoneWeb.AccountLive.Index => :accounts,
    DripstoneWeb.AccountLive.Show => :accounts,
    DripstoneWeb.DigestLive => :digest,
    DripstoneWeb.FeedLive.Index => :feeds
  }

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket), do: Tracker.subscribe()

    user = socket.assigns[:current_scope] && socket.assigns.current_scope.user
    # Anonymous visitors never see the badge, so skip the per-mount count.
    nav = %{active: Map.get(@sections, socket.view), open_alerts: open_alerts(user), toasts: []}

    {:cont,
     socket
     |> assign(:nav, nav)
     |> attach_hook(:nav_tracker, :handle_info, &handle_info/2)
     |> attach_hook(:nav_events, :handle_event, &handle_event/3)}
  end

  defp handle_info({:alert_raised, alert} = message, socket) do
    socket
    |> recount()
    |> toast(alert)
    |> forward(message)
  end

  defp handle_info({:alert_updated, _alert} = message, socket),
    do: socket |> recount() |> forward(message)

  defp handle_info({:network_updated, _id} = message, socket), do: forward(socket, message)
  defp handle_info({:account_updated, _id} = message, socket), do: forward(socket, message)
  defp handle_info(_message, socket), do: {:cont, socket}

  defp handle_event("global_search", params, socket) do
    path =
      case params |> Map.get("q", "") |> String.trim() do
        "" -> ~p"/accounts"
        q -> ~p"/accounts?#{%{q: q}}"
      end

    {:halt, push_navigate(socket, to: path)}
  end

  defp handle_event("dismiss_toast", %{"id" => id}, socket),
    do:
      {:halt,
       update(socket, :nav, fn nav -> %{nav | toasts: Enum.reject(nav.toasts, &(&1.id == id))} end)}

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  defp forward(socket, message) do
    socket =
      if function_exported?(socket.view, :handle_tracker_event, 2),
        do: socket.view.handle_tracker_event(message, socket),
        else: socket

    {:halt, socket}
  end

  defp recount(socket) do
    user = socket.assigns[:current_scope] && socket.assigns.current_scope.user
    update(socket, :nav, &%{&1 | open_alerts: open_alerts(user)})
  end

  defp toast(socket, %{severity: :high, status: :open} = alert) do
    entry = %{id: alert.id, alert_id: alert.id, title: alert.title, severity: alert.severity}

    update(socket, :nav, fn nav ->
      %{
        nav
        | toasts:
            [entry | Enum.reject(nav.toasts, &(&1.id == alert.id))] |> Enum.take(@max_toasts)
      }
    end)
  end

  defp toast(socket, _alert), do: socket

  defp open_alerts(nil), do: 0
  defp open_alerts(_user), do: Tracker.count_alerts(%{status: :open})
end
