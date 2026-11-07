defmodule Dripstone.Tracker.SampleData do
  @moduledoc """
  Deterministic sample data for the tracker, used until real detection exists.

  `generate/1` returns:

    * `:accounts`, `:links`, `:posts`, `:feed_health`: base data (structs)
    * `:events`: a time-ordered list of what happens to the networks, each
      `%{at: DateTime.t(), type: :finding | :decision | :curation, ...}`

  Finding events carry a `:finding` map in the shape detection reports through the
  findings intake (see `openspec/changes/add-tracker-ui/docs/DETECTION_INTERFACE.md`). Decision and curation events
  stand in for analyst actions. The store replays the events in order, so every
  sample alert is produced by the real intake.

  The same `now` always produces the same data; all times are relative to it.
  """

  alias Dripstone.Tracker.{Account, FeedHealth, Link, Post, Signal}

  @seed {20_261_107, 29, 30}

  @feed_counts [
    {"x", 402},
    {"reddit", 260},
    {"bluesky", 180},
    {"mastodon", 150},
    {"telegram", 97},
    {"facebook", 211}
  ]

  @instances ["mastodon.example", "fedi.example", "toot.example"]

  @adjectives ~w(sunny quiet bright swift lucky happy daily golden silver true bold
                 fresh prime smart urban cosmic rapid clear noble vivid calm loyal)
  @nouns ~w(deals hunter finds market trends voice news picks savings wave pulse
            corner insider digest crew lens spark hub signal outlet)

  # Network blueprints. `days` is days ago of first activity; `story` picks the
  # events that happen to the network.
  @networks [
    %{
      key: "sunrise",
      name: "Sunrise Cluster",
      size: 41,
      feeds: ["x", "bluesky"],
      confidence: 86,
      hour: 9,
      weekdays_only: true,
      days: 30,
      domain: "deals-a.example",
      story: :promotion_shift
    },
    %{
      key: "bluewave",
      name: "Bluewave Ring",
      size: 18,
      extra: 9,
      feeds: ["reddit"],
      confidence: 95,
      hour: 14,
      days: 42,
      domain: "bluewave-coupons.example",
      story: :confirmed_growth
    },
    %{
      key: "quietpine",
      name: "Quiet Pine",
      size: 24,
      feeds: ["mastodon"],
      confidence: 78,
      hour: 20,
      days: 50,
      domain: "pine-crypto.example",
      story: :reactivation
    },
    %{
      key: "echo",
      name: "Echo Chamber 7",
      size: 15,
      extra: 9,
      feeds: ["telegram"],
      confidence: 72,
      hour: 7,
      days: 22,
      domain: "echo-signals.example",
      story: :dismissed_returns
    },
    %{
      key: "lumen",
      name: "Cluster #0388",
      size: 400,
      feeds: ["x", "reddit", "facebook"],
      confidence: 91,
      hour: 12,
      days: 18,
      domain: "lumen-giveaway.example",
      story: :large
    },
    %{
      key: "driftwood",
      name: "Cluster #0417",
      size: 12,
      feeds: ["facebook"],
      confidence: 64,
      hour: 17,
      days: 7,
      domain: "driftwood-shop.example",
      story: :no_summary
    },
    %{
      key: "c0420",
      name: "Cluster #0420",
      size: 28,
      feeds: ["x"],
      confidence: 88,
      hour: 6,
      days: 35,
      domain: "fastloans.example",
      story: {:decided, :confirm}
    },
    %{
      key: "c0421",
      name: "Cluster #0421",
      size: 22,
      feeds: ["bluesky", "mastodon"],
      confidence: 74,
      hour: 22,
      days: 12,
      domain: "rally-tickets.example",
      story: :open
    },
    %{
      key: "c0422",
      name: "Cluster #0422",
      size: 14,
      feeds: ["reddit"],
      confidence: 61,
      hour: 3,
      days: 9,
      domain: "gamekeys.example",
      story: :open
    },
    %{
      key: "c0423",
      name: "Cluster #0423",
      size: 19,
      feeds: ["x", "telegram"],
      confidence: 69,
      hour: 15,
      days: 26,
      domain: "fanclub.example",
      story: {:decided, :dismiss}
    },
    %{
      key: "c0424",
      name: "Cluster #0424",
      size: 33,
      feeds: ["facebook", "x"],
      confidence: 83,
      hour: 11,
      days: 38,
      domain: "miracle-diet.example",
      story: {:decided, :confirm}
    },
    %{
      key: "c0425",
      name: "Cluster #0425",
      size: 26,
      feeds: ["bluesky"],
      confidence: 79,
      hour: 18,
      days: 4,
      domain: "nft-drop.example",
      story: :open
    }
  ]

  @doc "Generates the full sample data set relative to `now`."
  @spec generate(DateTime.t()) :: map()
  def generate(now \\ DateTime.utc_now()) do
    now = DateTime.truncate(now, :second)
    previous = :rand.export_seed()
    :rand.seed(:exsss, @seed)

    try do
      build(now)
    after
      restore_seed(previous)
    end
  end

  defp restore_seed(:undefined), do: Process.delete(:rand_seed)
  defp restore_seed(state), do: :rand.seed(state)

  defp build(now) do
    skeletons = skeletons()
    pools = for {feed, _} <- @feed_counts, into: %{}, do: {feed, pool(skeletons, feed)}
    {plans, _cursors} = Enum.map_reduce(@networks, %{}, &allocate(&1, &2, pools))
    membership = membership(plans)

    {accounts, posts} = accounts_and_posts(skeletons, membership, now)

    %{
      accounts: accounts,
      posts: posts,
      links: Enum.flat_map(plans, &links/1),
      feed_health: feed_health(now),
      events: plans |> Enum.flat_map(&events(&1, now)) |> Enum.sort_by(& &1.at, DateTime)
    }
  end

  ## Accounts

  defp skeletons do
    @feed_counts
    |> Enum.flat_map(fn {feed, count} -> List.duplicate(feed, count) end)
    |> Enum.with_index(1)
    |> Enum.map(fn {feed, i} ->
      %{id: "acc-" <> String.pad_leading(Integer.to_string(i), 4, "0"), feed_id: feed, n: i}
    end)
  end

  defp pool(skeletons, feed),
    do: skeletons |> Enum.filter(&(&1.feed_id == feed)) |> Enum.map(& &1.id) |> List.to_tuple()

  defp allocate(blueprint, cursors, pools) do
    feeds = blueprint.feeds

    take = fn count, cursors ->
      Enum.map_reduce(0..(count - 1)//1, cursors, fn i, cursors ->
        feed = Enum.at(feeds, rem(i, length(feeds)))
        index = Map.get(cursors, feed, 0)
        {elem(pools[feed], index), Map.put(cursors, feed, index + 1)}
      end)
    end

    {member_ids, cursors} = take.(blueprint.size, cursors)
    {extra_ids, cursors} = take.(Map.get(blueprint, :extra, 0), cursors)

    plan =
      Map.merge(blueprint, %{
        id: "net-" <> blueprint.key,
        member_ids: member_ids,
        extra_ids: extra_ids
      })

    {plan, cursors}
  end

  defp membership(plans) do
    for plan <- plans,
        {id, role} <-
          Enum.map(plan.member_ids, &{&1, :member}) ++ Enum.map(plan.extra_ids, &{&1, :extra}),
        into: %{},
        do: {id, {plan, role}}
  end

  defp accounts_and_posts(skeletons, membership, now) do
    {accounts, posts, _counter} =
      Enum.reduce(skeletons, {[], [], 0}, fn skeleton, {accounts, posts, counter} ->
        role = Map.get(membership, skeleton.id)
        times = post_times(role, skeleton.id, now)

        {new_posts, counter} =
          Enum.map_reduce(times, counter, fn {at, domain}, counter ->
            counter = counter + 1

            post = %Post{
              id: "post-" <> Integer.to_string(counter),
              account_id: skeleton.id,
              post_id: Integer.to_string(1_790_000_000 + counter * 7919),
              posted_at: at,
              domain: domain,
              text: post_text(role, domain)
            }

            {post, counter}
          end)

        account = account(skeleton, role, new_posts, now)
        {[account | accounts], Enum.reverse(new_posts, posts), counter}
      end)

    {Enum.reverse(accounts), Enum.reverse(posts)}
  end

  defp account(%{id: id, feed_id: feed, n: n}, role, posts, now) do
    adjective = pick(@adjectives)
    noun = pick(@nouns)
    {handle, instance} = handle(feed, adjective, noun, n)
    posted = Enum.map(posts, & &1.posted_at)
    first_seen = Enum.min(posted, DateTime, fn -> ago(now, 30) end)
    score = risk_score(role)

    %Account{
      id: id,
      feed_id: feed,
      handle: handle,
      instance: instance,
      display_name: String.capitalize(adjective) <> " " <> String.capitalize(noun),
      created_at: created_at(role, now),
      first_seen_at: first_seen,
      last_seen_at: Enum.max(posted, DateTime, fn -> first_seen end),
      risk_score: score,
      signals: signals(role, score)
    }
  end

  defp handle("bluesky", a, n, i), do: {"#{a}-#{n}#{i}.bsky.social", nil}
  defp handle("mastodon", a, n, i), do: {"#{a}_#{n}#{i}", pick(@instances)}
  defp handle("telegram", a, n, i), do: {"#{a}_#{n}_#{i}", nil}

  defp handle("facebook", a, n, i),
    do: {String.capitalize(a) <> String.capitalize(n) <> "#{i}", nil}

  defp handle(_feed, a, n, i), do: {"#{a}_#{n}#{i}", nil}

  defp created_at(nil, now), do: ago(now, rand(365, 3000))
  defp created_at({_plan, :extra}, now), do: ago(now, rand(6, 10))
  defp created_at({plan, :member}, now), do: ago(now, plan.days + rand(3, 9))

  defp risk_score(nil), do: if(chance(0.03), do: rand(70, 84), else: rand(3, 62))
  defp risk_score({%{confidence: c}, _role}) when c < 70, do: rand(52, 82)
  defp risk_score(_member), do: rand(70, 98)

  ## Signals

  @member_signals [
    {"Posting cadence", &__MODULE__.cadence_text/0},
    {"Content similarity", &__MODULE__.similarity_text/0},
    {"Account age", &__MODULE__.young_age_text/0},
    {"Persona consistency", &__MODULE__.persona_text/0},
    {"Link sharing", &__MODULE__.link_text/0},
    {"Engagement pattern", &__MODULE__.engagement_text/0}
  ]

  @baseline_signals [
    {"Posting cadence", "Posts at irregular, human-looking times."},
    {"Account age", "Account is several years old."},
    {"Link sharing", "Links to a varied mix of sites."},
    {"Engagement pattern", "Interacts with a broad, changing set of accounts."}
  ]

  defp signals(role, score) do
    named =
      case role do
        nil ->
          @baseline_signals |> Enum.shuffle() |> Enum.take(rand(2, 3))

        _member ->
          @member_signals
          |> Enum.shuffle()
          |> Enum.take(rand(3, 4))
          |> Enum.map(fn {name, text} -> {name, text.()} end)
      end

    named
    |> Enum.zip(split(score, length(named)))
    |> Enum.map(fn {{name, explanation}, part} ->
      %Signal{name: name, explanation: explanation, contribution: part}
    end)
    |> Enum.sort_by(& &1.contribution, :desc)
  end

  # Splits `total` into `parts` positive integers that sum to it.
  defp split(total, parts) do
    weights = for _ <- 1..parts, do: rand(2, 10)
    sum = Enum.sum(weights)
    shares = Enum.map(weights, &max(div(&1 * total, sum), 1))
    [first | rest] = Enum.sort(shares, :desc)
    [first + total - Enum.sum(shares) | rest]
  end

  @doc false
  def cadence_text, do: "Posts every #{rand(4, 12)} minutes, around the clock."
  @doc false
  def similarity_text, do: "#{rand(78, 97)}% text overlap with #{rand(6, 30)} other accounts."
  @doc false
  def young_age_text,
    do: "Created #{rand(9, 60)} days ago, alongside #{rand(5, 25)} similar accounts."

  @doc false
  def persona_text, do: "Profile details and writing style don't match each other."
  @doc false
  def link_text, do: "#{rand(60, 95)}% of posts link to the same domain."
  @doc false
  def engagement_text, do: "Interactions come almost entirely from the same small group."

  ## Posts

  # Returns [{posted_at, domain}] for an account.
  defp post_times(nil, _id, now) do
    count = if chance(0.03), do: 0, else: rand(2, 5)
    domains = [nil, nil, nil, "news.example", "blog.example", "shop.example"]
    for _ <- 1..count//1, do: {ago(now, rand(0, 29), rand(0, 23), rand(0, 59)), pick(domains)}
  end

  defp post_times({plan, :extra}, _id, now) do
    {from, to} = if plan.story == :dismissed_returns, do: {5, 3}, else: {3, 1}
    for _ <- 1..rand(2, 4), do: coordinated(plan, rand(to, from), now)
  end

  defp post_times({%{story: :reactivation} = plan, :member}, id, now) do
    quiet = for _ <- 1..rand(3, 6), do: coordinated(plan, rand(21, plan.days - 1), now)

    if id in Enum.take(plan.member_ids, 5),
      do: quiet ++ [{ago(now, 0, rand(3, 5), rand(0, 59)), plan.domain}],
      else: quiet
  end

  defp post_times({plan, :member}, _id, now) do
    for _ <- 1..rand(4, 8), do: coordinated(plan, rand(0, plan.days - 1), now)
  end

  defp coordinated(plan, days_ago, now) do
    at = now |> ago(days_ago) |> at_hour(plan.hour, rand(0, 59))
    at = if Map.get(plan, :weekdays_only), do: weekday(at), else: at
    at = if DateTime.compare(at, now) == :gt, do: DateTime.add(at, -86_400, :second), else: at
    {at, domain_at(plan, days_ago)}
  end

  defp domain_at(%{story: :promotion_shift}, days_ago) when days_ago <= 5, do: "deals-b.example"
  defp domain_at(plan, _days_ago), do: plan.domain

  defp post_text(nil, nil),
    do:
      pick([
        "Good morning everyone!",
        "Anyone watching the match tonight?",
        "Thoughts on the new update?",
        "Lovely weather today."
      ])

  defp post_text(nil, domain), do: "Interesting read: https://#{domain}/#{rand(100, 999)}"

  defp post_text(_member, domain) do
    pick([
      "Huge discount today only! https://#{domain}/#{rand(100, 999)}",
      "Don't miss out, limited spots left https://#{domain}/go",
      "I tried this and it actually works https://#{domain}/#{rand(100, 999)}",
      "Everyone is talking about this https://#{domain}"
    ])
  end

  ## Links

  defp links(plan) do
    ids = List.to_tuple(plan.member_ids ++ plan.extra_ids)
    n = tuple_size(ids)
    kinds = Link.kinds()

    for i <- 0..(n - 1), offset <- 1..rand(1, 3), n > 1 do
      a = elem(ids, i)
      b = elem(ids, rem(i + offset, n))
      kind = pick(kinds)

      %Link{
        account_ids: if(a < b, do: {a, b}, else: {b, a}),
        kind: kind,
        strength: pick([:weak, :moderate, :moderate, :strong, :strong])
      }
    end
    |> Enum.uniq_by(&{&1.account_ids, &1.kind})
  end

  ## Feed health

  defp feed_health(now) do
    [
      %FeedHealth{
        feed_id: "x",
        status: :healthy,
        last_item_at: ago(now, 0, 0, 0) |> DateTime.add(-12, :second),
        items_24h: 18_204
      },
      %FeedHealth{
        feed_id: "reddit",
        status: :healthy,
        last_item_at: DateTime.add(now, -95, :second),
        items_24h: 6_120
      },
      %FeedHealth{
        feed_id: "bluesky",
        status: :healthy,
        last_item_at: DateTime.add(now, -30, :second),
        items_24h: 4_410
      },
      %FeedHealth{
        feed_id: "mastodon",
        status: :healthy,
        last_item_at: DateTime.add(now, -70, :second),
        items_24h: 2_302
      },
      %FeedHealth{
        feed_id: "telegram",
        status: :down,
        last_item_at: ago(now, 0, 3, 4),
        items_24h: 1_102,
        last_error: "401 Unauthorized",
        last_error_at: ago(now, 0, 3)
      },
      %FeedHealth{
        feed_id: "facebook",
        status: :degraded,
        last_item_at: ago(now, 0, 0, 41),
        items_24h: 2_881
      }
    ]
  end

  ## Events

  defp events(%{story: :promotion_shift} = plan, now) do
    removed = Enum.at(plan.member_ids, 5)

    [
      new_network(plan, ago(now, 28)),
      curation(ago(now, 27), plan, :rename, %{name: "Discount Spam Ring"}),
      curation(ago(now, 27, -1), plan, :add_tag, %{tag: "discount-spam"}),
      curation(ago(now, 27, -1, -5), plan, :add_tag, %{tag: "coordinated-promo"}),
      curation(ago(now, 20), plan, :remove_member, %{account_id: removed}),
      finding(ago(now, 0, 2), %{
        trigger: "promotion_shift",
        severity: "high",
        title: "#{plan.name} switched its main promoted domain",
        network_id: plan.id,
        evidence: [
          evidence(
            "shared_link",
            "strong",
            "Share of links to deals-b.example rose from 4% to 55% in 5 days.",
            Enum.take(plan.member_ids, 23)
          ),
          evidence(
            "other",
            "moderate",
            "deals-b.example was registered 3 days before the switch.",
            []
          ),
          evidence(
            "near_duplicate",
            "moderate",
            "Same promo copy as before, with the new link swapped in.",
            Enum.take(plan.member_ids, 17)
          )
        ],
        ai_rationale:
          rationale(
            "The network moved its promotion to a newly registered domain while keeping the same copy and posting schedule, which suggests the same operator rotating domains.",
            ago(now, 0, 2)
          ),
        comparison: %{
          label: "Main promoted domain",
          before: "deals-a.example (62% of links)",
          after: "deals-b.example (55% of links)"
        },
        network_updates: %{
          main_domain: "deals-b.example",
          confidence: 88,
          add_member_ids: [removed]
        }
      })
    ]
  end

  defp events(%{story: :confirmed_growth} = plan, now) do
    [
      new_network(plan, ago(now, 40)),
      decision(ago(now, 39), plan, :confirm, "Same promo copy across all 18 accounts."),
      growth(plan, ago(now, 1), plan.extra_ids)
    ]
  end

  defp events(%{story: :reactivation} = plan, now) do
    woke = Enum.take(plan.member_ids, 5)

    [
      new_network(plan, ago(now, 45)),
      decision(ago(now, 44), plan, :confirm, nil),
      finding(ago(now, 0, 2), %{
        trigger: "network_reactivation",
        severity: "medium",
        title: "#{plan.name} is posting again after 20 days",
        network_id: plan.id,
        evidence: [
          evidence(
            "synced_posting",
            "strong",
            "5 accounts posted within 3 hours after 20 days of silence.",
            woke
          ),
          evidence(
            "near_duplicate",
            "moderate",
            "New posts reuse the network's earlier templates.",
            woke
          )
        ],
        ai_rationale:
          rationale(
            "A dormant group resumed at once with recycled templates, consistent with a scheduled campaign restarting.",
            ago(now, 0, 2)
          ),
        comparison: %{
          label: "Activity",
          before: "Silent for 20 days",
          after: "5 accounts active in 3 hours"
        },
        network_updates: nil
      })
    ]
  end

  defp events(%{story: :dismissed_returns} = plan, now) do
    stale_finding =
      growth(plan, ago(now, 10), Enum.take(plan.extra_ids, 2))
      |> put_in([:finding, :observed_at], ago(now, 19))
      |> put_in([:finding, :network_updates], nil)

    [
      new_network(plan, ago(now, 20)),
      decision(ago(now, 18), plan, :dismiss, "Looks like a fan group, not coordinated."),
      stale_finding,
      growth(plan, ago(now, 3), plan.extra_ids)
    ]
  end

  defp events(%{story: {:decided, action}} = plan, now) do
    raised = plan.days - 2
    [new_network(plan, ago(now, raised)), decision(ago(now, raised - 1), plan, action, nil)]
  end

  defp events(plan, now), do: [new_network(plan, ago(now, max(plan.days - 2, 1)))]

  defp new_network(plan, at) do
    evidence = network_evidence(plan)
    summary? = plan.story != :no_summary

    finding(at, %{
      trigger: "new_network",
      severity: severity(plan.confidence),
      title: "#{plan.name} detected with #{plan.confidence}% confidence",
      new_network: %{
        id: plan.id,
        name: plan.name,
        member_ids: plan.member_ids,
        confidence: plan.confidence,
        platforms: plan.feeds,
        main_domain: plan.domain,
        evidence: evidence,
        summary: if(summary?, do: rationale(summary_text(plan), at))
      },
      evidence: evidence,
      ai_rationale:
        if(summary?,
          do:
            rationale("Recently created accounts posting the same links on a fixed schedule.", at)
        ),
      comparison: nil,
      network_updates: nil
    })
  end

  defp growth(plan, at, new_ids) do
    count = length(new_ids)

    finding(at, %{
      trigger: "network_growth",
      severity: "medium",
      title: "#{plan.name} gained #{count} accounts",
      network_id: plan.id,
      evidence: [
        evidence(
          "near_duplicate",
          "strong",
          "#{count} new accounts post the network's promo copy.",
          new_ids
        ),
        evidence(
          "created_together",
          "moderate",
          "The new accounts were created within days of each other.",
          new_ids
        )
      ],
      ai_rationale:
        rationale(
          "New accounts joined with the same templates and links as existing members.",
          at
        ),
      comparison: %{label: "Members", before: "#{plan.size}", after: "#{plan.size + count}"},
      network_updates: %{add_member_ids: new_ids}
    })
  end

  defp network_evidence(plan) do
    members = plan.member_ids
    size = length(members)

    [
      evidence(
        "shared_link",
        "strong",
        "#{div(size, 3) + 1} members posted links to #{plan.domain}.",
        Enum.take(members, div(size, 3) + 1)
      ),
      evidence(
        "near_duplicate",
        "strong",
        "#{div(size * 2, 3)} members post near-identical text.",
        Enum.take(members, div(size * 2, 3))
      ),
      evidence(
        "created_together",
        "moderate",
        "#{div(size, 2) + 1} accounts were created within the same week.",
        Enum.take(members, div(size, 2) + 1)
      )
    ]
  end

  defp summary_text(plan) do
    "A cluster of #{plan.size} recently created accounts on #{Enum.join(plan.feeds, ", ")} " <>
      "promoting #{plan.domain} on a fixed schedule around #{plan.hour}:00 UTC, " <>
      "with near-identical text and shared links."
  end

  defp severity(confidence) when confidence >= 85, do: "high"
  defp severity(confidence) when confidence >= 70, do: "medium"
  defp severity(_confidence), do: "low"

  defp finding(at, finding),
    do: %{at: at, type: :finding, finding: Map.put_new(finding, :observed_at, at)}

  defp decision(at, plan, action, note),
    do: %{
      at: at,
      type: :decision,
      action: action,
      network_id: plan.id,
      trigger: "new_network",
      note: note
    }

  defp curation(at, plan, action, attrs),
    do: Map.merge(%{at: at, type: :curation, action: action, network_id: plan.id}, attrs)

  defp evidence(kind, strength, explanation, account_ids),
    do: %{kind: kind, strength: strength, explanation: explanation, account_ids: account_ids}

  defp rationale(text, at), do: %{text: text, generated_at: at}

  ## Helpers

  defp ago(now, days, hours \\ 0, minutes \\ 0),
    do: DateTime.add(now, -(days * 86_400 + hours * 3_600 + minutes * 60), :second)

  defp at_hour(at, hour, minute) do
    {:ok, time} = Time.new(hour, minute, 0)
    DateTime.new!(DateTime.to_date(at), time, "Etc/UTC")
  end

  defp weekday(at) do
    case Date.day_of_week(at) do
      dow when dow > 5 -> DateTime.add(at, -(dow - 5) * 86_400, :second)
      _dow -> at
    end
  end

  defp rand(low, high), do: low + :rand.uniform(high - low + 1) - 1
  defp pick(list), do: Enum.at(list, :rand.uniform(length(list)) - 1)
  defp chance(probability), do: :rand.uniform() < probability
end
