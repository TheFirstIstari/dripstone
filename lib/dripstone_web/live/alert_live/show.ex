defmodule DripstoneWeb.AlertLive.Show do
  @moduledoc "Alert detail screen. Placeholder until group 7 (see openspec tasks.md)."
  use DripstoneWeb, :live_view

  alias Dripstone.Tracker

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Tracker.get_alert(id) do
      nil ->
        {:ok, assign(socket, detail: nil, page_title: "Alert not found")}

      detail ->
        {:ok, assign(socket, detail: detail, page_title: detail.alert.title)}
    end
  end

  @impl true
  def render(%{detail: nil} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} nav={@nav}>
      <.not_found title="Alert not found" back={~p"/alerts"} back_label="Back to alerts" />
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} nav={@nav}>
      <.page_header title={@detail.alert.title} back={~p"/alerts"} back_label="Alerts">
        <:meta>
          <.severity_badge severity={@detail.alert.severity} />
          <.status_pill status={@detail.alert.status} />
        </:meta>
      </.page_header>
      <.card>
        <.empty_state
          id="screen-placeholder"
          icon="hero-wrench-screwdriver"
          title="This screen is being built"
        />
      </.card>
    </Layouts.app>
    """
  end
end
