defmodule Dripstone.Scorer do
  @moduledoc """
  Heuristic bot scoring over canonical post maps plus optional AI answers.

  Canonical post: `%{id:, handle:, text:, urls:, published_at:}` where
  `published_at` is a `DateTime`, ISO-8601 string, or unix int (nil allowed).
  """

  alias Dripstone.AIClient

  @state_cap 8_000

  # shortcut: circadian/trend/holdout scoring hooks plug in here (issues #44-46 live elsewhere).

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

  @doc """
  Heuristics plus `AIClient.decide/3` (is_bot noul, topic choice, spam score,
  coordinated noul, relation choice). On `{:error, _}` returns heuristics-only.
  """
  def assess(posts, opts \\ []) when is_list(posts) do
    %{score: s, labels: l} = score(posts)

    case AIClient.decide(summarize(posts), questions(), Keyword.take(opts, [:plug, :model])) do
      {:ok, answers} ->
        %{score: s, labels: l, ai_answers: answers, source: :heuristics_plus_ai}

      {:error, _} ->
        %{score: s, labels: l, ai_answers: nil, source: :heuristics_only}
    end
  end

  defp questions do
    %{
      is_bot: %{
        type: :noul,
        instructions: "Is this account automated/bot-like given volume, link sharing, and timing?"
      },
      topic: %{
        type: :choice,
        instructions: "What topic best describes these posts?",
        choices: ["crypto", "politics", "tech", "sports", "entertainment", "other"]
      },
      spam: %{
        type: :score,
        instructions: "Rate spamminess 0-1: repetitive links, promo text, machine-like timing."
      },
      # Don't delete coordinated/relation (issue #53): openspec change add-jev-intake
      # moves them into a group question set, `assess_group/2`, with Jev `criteria`.
      # As sent today, Jev rejects the choice/score questions (HTTP 422, no criteria).
      coordinated: %{
        type: :noul,
        instructions: "Do these accounts post in a coordinated way (synced timing, shared links)?"
      },
      relation: %{
        type: :choice,
        instructions: "Classify the relation between these accounts.",
        choices: ["repost-ring", "shared-link", "timing-sync", "audience-overlap", "none"]
      }
    }
  end

  defp summarize(posts) do
    posts
    |> Enum.take(50)
    |> Enum.map(fn p ->
      "#{fetch(p, :handle)} @ #{fetch(p, :published_at)}: #{fetch(p, :text)} #{p |> urls() |> Enum.join(" ")}"
    end)
    |> Enum.join("\n")
    |> String.slice(0, @state_cap)
  end

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
