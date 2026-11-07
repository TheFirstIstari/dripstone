defmodule Dripstone.Tracker.Assessments do
  @moduledoc """
  Interim hookup for the scorer's output (`Dripstone.Scorer.assess/2`), until the
  intake format between detection and the tracker is agreed.

  `record/3` takes one handle's posts and the scorer's result for them, then:

    * creates or updates the account: `risk_score` is the scorer's `score`, the
      signals are its `labels`, and its `ai_answers` and `source` are kept as-is;
    * merges the scored posts into the account's history (newest wins per post);
    * reports a `scorer_assessment` finding through `Dripstone.Tracker.Intake`, whose
      evidence is the scorer's raw output, one line per value.

  The scorer looks at one handle at a time, so each account gets its own
  single-member placeholder network. The severity, title, evidence strength and
  network are placeholders, not detection results.

  Being replaced: openspec change `add-jev-intake` removes this module and the
  `scorer_assessment` trigger in favour of account, group and trend findings
  (it supersedes issue #49). Read that change before extending this module.
  """

  alias Dripstone.Feeds
  alias Dripstone.Tracker.{Account, Intake, Post, Signal, State}

  @trigger "scorer_assessment"

  @type attrs :: %{
          feed_id: String.t(),
          handle: String.t(),
          posts: [map()],
          assessment: %{
            score: integer(),
            labels: [String.t()],
            ai_answers: map() | nil,
            source: atom()
          }
        }

  @doc "Records an assessment. Returns the intake's result, or `{:error, errors}`."
  @spec record(State.t(), attrs(), DateTime.t()) ::
          {:ok, Intake.result(), State.t()} | {:error, %{atom() => [String.t()]}}
  def record(%State{} = state, attrs, %DateTime{} = now) when is_map(attrs) do
    now = DateTime.truncate(now, :second)

    with {:ok, attrs} <- normalize(attrs) do
      case Feeds.get(attrs.feed_id) do
        nil ->
          {:error, %{feed_id: ["unknown feed #{inspect(attrs.feed_id)}"]}}

        feed ->
          {account, state} = upsert_account(state, attrs, now)
          Intake.run(state, finding(state, feed, account, attrs.assessment, now), now)
      end
    end
  end

  def record(%State{}, _attrs, %DateTime{}),
    do: {:error, %{base: ["an assessment must be a map"]}}

  # Accepts atom- or string-keyed maps (like Finding.cast/2); anything else is
  # rejected so a bad payload never raises inside the store GenServer.
  defp normalize(attrs) do
    assessment = fetch(attrs, :assessment)

    errors =
      %{}
      |> check(:feed_id, fetch(attrs, :feed_id), &is_binary/1, "must be a string")
      |> check(:handle, fetch(attrs, :handle), &is_binary/1, "must be a string")
      |> check(:posts, fetch(attrs, :posts), &posts?/1, "must be a list of maps")
      |> check_assessment(assessment)

    if errors == %{} do
      {:ok,
       %{
         feed_id: fetch(attrs, :feed_id),
         handle: fetch(attrs, :handle),
         posts: fetch(attrs, :posts),
         assessment: %{
           score: fetch(assessment, :score),
           labels: fetch(assessment, :labels),
           ai_answers: fetch(assessment, :ai_answers),
           source: fetch(assessment, :source)
         }
       }}
    else
      {:error, errors}
    end
  end

  defp check(errors, field, value, valid?, message) do
    if valid?.(value), do: errors, else: Map.update(errors, field, [message], &[message | &1])
  end

  defp posts?(posts), do: is_list(posts) and Enum.all?(posts, &is_map/1)
  defp labels?(labels), do: is_list(labels) and Enum.all?(labels, &is_binary/1)

  defp answers?(nil), do: true
  defp answers?(%{}), do: true
  defp answers?(_), do: false

  defp source?(nil), do: true
  defp source?(source) when is_atom(source), do: true
  defp source?(source) when is_binary(source), do: true
  defp source?(_), do: false

  defp check_assessment(errors, assessment) when is_map(assessment) do
    errors
    |> check(:assessment, fetch(assessment, :score), &is_number/1, "score must be a number")
    |> check(
      :assessment,
      fetch(assessment, :labels),
      &labels?/1,
      "labels must be a list of strings"
    )
    |> check(
      :assessment,
      fetch(assessment, :ai_answers),
      &answers?/1,
      "ai_answers must be a map or nil"
    )
    |> check(
      :assessment,
      fetch(assessment, :source),
      &source?/1,
      "source must be an atom, a string, or nil"
    )
  end

  defp check_assessment(errors, _assessment),
    do: Map.update(errors, :assessment, ["must be a map"], &["must be a map" | &1])

  ## Account and posts

  defp upsert_account(state, %{feed_id: feed_id, handle: handle} = attrs, now) do
    {account, state} =
      case Enum.find(Map.values(state.accounts), &(&1.feed_id == feed_id and &1.handle == handle)) do
        nil ->
          {id, state} = State.next_id(state, "acc")
          {%Account{id: id, feed_id: feed_id, handle: handle, first_seen_at: now}, state}

        account ->
          {account, state}
      end

    {posts, state} = posts(state, account.id, attrs.posts)
    %{score: score, labels: labels} = attrs.assessment

    account = %{
      account
      | risk_score: score |> round() |> max(0) |> min(100),
        signals: Enum.map(labels, &signal/1),
        last_seen_at: newest(posts) || now,
        assessment: Map.take(attrs.assessment, [:ai_answers, :source])
    }

    {account,
     %{
       state
       | accounts: Map.put(state.accounts, account.id, account),
         posts: Map.put(state.posts, account.id, posts)
     }}
  end

  # The scorer gives no breakdown of its score, so signals carry no contribution.
  defp signal(label),
    do: %Signal{name: label, explanation: "Heuristic label from the scorer.", contribution: nil}

  defp posts(state, account_id, raw_posts) do
    {fresh, state} =
      Enum.flat_map_reduce(raw_posts, state, fn raw, state ->
        case posted_at(fetch(raw, :published_at)) do
          nil ->
            {[], state}

          at ->
            {id, state} = State.next_id(state, "post")

            post = %Post{
              id: id,
              account_id: account_id,
              post_id: to_string(fetch(raw, :id)),
              posted_at: at,
              text: fetch(raw, :text),
              domain: raw |> fetch(:urls) |> List.wrap() |> Enum.find_value(&host/1)
            }

            {[post], state}
        end
      end)

    # Re-assessments merge into history: the new batch wins per platform post
    # id, and the list stays newest-first.
    merged =
      (fresh ++ Map.get(state.posts, account_id, []))
      |> Enum.uniq_by(& &1.post_id)
      |> Enum.sort_by(& &1.posted_at, {:desc, DateTime})

    {merged, state}
  end

  defp newest([]), do: nil
  defp newest([post | _]), do: post.posted_at

  defp posted_at(%DateTime{} = at), do: DateTime.truncate(at, :second)
  defp posted_at(unix) when is_integer(unix), do: DateTime.from_unix!(unix)

  defp posted_at(text) when is_binary(text) do
    case DateTime.from_iso8601(text) do
      {:ok, at, _offset} -> DateTime.truncate(at, :second)
      _ -> nil
    end
  end

  defp posted_at(_), do: nil

  defp host(url) when is_binary(url), do: URI.parse(url).host
  defp host(_), do: nil

  ## Finding

  defp finding(state, feed, account, assessment, now) do
    network_id = "net-scorer-" <> account.id
    handle = feed.format_handle(account)

    finding = %{
      trigger: @trigger,
      severity: "medium",
      title: "Scorer assessment for #{handle}",
      observed_at: now,
      evidence: evidence(account, assessment)
    }

    if Map.has_key?(state.networks, network_id) do
      Map.put(finding, :network_id, network_id)
    else
      Map.put(finding, :new_network, %{
        id: network_id,
        name: "#{handle} (unsorted)",
        member_ids: [account.id],
        confidence: account.risk_score,
        platforms: [account.feed_id]
      })
    end
  end

  defp evidence(account, assessment) do
    lines =
      [
        "source: #{assessment.source}",
        "score: #{assessment.score}",
        "labels: #{labels(assessment.labels)}"
      ] ++ answers(assessment.ai_answers)

    for line <- lines,
        do: %{explanation: line, strength: "moderate", kind: "other", account_ids: [account.id]}
  end

  defp labels([]), do: "none"
  defp labels(labels), do: Enum.join(labels, ", ")

  defp answers(nil), do: ["ai_answers: none (AI unavailable)"]

  defp answers(answers) when is_map(answers) do
    answers
    |> Enum.sort_by(fn {name, _} -> to_string(name) end)
    |> Enum.map(fn {name, answer} -> "#{name}: #{answer_value(answer)}" end)
  end

  # An answer looks like %{"type" => "noul", "noul" => 0.8}: the value sits under its type.
  defp answer_value(%{} = answer) do
    case fetch(answer, :type) do
      type when is_binary(type) ->
        answer |> Map.get(type) |> format_value(answer)

      type when is_atom(type) and not is_nil(type) ->
        answer |> fetch(type) |> format_value(answer)

      _ ->
        inspect(answer)
    end
  end

  defp answer_value(answer), do: inspect(answer)

  defp format_value(nil, answer), do: inspect(answer)
  defp format_value(value, _answer) when is_binary(value), do: value
  defp format_value(value, _answer), do: inspect(value)

  defp fetch(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
