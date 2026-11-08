defmodule Dripstone.Tracker.AnswersTest do
  use ExUnit.Case, async: true

  alias Dripstone.Tracker.Answers

  # The answers from the live check against jev-1.13-free on 2026-11-07
  # (add-jev-intake task 1.3, now archived), verbatim.
  @live %{
    "is_bot" => %{"type" => "noul", "noul" => 0.83},
    "topic" => %{
      "type" => "choice",
      "choice" => "shopping",
      "confidence" => 1,
      "probabilities" => %{"crypto" => 0, "shopping" => 1, "other" => 0}
    },
    "spam" => %{
      "type" => "score",
      "score" => 2,
      "confidence" => 1,
      "legend" => %{"0" => "not spam", "1" => "somewhat spammy", "2" => "heavy spam"},
      "probabilities" => %{"0" => 0, "1" => 0, "2" => 1}
    }
  }

  test "parses the recorded live response" do
    assert {:ok, answers} = Answers.parse(@live)

    assert Answers.noul(answers, "is_bot") == 0.83
    assert Answers.choice(answers, "topic") == {"shopping", 1.0}
    assert Answers.score(answers, "spam") == 1.0
    assert Answers.display(answers["spam"]) == "heavy spam (2 of 2)"
  end

  test "nil means the AI was unavailable" do
    assert Answers.parse(nil) == {:ok, nil}
    assert Answers.noul(nil, "is_bot") == nil
  end

  describe "score normalization" do
    test "divides the expected level by the highest level (spec: Score normalized)" do
      legend = %{"0" => "none", "1" => "some", "2" => "heavy"}

      {:ok, answers} =
        Answers.parse(%{"spam" => %{"type" => "score", "score" => 1.5, "legend" => legend}})

      assert Answers.score(answers, "spam") == 0.75
    end

    test "falls back to probabilities, then to the app's known level count" do
      {:ok, a} =
        Answers.parse(%{
          "x" => %{"type" => "score", "score" => 1, "probabilities" => %{"0" => 0, "1" => 1}}
        })

      assert Answers.score(a, "x") == 1.0

      {:ok, b} = Answers.parse(%{"spam" => %{"type" => "score", "score" => 1}})
      assert Answers.score(b, "spam") == 0.5
    end

    test "a score with no way to tell its levels is malformed" do
      assert {:error, "rating: " <> _} =
               Answers.parse(%{"rating" => %{"type" => "score", "score" => 1}})
    end

    test "a score above the highest level is malformed" do
      legend = %{"0" => "a", "1" => "b"}

      assert {:error, "spam: score is above the highest level"} =
               Answers.parse(%{"spam" => %{"type" => "score", "score" => 3, "legend" => legend}})
    end
  end

  test "an answer to a question the app doesn't use is kept (spec: Unknown question kept)" do
    {:ok, answers} =
      Answers.parse(%{"language" => %{"type" => "choice", "choice" => "en", "confidence" => 0.9}})

    assert %{"language" => %{type: :choice, label: "en"}} = answers
    assert Answers.display(answers["language"]) == "en (90%)"
  end

  test "an unknown answer type is kept for display" do
    assert {:ok, %{"where" => %{type: :other}}} =
             Answers.parse(%{"where" => %{"type" => "box", "box" => %{"top" => 0.1}}})
  end

  test "out-of-range and malformed answers are rejected with the question name" do
    assert {:error, "coordinated: noul must be a number from 0 to 1"} =
             Answers.parse(%{"coordinated" => %{"type" => "noul", "noul" => 1.4}})

    assert {:error, "relation: choice must be a non-empty string"} =
             Answers.parse(%{"relation" => %{"type" => "choice", "choice" => ""}})

    assert {:error, "topic: confidence must be a number from 0 to 1"} =
             Answers.parse(%{
               "topic" => %{"type" => "choice", "choice" => "x", "confidence" => 2}
             })

    assert {:error, "is_bot: must be a map"} = Answers.parse(%{"is_bot" => 0.8})
    assert {:error, "is_bot: type is missing"} = Answers.parse(%{"is_bot" => %{"noul" => 0.8}})
    assert {:error, _} = Answers.parse("not a map")
  end

  test "rejects maps with more than 64 answers" do
    oversized =
      Map.new(1..65, fn i -> {"q#{i}", %{"type" => "noul", "noul" => 0.5}} end)

    assert {:error, "must have at most 64 answers"} = Answers.parse(oversized)

    ok = Map.new(1..64, fn i -> {"q#{i}", %{"type" => "noul", "noul" => 0.5}} end)
    assert {:ok, parsed} = Answers.parse(ok)
    assert map_size(parsed) == 64
  end

  test "atom keys work as well as string keys" do
    assert {:ok, answers} = Answers.parse(%{coordinated: %{type: :noul, noul: 0.9}})
    assert Answers.noul(answers, "coordinated") == 0.9
  end

  test "relation maps known labels to link kinds and ignores unknown ones" do
    {:ok, a} =
      Answers.parse(%{
        "relation" => %{"type" => "choice", "choice" => "timing-sync", "confidence" => 0.7}
      })

    assert Answers.relation(a) == {:timing_sync, "timing-sync", 0.7}

    {:ok, b} = Answers.parse(%{"relation" => %{"type" => "choice", "choice" => "mystery"}})
    assert Answers.relation(b) == nil
  end
end
