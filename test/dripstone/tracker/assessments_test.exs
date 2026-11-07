defmodule Dripstone.Tracker.AssessmentsTest do
  use ExUnit.Case, async: true

  alias Dripstone.Tracker.{Assessments, State}

  @now ~U[2026-11-07 12:00:00Z]

  # Shapes as returned by Dripstone.Scorer.assess/2.
  @answers %{
    "is_bot" => %{"type" => "noul", "noul" => 0.8},
    "topic" => %{"type" => "choice", "choice" => "crypto"},
    "spam" => %{"type" => "score", "score" => 0.7},
    "coordinated" => %{"type" => "noul", "noul" => 0.6},
    "relation" => %{"type" => "choice", "choice" => "shared-link"}
  }

  defp posts do
    [
      %{
        id: "x1",
        handle: "promo",
        text: "Deal https://deals.example/a",
        urls: ["https://deals.example/a"],
        published_at: ~U[2026-11-01 10:00:00Z]
      },
      %{
        id: "x2",
        handle: "promo",
        text: "No link",
        urls: [],
        published_at: "2026-11-01T11:00:00Z"
      },
      %{id: "x3", handle: "promo", text: "Undated", urls: [], published_at: nil}
    ]
  end

  defp attrs(assessment \\ %{}) do
    %{
      feed_id: "x",
      handle: "promo",
      posts: posts(),
      assessment:
        Map.merge(
          %{
            score: 72,
            labels: ["high_link_ratio", "regular_timing"],
            ai_answers: @answers,
            source: :heuristics_plus_ai
          },
          assessment
        )
    }
  end

  test "creates the account, its posts, a placeholder network and an alert" do
    assert {:ok, %{action: :created, alert: alert, network_id: network_id}, state} =
             Assessments.record(%State{}, attrs(), @now)

    [account] = Map.values(state.accounts)
    assert %{feed_id: "x", handle: "promo", risk_score: 72} = account
    assert Enum.map(account.signals, & &1.name) == ["high_link_ratio", "regular_timing"]
    assert Enum.all?(account.signals, &is_nil(&1.contribution))
    assert account.assessment == %{ai_answers: @answers, source: :heuristics_plus_ai}
    assert account.last_seen_at == ~U[2026-11-01 11:00:00Z]

    # The undated post is skipped; the rest are newest first.
    assert [%{post_id: "x2", domain: nil}, %{post_id: "x1", domain: "deals.example"}] =
             state.posts[account.id]

    network = state.networks[network_id]
    assert network.name == "@promo (unsorted)"
    assert network.member_ids == [account.id]

    assert alert.trigger_id == "scorer_assessment"
    assert alert.severity == :medium
    assert alert.title == "Scorer assessment for @promo"

    lines = Enum.map(alert.evidence, & &1.explanation)

    for line <- [
          "source: heuristics_plus_ai",
          "score: 72",
          "labels: high_link_ratio, regular_timing",
          "is_bot: 0.8",
          "topic: crypto",
          "spam: 0.7",
          "coordinated: 0.6",
          "relation: shared-link"
        ],
        do: assert(line in lines)
  end

  test "a heuristics-only result says the AI was unavailable" do
    {:ok, %{alert: alert}, _state} =
      Assessments.record(
        %State{},
        attrs(%{ai_answers: nil, source: :heuristics_only, labels: []}),
        @now
      )

    lines = Enum.map(alert.evidence, & &1.explanation)
    assert "source: heuristics_only" in lines
    assert "labels: none" in lines
    assert "ai_answers: none (AI unavailable)" in lines
  end

  test "assessing the same handle again updates the account and the open alert" do
    {:ok, %{alert: first}, state} = Assessments.record(%State{}, attrs(), @now)

    assert {:ok, %{action: :merged, alert: second}, state} =
             Assessments.record(state, attrs(%{score: 40, labels: []}), @now)

    assert second.id == first.id
    assert [%{risk_score: 40, signals: []}] = Map.values(state.accounts)
    assert map_size(state.networks) == 1
    assert "score: 40" in Enum.map(second.evidence, & &1.explanation)
  end

  test "string-keyed attrs are accepted; malformed attrs return errors without touching state" do
    stringy =
      attrs()
      |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
      |> Map.update!("assessment", &Map.new(&1, fn {k, v} -> {Atom.to_string(k), v} end))

    assert {:ok, _, state} = Assessments.record(%State{}, stringy, @now)
    assert [%{handle: "promo"}] = Map.values(state.accounts)

    assert {:error, %{assessment: [_]}} =
             Assessments.record(%State{}, %{"feed_id" => "x", "handle" => "promo"}, @now)

    assert {:error, %{assessment: errors}} =
             Assessments.record(%State{}, attrs(%{ai_answers: "junk", source: 42}), @now)

    assert "ai_answers must be a map or nil" in errors
    assert "source must be an atom, a string, or nil" in errors

    assert {:error, %{base: [_]}} = Assessments.record(%State{}, "nope", @now)

    # Prior good state still records fine afterwards.
    assert {:ok, %{action: :merged}, _} = Assessments.record(state, attrs(), @now)
  end

  test "an unknown feed is rejected" do
    assert {:error, %{feed_id: [_]}} =
             Assessments.record(%State{}, %{attrs() | feed_id: "myspace"}, @now)
  end
end
