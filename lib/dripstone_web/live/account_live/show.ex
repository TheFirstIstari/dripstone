defmodule DripstoneWeb.AccountLive.Show do
  @moduledoc "Account detail screen. Placeholder until group 9 (see openspec tasks.md)."
  use DripstoneWeb, :live_view

  alias Dripstone.Feeds
  alias Dripstone.Tracker

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Tracker.get_account(id) do
      nil ->
        {:ok, assign(socket, detail: nil, page_title: "Account not found")}

      detail ->
        {:ok, assign(socket, detail: detail, page_title: handle(detail.account))}
    end
  end

  @impl true
  def render(%{detail: nil} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} nav={@nav}>
      <.not_found title="Account not found" back={~p"/accounts"} back_label="Back to accounts" />
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} nav={@nav}>
      <.page_header title={handle(@detail.account)} back={~p"/accounts"} back_label="Accounts">
        <:meta>
          <.platform_badge feed_id={@detail.account.feed_id} />
          <.risk_badge score={@detail.account.risk_score} />
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

  defp handle(account) do
    case Feeds.get(account.feed_id) do
      nil -> account.handle
      feed -> feed.format_handle(account)
    end
  end
end
