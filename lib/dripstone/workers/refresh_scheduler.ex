defmodule Dripstone.Workers.RefreshScheduler do
  @moduledoc """
  Hourly fan-out: enqueues one `RefreshWorker` per tracked account so corpora
  stay fresh and `AssessWorker` keeps seeing new activity.

  Accounts in Cleared networks (every network dismissed) are skipped until
  new activity reopens them — fresh findings reopen dismissed networks via
  the intake, and `mix dripstone.datasets.refresh` still captures them
  manually. Unknown feeds are skipped.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Dripstone.Tracker
  alias Dripstone.Workers.RefreshWorker

  @adapters %{"x" => "stub_x", "reddit" => "stub_reddit"}

  @impl Oban.Worker
  def perform(_job) do
    %{total: total, pages: pages} = Tracker.list_accounts(%{})

    if total == 0 do
      :ok
    else
      Enum.each(1..pages, &enqueue_page/1)
      :ok
    end
  end

  defp enqueue_page(page) do
    %{entries: entries} = Tracker.list_accounts(%{page: page})

    for %{account: account, networks: networks} <- entries,
        adapter = Map.get(@adapters, account.feed_id),
        not is_nil(adapter),
        not cleared?(networks) do
      %{"adapter" => adapter, "feed" => account.feed_id, "handle" => account.handle}
      |> RefreshWorker.new()
      |> Oban.insert()
    end
  end

  defp cleared?([]), do: false
  defp cleared?(networks), do: Enum.all?(networks, &(&1.status == :dismissed))
end
