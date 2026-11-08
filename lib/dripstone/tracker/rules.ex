defmodule Dripstone.Tracker.Rules do
  @moduledoc """
  The app's alert rules: turns a validated `Dripstone.Tracker.Report` (an account,
  group or trend finding) into state changes and internal findings, which go through
  `Dripstone.Tracker.Intake` unchanged (de-duplication, re-alerting after dismissal,
  respecting analyst changes). Pure: `run/3` takes a state and returns a new one.

    * **Account** findings create or update the account (risk score, signals,
      topic, posts) and raise no alert.
    * **Group** findings link the members (link type = the `relation` answer) and
      raise `New network` or `Network growth` when `coordinated` is at or above the
      yes threshold, plus `Promotion shift` when a known network's top domain
      changes (heuristics only).
    * **Trend** findings raise `Network reactivation` or `Coordination rising`.

  Severity, evidence strength and evidence text come from the answers, using the
  thresholds in `config :dripstone, Dripstone.Tracker.Rules` (see `config/0`).
  """

  alias Dripstone.Feeds
  alias Dripstone.Tracker.{Account, Answers, Intake, Link, Post, Report, Signal, State}

  @defaults [
    yes: 0.7,
    severity: [high: 0.9, medium: 0.8],
    strength: [strong: 0.85, moderate: 0.7],
    posts_per_account: 200,
    provenance_per_link: 20,
    findings_log: 500
  ]

  @strengths %{"strong" => :strong, "moderate" => :moderate, "weak" => :weak}

  @heuristic_labels %{
    "high_volume" =>
      {"High volume", "Posted at least 20 times in the assessed window (heuristic)."},
    "high_link_ratio" =>
      {"High link ratio", "More than half of the assessed posts carry links (heuristic)."},
    "regular_timing" =>
      {"Regular timing", "Posts arrive at machine-like regular intervals (heuristic)."}
  }

  @type result :: %{
          kind: :account | :group | :trend,
          finding_id: String.t(),
          alerts: [%{action: :created | :merged, alert: map()}],
          network_id: String.t() | nil,
          account_ids: [String.t()],
          skipped: [map()],
          reason: atom() | nil
        }

  @doc "The rule thresholds and caps: the configured values over the defaults."
  @spec config() :: keyword()
  def config,
    do: Keyword.merge(@defaults, Application.get_env(:dripstone, __MODULE__, []))

  @doc "Applies a report. Returns the result and the new state, or intake errors."
  @spec run(State.t(), Report.t(), DateTime.t()) ::
          {:ok, result(), State.t()} | {:error, %{atom() => [String.t()]}}
  def run(%State{} = state, %Report{} = report, %DateTime{} = now) do
    {finding_id, state} = State.next_id(state, "finding")

    ctx = %{
      id: finding_id,
      report: report,
      now: DateTime.truncate(now, :second),
      cfg: config()
    }

    state = log_finding(state, ctx)

    case report.kind do
      :account -> account(state, ctx)
      :group -> group(state, ctx)
      :trend -> trend(state, ctx)
    end
  end

  ## Account findings

  defp account(state, %{report: report} = ctx) do
    {account, state} = ensure_account(state, report.account, ctx.now)
    {posts, state} = merge_posts(state, account.id, report.posts, ctx.cfg[:posts_per_account])
    answers = report.answers

    topic =
      case Answers.choice(answers, "topic") do
        {label, _confidence} -> label
        nil -> account.topic
      end

    account = %{
      account
      | risk_score: risk(report.heuristics.score, account.risk_score),
        signals: heuristic_signals(report.heuristics.labels) ++ answer_signals(answers),
        topic: topic,
        last_seen_at: newest(posts) || account.last_seen_at || report.observed_at,
        assessment: %{answers: answers, model: report.model, observed_at: report.observed_at}
    }

    state =
      state
      |> State.put_account(account)
      |> Map.update!(:posts, &Map.put(&1, account.id, posts))

    {:ok, result(ctx, alerts: [], account_ids: [account.id]), state}
  end

  defp risk(nil, current), do: current
  defp risk(score, _current), do: score |> round() |> max(0) |> min(100)

  defp heuristic_signals(labels) do
    Enum.map(labels, fn label ->
      {name, explanation} =
        Map.get(@heuristic_labels, label, {humanize(label), "Heuristic label: #{label}."})

      %Signal{name: name, explanation: explanation}
    end)
  end

  defp answer_signals(nil), do: []

  defp answer_signals(answers) do
    [
      {"is_bot", "Bot-like", "Jev's probability that this account is automated."},
      {"spam", "Spam", "How spammy Jev rates the assessed posts."},
      {"topic", "Topic", "The topic Jev picked for the assessed posts."}
    ]
    |> Enum.flat_map(fn {question, name, explanation} ->
      case answers[question] do
        nil -> []
        %{type: :other} -> []
        answer -> [%Signal{name: name, explanation: explanation, value: Answers.display(answer)}]
      end
    end)
  end

  defp humanize(label), do: label |> String.replace("_", " ") |> String.capitalize()

  ## Group findings

  defp group(state, %{report: report, cfg: cfg} = ctx) do
    {ids, state} =
      Enum.map_reduce(report.accounts, state, fn ref, state ->
        {account, state} = ensure_account(state, ref, ctx.now)
        {account.id, state}
      end)

    answers = report.answers
    coordinated = Answers.noul(answers, "coordinated")
    members = members(Enum.zip(report.accounts, ids), answers, cfg[:yes])
    target = report.network_id || majority_network(state, members)
    coordinated? = is_number(coordinated) and coordinated >= cfg[:yes] and length(members) >= 2

    state = if coordinated?, do: upsert_links(state, members, coordinated, ctx), else: state

    with {:ok, state, alerts, skipped, network_id, ignored} <-
           group_alerts(state, target, members, coordinated, coordinated?, ctx),
         {:ok, state, shift, shift_ignored} <- promotion_shift(state, network_id, members, ctx) do
      alerts = alerts ++ shift

      reason =
        cond do
          alerts != [] -> nil
          ignored || shift_ignored -> ignored || shift_ignored
          is_nil(answers) -> :no_answers
          not coordinated? -> :below_threshold
          true -> nil
        end

      {:ok,
       result(ctx,
         alerts: alerts,
         network_id: network_id,
         account_ids: ids,
         skipped: skipped,
         reason: reason
       ), state}
    end
  end

  # Accounts whose `member:<feed>:<handle>` answer is below the yes threshold are
  # left out. Accounts without one stay in.
  defp members(refs_and_ids, answers, yes) do
    refs_and_ids
    |> Enum.filter(fn {ref, _id} ->
      p = Answers.noul(answers, "member:#{ref.feed_id}:#{ref.handle}")
      is_nil(p) or p >= yes
    end)
    |> Enum.map(fn {_ref, id} -> id end)
    |> Enum.uniq()
  end

  # The live network holding more than half of the members, if any.
  defp majority_network(_state, []), do: nil

  defp majority_network(state, members) do
    member_set = MapSet.new(members)

    state.networks
    |> Map.values()
    |> Enum.filter(&is_nil(&1.retired_into))
    |> Enum.map(fn n -> {n.id, Enum.count(n.member_ids, &(&1 in member_set))} end)
    |> Enum.filter(fn {_id, count} -> count * 2 > length(members) end)
    |> Enum.max_by(fn {_id, count} -> count end, fn -> {nil, 0} end)
    |> elem(0)
  end

  # Not coordinated: record the assessment on a known network, raise nothing.
  defp group_alerts(state, target, _members, coordinated, false, ctx) do
    state = if target, do: put_group_assessment(state, target, coordinated, ctx), else: state
    {:ok, state, [], [], target, nil}
  end

  defp group_alerts(state, nil, members, coordinated, true, ctx) do
    {network_id, state} = State.next_id(state, "net")
    name = placeholder_name(state, members)
    top = top_domain(ctx.report.heuristics.domains)

    finding = %{
      trigger: "new_network",
      severity: severity(coordinated, ctx.cfg),
      title: "New network: #{name}",
      observed_at: ctx.report.observed_at,
      new_network: %{
        id: network_id,
        name: name,
        member_ids: members,
        confidence: percent(coordinated),
        platforms: feed_ids(state, members),
        main_domain: top && top.domain
      },
      evidence: group_evidence(members, coordinated, ctx)
    }

    with {:ok, state, alerts, skipped, ignored} <- intake(state, finding, ctx) do
      {:ok, put_group_assessment(state, network_id, coordinated, ctx), alerts, skipped,
       network_id, ignored}
    end
  end

  defp group_alerts(state, target, members, coordinated, true, ctx) do
    network = Map.fetch!(state.networks, target)
    new_ids = Enum.reject(members, &(&1 in network.member_ids))
    {removed, added} = Enum.split_with(new_ids, &(&1 in network.removed_account_ids))
    skipped = Enum.map(removed, &%{account_id: &1, reason: :removed_by_analyst})

    state =
      update_network(state, target, &%{&1 | confidence: percent(coordinated)})
      |> put_group_assessment(target, coordinated, ctx)

    case added do
      [] ->
        {:ok, state, [], skipped, target, nil}

      _ ->
        before = length(network.member_ids)

        finding = %{
          trigger: "network_growth",
          severity: severity(coordinated, ctx.cfg),
          title: "#{network.name} gained #{accounts_text(length(added))}",
          observed_at: ctx.report.observed_at,
          network_id: target,
          network_updates: %{add_member_ids: added},
          comparison: %{
            label: "Members",
            before: Integer.to_string(before),
            after: Integer.to_string(before + length(added))
          },
          evidence: growth_evidence(added, coordinated, ctx) ++ relation_evidence(added, ctx)
        }

        with {:ok, state, alerts, intake_skipped, ignored} <- intake(state, finding, ctx) do
          {:ok, state, alerts, skipped ++ intake_skipped, target, ignored}
        end
    end
  end

  # A known network whose top domain (at least half the links) changed. No AI needed.
  defp promotion_shift(state, nil, _members, _ctx), do: {:ok, state, [], nil}

  defp promotion_shift(state, network_id, members, ctx) do
    network = Map.fetch!(state.networks, network_id)

    # A network created by this finding already took the top domain as its main
    # domain, so it never shifts here.
    case top_domain(ctx.report.heuristics.domains) do
      %{domain: domain, share: share} when domain != network.main_domain ->
        shift(state, network, members, domain, share, ctx)

      _ ->
        {:ok, state, [], nil}
    end
  end

  defp shift(state, network, members, domain, share, ctx) do
    coordinated = network.assessment && network.assessment[:coordinated]

    finding = %{
      trigger: "promotion_shift",
      severity: if(coordinated, do: severity(coordinated, ctx.cfg), else: "medium"),
      title: "#{network.name} switched to promoting #{domain}",
      observed_at: ctx.report.observed_at,
      network_id: network.id,
      network_updates: %{main_domain: domain},
      comparison: %{
        label: "Main promoted domain",
        before: network.main_domain || "none",
        after: "#{domain} (#{percent(share)}%)"
      },
      evidence: [
        %{
          explanation: "#{percent(share)}% of the group's links point to #{domain}.",
          strength: strength(share, ctx.cfg),
          kind: "shared_link",
          account_ids: members
        }
      ]
    }

    with {:ok, state, alerts, _skipped, ignored} <- intake(state, finding, ctx) do
      {:ok, state, alerts, ignored}
    end
  end

  defp top_domain(domains) do
    case Enum.max_by(domains, & &1.share, fn -> nil end) do
      %{share: share} = top when share >= 0.5 -> top
      _ -> nil
    end
  end

  defp put_group_assessment(state, network_id, coordinated, %{report: report}) do
    {kind, label, confidence} = Answers.relation(report.answers) || {nil, nil, nil}

    update_assessment(state, network_id, %{
      coordinated: coordinated,
      relation: if(kind, do: label),
      relation_confidence: if(kind, do: confidence),
      group_observed_at: report.observed_at,
      model: report.model
    })
  end

  defp placeholder_name(state, members) do
    feeds =
      state
      |> feed_ids(members)
      |> Enum.map(&feed_name/1)
      |> join_names()

    topic =
      members
      |> Enum.map(&(state.accounts[&1] && state.accounts[&1].topic))
      # "other" is the topic question's catch-all, not a useful name.
      |> Enum.reject(&(is_nil(&1) or &1 == "other"))
      |> Enum.frequencies()
      |> Enum.max_by(fn {_topic, n} -> n end, fn -> nil end)

    case topic do
      {topic, _n} -> "#{String.capitalize(topic)} cluster on #{feeds}"
      nil -> "Unnamed cluster on #{feeds}"
    end
  end

  defp feed_ids(state, ids),
    do: ids |> Enum.map(&state.accounts[&1].feed_id) |> Enum.uniq()

  defp feed_name(id) do
    case Feeds.get(id) do
      nil -> id
      feed -> feed.name()
    end
  end

  defp join_names([one]), do: one
  defp join_names(names), do: Enum.join(Enum.drop(names, -1), ", ") <> " and " <> List.last(names)

  defp accounts_text(1), do: "1 account"
  defp accounts_text(n), do: "#{n} accounts"

  ## Links

  defp upsert_links(state, members, coordinated, %{report: report, cfg: cfg} = ctx) do
    case Answers.relation(report.answers) do
      {kind, _label, _confidence} when kind != :none ->
        strength = Map.fetch!(@strengths, strength(coordinated, cfg))

        entry = %{
          finding_id: ctx.id,
          question: "relation",
          model: report.model,
          at: report.observed_at
        }

        pairs = for a <- members, b <- members, a < b, do: {a, b}
        existing = Map.new(state.links, &{{&1.account_ids, &1.kind}, &1})

        {updated, added} =
          Enum.reduce(pairs, {existing, []}, fn pair, {links, added} ->
            case links[{pair, kind}] do
              nil ->
                link = %Link{
                  account_ids: pair,
                  kind: kind,
                  strength: strength,
                  provenance: [entry]
                }

                {Map.put(links, {pair, kind}, link), [link | added]}

              link ->
                provenance = Enum.take([entry | link.provenance], cfg[:provenance_per_link])
                link = %{link | strength: strength, provenance: provenance}
                {Map.put(links, {pair, kind}, link), added}
            end
          end)

        kept = Enum.map(state.links, &Map.fetch!(updated, {&1.account_ids, &1.kind}))
        %{state | links: kept ++ Enum.reverse(added)}

      _ ->
        state
    end
  end

  ## Trend findings

  defp trend(state, %{report: report, cfg: cfg} = ctx) do
    network = Map.fetch!(state.networks, report.network_id)
    previous = network.assessment && network.assessment[:trajectory]
    increasing = Answers.noul(report.answers, "increasing")
    {trajectory, confidence} = Answers.choice(report.answers, "trajectory") || {nil, nil}

    state =
      update_assessment(state, network.id, %{
        increasing: increasing,
        trajectory: trajectory || previous,
        trajectory_confidence: if(trajectory, do: confidence),
        trend_observed_at: report.observed_at,
        model: report.model
      })

    rising? = (is_number(increasing) and increasing >= cfg[:yes]) or trajectory == "forming"

    if rising? do
      trigger =
        if previous in ["fading", "none"], do: "network_reactivation", else: "coordination_rising"

      title =
        if trigger == "network_reactivation",
          do: "#{network.name} is active again",
          else: "Coordination rising in #{network.name}"

      finding = %{
        trigger: trigger,
        severity: severity(increasing || confidence, cfg),
        title: title,
        observed_at: report.observed_at,
        network_id: network.id,
        comparison: %{
          label: "Trajectory",
          before: previous || "unknown",
          after: trajectory || "unknown"
        },
        evidence:
          trend_evidence(network.member_ids, increasing, trajectory, confidence, cfg, who(ctx))
      }

      with {:ok, state, alerts, skipped, ignored} <- intake(state, finding, ctx) do
        {:ok,
         result(ctx, alerts: alerts, network_id: network.id, skipped: skipped, reason: ignored),
         state}
      end
    else
      reason = if is_nil(report.answers), do: :no_answers, else: :below_threshold
      {:ok, result(ctx, network_id: network.id, reason: reason), state}
    end
  end

  ## Evidence

  defp group_evidence(members, coordinated, ctx) do
    [
      answer_evidence(
        "#{who(ctx)}: these #{length(members)} accounts post in a coordinated way " <>
          "(#{percent(coordinated)}%).",
        strength(coordinated, ctx.cfg),
        relation_kind(ctx),
        members
      )
      | relation_evidence(members, ctx)
    ]
  end

  defp growth_evidence(added, coordinated, ctx) do
    [
      answer_evidence(
        "#{who(ctx)}: #{accounts_text(length(added))} outside the network post in a " <>
          "coordinated way with it (#{percent(coordinated)}%).",
        strength(coordinated, ctx.cfg),
        relation_kind(ctx),
        added
      )
    ]
  end

  defp relation_evidence(account_ids, %{report: report, cfg: cfg} = ctx) do
    case Answers.relation(report.answers) do
      {kind, label, confidence} when kind != :none ->
        suffix = if confidence, do: " (confidence #{percent(confidence)}%)", else: ""

        [
          answer_evidence(
            "#{who(ctx)}: the relation between them is #{label}#{suffix}.",
            strength(confidence || 0, cfg),
            Atom.to_string(kind),
            account_ids
          )
        ]

      _ ->
        []
    end
  end

  defp trend_evidence(account_ids, increasing, trajectory, confidence, cfg, who) do
    increasing_item =
      if is_number(increasing),
        do: [
          answer_evidence(
            "#{who}: coordination in this network is increasing (#{percent(increasing)}%).",
            strength(increasing, cfg),
            "other",
            account_ids
          )
        ],
        else: []

    trajectory_item =
      if trajectory,
        do: [
          answer_evidence(
            "#{who}: the network's trajectory is #{trajectory}" <>
              if(confidence, do: " (confidence #{percent(confidence)}%).", else: "."),
            strength(confidence || 0, cfg),
            "other",
            account_ids
          )
        ],
        else: []

    increasing_item ++ trajectory_item
  end

  # Evidence names the model that answered (e.g. "jev-1.13", or "simulator" for the
  # dev simulator's canned answers), never assuming it was Jev.
  defp who(%{report: %{model: model}}) when is_binary(model) and model != "", do: model
  defp who(_ctx), do: "The model"

  defp answer_evidence(explanation, strength, kind, account_ids),
    do: %{
      explanation: explanation,
      strength: strength,
      kind: kind,
      account_ids: account_ids,
      source: :answers
    }

  defp relation_kind(%{report: report}) do
    case Answers.relation(report.answers) do
      {kind, _label, _confidence} when kind != :none -> Atom.to_string(kind)
      _ -> "other"
    end
  end

  ## Intake

  # Runs one internal finding through the intake and stamps the resulting alert
  # with the report's answers and model. The last element is the intake's reason
  # when it ignored the finding (e.g. `:predates_dismissal`), otherwise nil.
  defp intake(state, finding, %{id: ctx_id, report: report, now: now}) do
    with {:ok, %{action: action, alert: alert, skipped: skipped, reason: reason}, state} <-
           Intake.run(state, finding, now) do
      case action do
        :ignored ->
          {:ok, state, [], skipped, reason}

        _ ->
          alert = %{alert | answers: report.answers, model: report.model, finding_id: ctx_id}
          state = State.put_alert(state, alert)
          {:ok, state, [%{action: action, alert: alert}], skipped, nil}
      end
    end
  end

  ## Accounts and posts

  defp ensure_account(state, %{feed_id: feed_id, handle: handle}, now) do
    case state.account_by_handle[{feed_id, handle}] do
      nil ->
        {id, state} = State.next_id(state, "acc")
        account = %Account{id: id, feed_id: feed_id, handle: handle, first_seen_at: now}
        {account, State.put_account(state, account)}

      id ->
        {state.accounts[id], state}
    end
  end

  # New posts win per platform post id; earlier posts are kept. Dated posts are
  # newest first; posts whose timestamp can't be read are kept at the end (never
  # dropped, never given an invented time) so evidence isn't lost. Capped.
  defp merge_posts(state, account_id, raw_posts, limit) do
    {fresh, state} =
      Enum.map_reduce(raw_posts, state, fn raw, state ->
        {id, state} = State.next_id(state, "post")

        post = %Post{
          id: id,
          account_id: account_id,
          post_id: raw.id,
          posted_at: posted_at(raw.published_at),
          text: raw.text,
          domain: Enum.find_value(raw.urls, &host/1)
        }

        {post, state}
      end)

    {dated, undated} =
      (fresh ++ Map.get(state.posts, account_id, []))
      |> Enum.uniq_by(& &1.post_id)
      |> Enum.split_with(& &1.posted_at)

    merged =
      (Enum.sort_by(dated, & &1.posted_at, {:desc, DateTime}) ++
         Enum.sort_by(undated, & &1.post_id))
      |> Enum.take(limit)

    {merged, state}
  end

  defp newest(posts) do
    case Enum.find(posts, & &1.posted_at) do
      nil -> nil
      post -> post.posted_at
    end
  end

  defp posted_at(%DateTime{} = at), do: DateTime.truncate(at, :second)

  defp posted_at(unix) when is_integer(unix) do
    case DateTime.from_unix(unix) do
      {:ok, at} -> at
      _ -> nil
    end
  end

  defp posted_at(text) when is_binary(text) do
    case DateTime.from_iso8601(text) do
      {:ok, at, _offset} -> DateTime.truncate(at, :second)
      _ -> nil
    end
  end

  defp posted_at(_), do: nil

  defp host(url) when is_binary(url), do: URI.parse(url).host
  defp host(_), do: nil

  ## Helpers

  defp update_network(state, id, fun),
    do: %{state | networks: Map.update!(state.networks, id, fun)}

  defp update_assessment(state, network_id, changes) do
    update_network(state, network_id, fn network ->
      %{network | assessment: Map.merge(network.assessment || %{}, changes)}
    end)
  end

  defp log_finding(state, %{id: id, report: report, cfg: cfg}) do
    entry = %{
      id: id,
      kind: report.kind,
      observed_at: report.observed_at,
      model: report.model,
      network_id: report.network_id,
      accounts: if(report.account, do: [report.account], else: report.accounts),
      answers: report.raw_answers
    }

    %{state | findings: Enum.take([entry | state.findings], cfg[:findings_log])}
  end

  defp severity(nil, _cfg), do: "medium"

  defp severity(p, cfg) do
    bands = cfg[:severity]

    cond do
      p >= bands[:high] -> "high"
      p >= bands[:medium] -> "medium"
      true -> "low"
    end
  end

  defp strength(p, cfg) do
    bands = cfg[:strength]

    cond do
      p >= bands[:strong] -> "strong"
      p >= bands[:moderate] -> "moderate"
      true -> "weak"
    end
  end

  defp percent(p), do: round(p * 100)

  defp result(ctx, fields) do
    Map.merge(
      %{
        kind: ctx.report.kind,
        finding_id: ctx.id,
        alerts: [],
        network_id: nil,
        account_ids: [],
        skipped: [],
        reason: nil
      },
      Map.new(fields)
    )
  end
end
