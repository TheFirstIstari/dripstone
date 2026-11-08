defmodule Dripstone.Workers.TrendWorker do
  @moduledoc """
  Trend re-checks for live networks (live-discovery "Trend re-checks"). It runs on
  Oban Cron every 6 hours. For each Live network whose members posted within the
  last day, it asks the decision model about the trend (`Scorer.assess_trend/2`)
  over the members' recent stored posts, and reports a trend finding. The Rules
  raise Network reactivation or Coordination rising when the trajectory calls for
  it.

  At most `max_networks` networks per run, most recently active first. All
  findings go in **one** write (`Tracker.report_findings/1`). Live only.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  require Logger

  alias Dripstone.{Scorer, Tracker}
  alias Dripstone.Tracker.Store

  @active_within_s 24 * 60 * 60
  @default_max_networks 10
  @posts_per_member 20

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    {:ok, state} = Store.load()
    since = DateTime.add(DateTime.utc_now(), -@active_within_s, :second)

    findings =
      state.networks
      |> Map.values()
      |> Enum.filter(&is_nil(&1.retired_into))
      |> Enum.map(&{&1, member_posts(state, &1)})
      |> Enum.map(fn {network, posts} -> {network, posts, latest(posts)} end)
      |> Enum.filter(fn {_n, _posts, latest} -> latest && DateTime.after?(latest, since) end)
      |> Enum.sort_by(fn {_n, _posts, latest} -> latest end, {:desc, DateTime})
      |> Enum.take(config(:max_networks, @default_max_networks))
      |> Enum.map(fn {network, posts, _latest} -> trend_finding(network, posts) end)

    case findings do
      [] ->
        :ok

      _ ->
        with {:ok, results} <- Tracker.report_findings(findings) do
          alerts = for %{alerts: alerts} <- results, %{alert: a} <- alerts, do: a.trigger_id
          Logger.info("Trend re-check of #{length(findings)} networks; alerts: #{inspect(alerts)}")
          :ok
        end
    end
  end

  defp member_posts(state, network) do
    Enum.flat_map(network.member_ids, fn id ->
      account = state.accounts[id]

      state.posts
      |> Map.get(id, [])
      |> Enum.filter(& &1.posted_at)
      |> Enum.take(@posts_per_member)
      |> Enum.map(fn post ->
        %{
          id: post.post_id,
          handle: account && account.handle,
          text: post.text || "",
          urls: if(post.domain, do: ["https://#{post.domain}/"], else: []),
          published_at: post.posted_at
        }
      end)
    end)
  end

  defp latest([]), do: nil
  defp latest(posts), do: posts |> Enum.map(& &1.published_at) |> Enum.max(DateTime)

  defp trend_finding(network, posts) do
    assessment = Scorer.assess_trend(posts, config(:ai_opts, []))
    times = Enum.map(posts, & &1.published_at)

    %{
      kind: "trend",
      observed_at: DateTime.utc_now(),
      model:
        if(assessment.ai_answers,
          do: :dripstone |> Application.get_env(Dripstone.AIClient, []) |> Keyword.get(:model)
        ),
      network_id: network.id,
      window: %{from: Enum.min(times, DateTime), to: Enum.max(times, DateTime)},
      answers: assessment.ai_answers
    }
  end

  defp config(key, default),
    do: :dripstone |> Application.get_env(__MODULE__, []) |> Keyword.get(key, default)
end
