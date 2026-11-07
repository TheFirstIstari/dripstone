defmodule Dripstone.ScorerTest do
  # async: false — Req.Test stubs are global.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  @stub Dripstone.ScorerTestStub

  setup do
    old = Application.get_env(:dripstone, Dripstone.AIClient, [])

    Application.put_env(:dripstone, Dripstone.AIClient,
      base_url: "http://ai.test",
      model: "test-model",
      api_key: "test-key"
    )

    on_exit(fn -> Application.put_env(:dripstone, Dripstone.AIClient, old) end)
    :ok
  end

  defp post(i, opts \\ []) do
    %{
      id: "p#{i}",
      handle: "@bot",
      text: Keyword.get(opts, :text, "hello #{i}"),
      urls: Keyword.get(opts, :urls, []),
      published_at:
        Keyword.get_lazy(opts, :published_at, fn ->
          DateTime.add(~U[2026-10-01 10:00:00Z], i * 3600)
        end)
    }
  end

  # Frozen holdout slice (`test/fixtures/holdout_posts.json`, issue #46):
  # excluded from all scorer tuning; reported metrics come from it.
  defp holdout_posts do
    path = Path.join([File.cwd!(), "test", "fixtures", "holdout_posts.json"])

    path
    |> File.read!()
    |> Jason.decode!()
    |> Enum.map(fn %{"published_at" => ts} = item ->
      {:ok, dt, _} = DateTime.from_iso8601(ts)

      %{
        id: item["id"],
        handle: item["handle"],
        text: item["text"],
        urls: item["urls"],
        published_at: dt
      }
    end)
  end

  test "score/1 empty posts scores zero with no labels" do
    assert %{score: 0, labels: []} = Dripstone.Scorer.score([])
  end

  test "score/1 volume, link ratio, and regular timing raise the score" do
    quiet = Enum.map(1..3, &post(&1))
    loud = Enum.map(1..50, &post(&1, urls: ["https://example.com/x"]))

    assert %{score: low} = Dripstone.Scorer.score(quiet)
    assert %{score: high, labels: labels} = Dripstone.Scorer.score(loud)
    assert high > low
    assert "high_volume" in labels
    assert "high_link_ratio" in labels
    assert "regular_timing" in labels
    assert high >= 0 and high <= 100
  end

  test "score/1 irregular timing scores below regular timing" do
    regular = Enum.map(1..10, &post(&1))

    jittered =
      [0, 1, 2, 50, 51, 52, 200, 201, 202, 500]
      |> Enum.with_index(1)
      |> Enum.map(fn {h, i} ->
        post(i, published_at: DateTime.add(~U[2026-10-01 10:00:00Z], h * 3600))
      end)

    assert %{score: r} = Dripstone.Scorer.score(regular)
    assert %{score: j} = Dripstone.Scorer.score(jittered)
    assert r > j
  end

  test "assess/2 merges heuristics with AI answers" do
    Req.Test.stub(@stub, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      body = Jason.decode!(raw)
      assert Map.has_key?(body["questions"], "is_bot")
      assert Map.has_key?(body["questions"], "topic")
      assert Map.has_key?(body["questions"], "spam")
      refute Map.has_key?(body["questions"], "coordinated")
      refute Map.has_key?(body["questions"], "relation")

      Req.Test.json(conn, %{
        "answers" => %{
          "is_bot" => %{"type" => "noul", "noul" => 0.8},
          "topic" => %{"type" => "choice", "choice" => "crypto"},
          "spam" => %{"type" => "score", "score" => 0.7}
        }
      })
    end)

    result = Dripstone.Scorer.assess([post(1)], plug: {Req.Test, @stub})
    assert result.source == :heuristics_plus_ai
    assert is_integer(result.score)
    assert is_list(result.labels)
    assert result.ai_answers["topic"]["choice"] == "crypto"
    refute Map.has_key?(result.ai_answers, "relation")
  end

  test "score/1 and assess/2 reject non-list input" do
    assert {:error, {:invalid_args, _}} = Dripstone.Scorer.score(nil)
    assert {:error, {:invalid_args, _}} = Dripstone.Scorer.score(%{})
    assert {:error, {:invalid_args, _}} = Dripstone.Scorer.assess(nil)
    assert {:error, {:invalid_args, _}} = Dripstone.Scorer.assess(%{}, plug: {Req.Test, @stub})
  end

  test "holdout slice scores deterministically and is never tuned against" do
    posts = holdout_posts()
    assert length(posts) == 6
    assert %{score: s1} = Dripstone.Scorer.score(posts)
    assert %{score: s2} = Dripstone.Scorer.score(posts)
    assert s1 == s2
  end

  test "assess/2 falls back to heuristics-only on AI error" do
    Req.Test.stub(@stub, fn conn -> Req.Test.transport_error(conn, :timeout) end)

    assert capture_log(fn ->
             result = Dripstone.Scorer.assess([post(1)], plug: {Req.Test, @stub})
             assert result.source == :heuristics_only
             assert result.ai_answers == nil
             assert is_integer(result.score)
             send(self(), {:assess_result, result})
           end) =~ "AIClient"

    assert_received {:assess_result, %{source: :heuristics_only}}
  end
end
