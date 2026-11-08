defmodule Dripstone.Scorer do
  @moduledoc """
  Heuristic bot scoring over canonical post maps plus optional AI answers.

  Canonical post: `%{id:, handle:, text:, urls:, published_at:}` where
  `published_at` is a `DateTime`, ISO-8601 string, or unix int (nil allowed).
  """

  alias Dripstone.AIClient

  @state_cap 8_000

  # shortcut: circadian/trend scoring hooks plug in here (issues #44-45 live elsewhere).
  # Holdout discipline (issue #46): `test/fixtures/holdout_posts.json` is frozen and
  # excluded from all scorer tuning; reported metrics come from that slice.

  @doc "Pure heuristics: volume (40) + link ratio (30) + timing regularity (30)."
  def score(posts) when is_list(posts) do
    count = length(posts)
    ratio = link_ratio(posts)
    regularity = regularity_points(posts)

    total =
      min(count / 50, 1.0) * 40 +
        ratio * 30 +
        regularity

    labels =
      []
      |> maybe(count >= 20, "high_volume")
      |> maybe(count > 0 and ratio > 0.5, "high_link_ratio")
      |> maybe(regularity > 15, "regular_timing")

    %{score: round(min(total, 100)), labels: labels}
  end

  def score(_posts), do: {:error, {:invalid_args, "posts must be a list"}}

  @doc """
  Heuristics plus `AIClient.decide/3` with the account question set (`is_bot`
  noul, `topic` choice, `spam` score). On `{:error, _}` returns heuristics-only.
  """
  def assess(posts, opts \\ [])

  def assess(posts, _opts) when not is_list(posts),
    do: {:error, {:invalid_args, "posts must be a list"}}

  def assess(posts, opts) when is_list(posts) do
    %{score: s, labels: l} = score(posts)
    run_decision(summarize(posts), account_questions(), %{score: s, labels: l}, opts)
  end

  @doc """
  Heuristics plus `AIClient.decide/3` with the group question set (`coordinated`
  noul, `relation` choice, one `member:<feed>:<handle>` noul per member).
  Each member is `%{feed_id:, handle:, posts:}` (atom or string keys).
  On `{:error, _}` returns heuristics-only.
  """
  def assess_group(members, opts \\ []) when is_list(members) do
    %{score: s, labels: l} = members |> Enum.flat_map(&member_posts/1) |> score()
    run_decision(group_state(members), group_questions(members), %{score: s, labels: l}, opts)
  end

  @doc """
  Heuristics plus `AIClient.decide/3` with the trend question set (`increasing`
  noul, `trajectory` choice) over the network's recent posts.
  On `{:error, _}` returns heuristics-only.
  """
  def assess_trend(posts, opts \\ []) when is_list(posts) do
    %{score: s, labels: l} = score(posts)
    run_decision(summarize(posts), trend_questions(), %{score: s, labels: l}, opts)
  end

  # Every choice/score question carries `criteria` with the exact labels the
  # intake expects (Jev rejects `choices:` and level-less scores, HTTP 422).
  defp account_questions do
    %{
      is_bot: %{
        type: :noul,
        instructions: "Is this account automated/bot-like given volume, link sharing, and timing?"
      },
      topic: %{
        type: :choice,
        instructions: "What topic best describes these posts?",
        criteria: %{
          "crypto" => "Cryptocurrency, trading, or token promotion.",
          "politics" => "Political news, campaigns, or activism.",
          "tech" => "Technology, gadgets, or software.",
          "sports" => "Sports news, teams, or betting.",
          "entertainment" => "Celebrities, movies, music, or gossip.",
          "other" => "Anything else."
        }
      },
      spam: %{
        type: :score,
        instructions: "Rate spamminess 0-1: repetitive links, promo text, machine-like timing.",
        criteria: ["not spam", "somewhat spammy", "heavy spam"]
      }
    }
  end

  defp group_questions(members) do
    member_questions =
      Map.new(members, fn member ->
        {"member:#{fetch(member, :feed_id)}:#{fetch(member, :handle)}",
         %{
           type: :noul,
           instructions: "Does this account take part in the coordinated activity?"
         }}
      end)

    Map.merge(
      %{
        coordinated: %{
          type: :noul,
          instructions:
            "Do these accounts post in a coordinated way (synced timing, shared links)?"
        },
        relation: %{
          type: :choice,
          instructions: "Classify the relation between these accounts.",
          criteria: %{
            "repost-ring" => "Accounts amplify each other by reposting the same content.",
            "shared-link" => "Accounts promote the same links or domains together.",
            "timing-sync" => "Accounts post in synchronized timing patterns.",
            "audience-overlap" => "Accounts target or reach the same audience.",
            "none" => "No coordination relation between these accounts."
          }
        }
      },
      member_questions
    )
  end

  # Trajectory options are the four labels the intake's trend rules read: `forming`
  # (or `increasing`) raises an alert, which is a reactivation when the previous
  # trajectory was `fading` or `none`.
  defp trend_questions do
    %{
      increasing: %{
        type: :noul,
        instructions: "Is coordination in this network increasing?"
      },
      trajectory: %{
        type: :choice,
        instructions: "What is the trajectory of this network's coordinated activity?",
        criteria: %{
          "forming" => "Coordination is forming and ramping up.",
          "stable" => "Activity is steady with no clear change.",
          "fading" => "Activity is fading; the network is going quiet.",
          "none" => "No coordinated activity at all in this period."
        }
      }
    }
  end

  defp run_decision(state, questions, heuristics, opts) do
    case AIClient.decide(state, questions, Keyword.take(opts, [:plug, :model])) do
      {:ok, answers} ->
        Map.merge(heuristics, %{ai_answers: answers, source: :heuristics_plus_ai})

      {:error, _} ->
        Map.merge(heuristics, %{ai_answers: nil, source: :heuristics_only})
    end
  end

  defp member_posts(member), do: member |> fetch(:posts) |> List.wrap() |> Enum.filter(&is_map/1)

  defp group_state(members) do
    members
    |> Enum.map(fn m ->
      "#{fetch(m, :handle)} (#{fetch(m, :feed_id)}):\n#{m |> member_posts() |> summarize()}"
    end)
    |> Enum.join("\n---\n")
    |> String.slice(0, @state_cap)
  end

  defp summarize(posts) do
    posts
    |> Enum.take(50)
    |> Enum.map(&line/1)
    |> Enum.reduce_while({[], 0}, fn
      line, {[], 0} ->
        # Always keep the first line, even if over budget.
        {:cont, {[line], byte_size(line) + 1}}

      line, {[_ | _] = acc, size} ->
        # +1 for the "\n" join separator.
        if over_budget?(size, line) do
          {:halt, {acc, size}}
        else
          {:cont, {[line | acc], size + byte_size(line) + 1}}
        end
    end)
    |> elem(0)
    |> Enum.reverse()
    |> Enum.join("\n")
    |> String.slice(0, @state_cap)
  end

  defp line(p) do
    "#{fetch(p, :handle)} @ #{fetch(p, :published_at)}: #{fetch(p, :text)} #{p |> urls() |> Enum.join(" ")}"
  end

  # +1 for the "\n" join separator.
  defp over_budget?(size, line), do: size + byte_size(line) + 1 > @state_cap

  defp link_ratio([]), do: 0.0

  defp link_ratio(posts) do
    Enum.count(posts, &(urls(&1) != [])) / length(posts)
  end

  defp regularity_points(posts) do
    times = posts |> Enum.map(&to_unix/1) |> Enum.reject(&is_nil/1) |> Enum.sort()

    intervals =
      times |> Enum.chunk_every(2, 1, :discard) |> Enum.map(fn [a, b] -> b - a end)

    if length(intervals) < 2 do
      0.0
    else
      mean = Enum.sum(intervals) / length(intervals)

      if mean == 0 do
        0.0
      else
        var =
          Enum.reduce(intervals, 0.0, fn i, acc -> acc + (i - mean) * (i - mean) end) /
            length(intervals)

        cv = :math.sqrt(var) / mean
        max(0.0, 1.0 - cv) * 30
      end
    end
  end

  defp urls(post), do: fetch(post, :urls) |> List.wrap() |> Enum.filter(&is_binary/1)

  defp fetch(post, key) when is_map(post) do
    Map.get(post, key, Map.get(post, Atom.to_string(key)))
  end

  defp fetch(_post, _key), do: nil

  defp to_unix(post) do
    case fetch(post, :published_at) do
      %DateTime{} = dt -> DateTime.to_unix(dt)
      i when is_integer(i) -> i
      s when is_binary(s) -> if s == "", do: nil, else: parse_time(s)
      _ -> nil
    end
  end

  defp parse_time(s) do
    case DateTime.from_iso8601(s) do
      {:ok, dt, _} -> DateTime.to_unix(dt)
      _ -> nil
    end
  end

  defp maybe(list, true, label), do: list ++ [label]
  defp maybe(list, _, _), do: list
end
