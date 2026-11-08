defmodule Dripstone.Workers.DiscoverWorker do
  @moduledoc """
  Assesses one live-discovery candidate group: accounts that posted the same link
  within a short window (see `Dripstone.Discovery.Bursts`). Args:
  `%{"platform" => "bluesky" | "mastodon", "url" => ..., "domain" => ..., "dids" => [...]}`.
  `dids` are Bluesky DIDs or Mastodon `user@instance` handles; `platform` defaults
  to Bluesky.

  1. Checks the caps (`Dripstone.Discovery.Caps`): groups per hour, and accounts
     already assessed recently are left out.
  2. Resolves the DIDs to handles and trims to `max_group_size`.
  3. Fetches each member's recent posts (`Adapters.Bluesky`, via the politeness
     layer). Members that can't be fetched are left out.
  4. Builds an account finding per member (`Scorer.assess/2`) and, with at least
     two members, a group finding (`Scorer.assess_group/2`) whose heuristics carry
     the members' link-domain shares.
  5. Reports them in **one** write (`Tracker.report_findings/1`), into Live.

  Runs once (no retries, so AI calls aren't repeated). It is unique per URL for the
  burst cooldown, so the same link isn't assessed twice.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [period: 6 * 60 * 60, keys: [:url, :platform]]

  require Logger

  alias Dripstone.{Scorer, Tracker}
  alias Dripstone.Adapters.{Bluesky, Mastodon}
  alias Dripstone.Discovery.{Bursts, Caps}

  @default_max_group_size 10

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"dids" => dids} = args}) when is_list(dids) do
    case Caps.take_group() do
      :over_cap ->
        Logger.info("Discovery skipped a candidate (#{args["url"]}): hourly cap reached")
        :ok

      :ok ->
        assess(args, Map.get(args, "platform", "bluesky"), dids)
    end
  end

  defp assess(args, platform, dids) do
    dids =
      dids
      |> Enum.map(&"#{platform}:#{&1}")
      |> Caps.fresh()
      |> Enum.map(&String.replace_prefix(&1, "#{platform}:", ""))
      |> Enum.take(config(:max_group_size, @default_max_group_size))

    with true <- dids != [] || :nothing_new,
         members when members != [] <- members(platform, dids) do
      findings =
        Enum.map(members, &account_finding(&1, platform)) ++ group_finding(members, platform)

      case Tracker.report_findings(findings) do
        {:ok, results} ->
          alerts = for %{alerts: alerts} <- results, %{alert: a} <- alerts, do: a.trigger_id

          Logger.info(
            "Discovery assessed #{length(members)} accounts for #{args["url"]}; alerts: #{inspect(alerts)}"
          )

          :ok

        {:error, reason} ->
          {:error, reason}
      end
    else
      :nothing_new -> :ok
      [] -> :ok
    end
  end

  # Bluesky ids are DIDs, resolved to handles in one call; Mastodon ids are
  # already `user@instance` handles. Accounts that can't be fetched are left out.
  defp members("bluesky", dids) do
    case Bluesky.profiles(dids, http_opts()) do
      {:ok, profiles} ->
        fetch_members(profiles)

      {:error, reason} ->
        Logger.warning("Discovery profile lookup failed: #{inspect(reason)}") && []
    end
  end

  defp members("mastodon", accts) do
    Enum.flat_map(accts, fn acct ->
      case Mastodon.fetch_posts(acct, http_opts()) do
        {:ok, posts} -> [%{did: acct, handle: acct, posts: posts}]
        {:error, _reason} -> []
      end
    end)
  end

  defp members(_platform, _ids), do: []

  defp fetch_members(profiles) do
    Enum.flat_map(profiles, fn %{did: did, handle: handle} ->
      case Bluesky.fetch_posts(handle, http_opts()) do
        {:ok, posts} -> [%{did: did, handle: handle, posts: posts}]
        {:error, _reason} -> []
      end
    end)
  end

  defp account_finding(member, platform) do
    assessment = Scorer.assess(member.posts, ai_opts())

    %{
      kind: "account",
      observed_at: DateTime.utc_now(),
      model: model(assessment),
      account: ref(member, platform),
      posts: member.posts,
      heuristics: %{score: assessment.score, labels: assessment.labels},
      answers: assessment.ai_answers
    }
  end

  defp group_finding(members, _platform) when length(members) < 2, do: []

  defp group_finding(members, platform) do
    scorer_members = Enum.map(members, &%{feed_id: platform, handle: &1.handle, posts: &1.posts})
    assessment = Scorer.assess_group(scorer_members, ai_opts())

    [
      %{
        kind: "group",
        observed_at: DateTime.utc_now(),
        model: model(assessment),
        accounts: Enum.map(members, &ref(&1, platform)),
        heuristics: %{domains: domains(members)},
        answers: assessment.ai_answers
      }
    ]
  end

  # Each domain's share of the members' posts that carry a link (top five).
  defp domains(members) do
    linked =
      for m <- members, post <- m.posts, post.urls != [] do
        post.urls
        |> Enum.find_value(fn url ->
          case Bursts.normalize(url) do
            {:ok, _link, domain} -> domain
            :error -> nil
          end
        end)
      end
      |> Enum.reject(&is_nil/1)

    total = length(linked)

    linked
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_d, n} -> -n end)
    |> Enum.take(5)
    |> Enum.map(fn {domain, n} -> %{domain: domain, share: n / total} end)
  end

  defp ref(member, platform),
    do: %{feed_id: platform, handle: member.handle, external_id: member.did}

  defp model(%{ai_answers: nil}), do: nil

  defp model(_assessment),
    do: :dripstone |> Application.get_env(Dripstone.AIClient, []) |> Keyword.get(:model)

  defp config(key, default),
    do: :dripstone |> Application.get_env(__MODULE__, []) |> Keyword.get(key, default)

  # Tests inject Req.Test plugs through config; production uses neither.
  defp http_opts, do: config(:http_opts, [])
  defp ai_opts, do: config(:ai_opts, [])
end
