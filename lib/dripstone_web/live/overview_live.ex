defmodule DripstoneWeb.OverviewLive do
  @moduledoc "Overview screen. Placeholder until its task group lands (see openspec tasks.md)."
  use DripstoneWeb, :live_view

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, :page_title, "Overview")}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} nav={@nav}>
      <.page_header title="Overview">
        <:subtitle>What needs attention, and what Dripstone is tracking.</:subtitle>
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
