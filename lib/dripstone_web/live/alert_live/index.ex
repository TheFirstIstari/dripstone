defmodule DripstoneWeb.AlertLive.Index do
  @moduledoc "Alerts inbox screen. Placeholder until its task group lands (see openspec tasks.md)."
  use DripstoneWeb, :live_view

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, :page_title, "Alerts")}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} nav={@nav}>
      <.page_header title="Alerts">
        <:subtitle>Alerts raised by detection, waiting for a decision.</:subtitle>
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
