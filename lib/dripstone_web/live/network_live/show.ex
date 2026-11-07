defmodule DripstoneWeb.NetworkLive.Show do
  @moduledoc "Network detail screen. Placeholder until group 8 (see openspec tasks.md)."
  use DripstoneWeb, :live_view

  alias Dripstone.Tracker

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Tracker.get_network(id) do
      nil ->
        {:ok, assign(socket, detail: nil, page_title: "Network not found")}

      detail ->
        {:ok, assign(socket, detail: detail, page_title: detail.network.name)}
    end
  end

  @impl true
  def render(%{detail: nil} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} nav={@nav}>
      <.not_found title="Network not found" back={~p"/networks"} back_label="Back to networks" />
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} nav={@nav}>
      <.page_header title={@detail.network.name} back={~p"/networks"} back_label="Networks">
        <:meta><.status_pill status={@detail.network.status} /></:meta>
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
