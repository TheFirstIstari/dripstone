defmodule Dripstone.Tracker.ReportTest do
  use ExUnit.Case, async: true

  alias Dripstone.Tracker.{Network, Report, State}

  @t "2026-11-07T19:40:00Z"

  defp state do
    %State{
      networks: %{
        "net-1" => %Network{id: "net-1", name: "One"},
        "net-old" => %Network{id: "net-old", name: "Old", retired_into: "net-1"}
      }
    }
  end

  defp group(extra \\ %{}) do
    Map.merge(
      %{
        "kind" => "group",
        "observed_at" => @t,
        "accounts" => [
          %{"feed_id" => "x", "handle" => "a"},
          %{"feed_id" => "x", "handle" => "b"}
        ],
        "answers" => %{"coordinated" => %{"type" => "noul", "noul" => 0.9}}
      },
      extra
    )
  end

  test "accepts a decoded JSON group finding" do
    assert {:ok, %Report{kind: :group, accounts: [_, _], answers: %{"coordinated" => _}} = r} =
             Report.cast(group(), state())

    assert r.observed_at == ~U[2026-11-07 19:40:00Z]
    assert r.heuristics == %{score: nil, labels: [], domains: []}
  end

  test "accepts an account finding with posts and heuristics, and null answers" do
    attrs = %{
      kind: "account",
      observed_at: @t,
      account: %{feed_id: "reddit", handle: "bob"},
      posts: [%{id: 7, published_at: @t, urls: ["https://deals.example/a"], text: "hi"}],
      heuristics: %{score: 72, labels: ["regular_timing"]},
      answers: nil
    }

    assert {:ok, %Report{kind: :account, answers: nil, posts: [post]} = r} =
             Report.cast(attrs, state())

    assert post.id == "7"
    assert r.account == %{feed_id: "reddit", handle: "bob"}
    assert r.heuristics.score == 72
  end

  describe "rejections (spec: Answer-shaped finding validation)" do
    test "unknown kind" do
      assert {:error, %{kind: ["must be account, group or trend"]}} =
               Report.cast(group(%{"kind" => "does-not-exist"}), state())
    end

    test "no observation time" do
      assert {:error, %{observed_at: ["can't be blank"]}} =
               Report.cast(Map.delete(group(), "observed_at"), state())
    end

    test "an account on an unknown feed" do
      attrs = %{
        "kind" => "account",
        "observed_at" => @t,
        "account" => %{"feed_id" => "myspace", "handle" => "tom"}
      }

      assert {:error, %{account: ["unknown feed \"myspace\""]}} = Report.cast(attrs, state())
    end

    test "a group of fewer than two different accounts" do
      one = %{"feed_id" => "x", "handle" => "a"}

      assert {:error, %{accounts: ["a group needs at least two different accounts"]}} =
               Report.cast(group(%{"accounts" => [one, one]}), state())
    end

    test "a group or trend naming an unknown or merged network" do
      assert {:error, %{network_id: ["unknown network \"net-9\""]}} =
               Report.cast(group(%{"network_id" => "net-9"}), state())

      assert {:error, %{network_id: [_]}} =
               Report.cast(group(%{"network_id" => "net-old"}), state())

      assert {:error, %{network_id: ["a trend finding needs a network_id"]}} =
               Report.cast(%{"kind" => "trend", "observed_at" => @t}, state())
    end

    test "a malformed answer (spec: Malformed answer)" do
      answers = %{"coordinated" => %{"type" => "noul", "noul" => 1.4}}

      assert {:error, %{answers: ["coordinated: noul must be a number from 0 to 1"]}} =
               Report.cast(group(%{"answers" => answers}), state())
    end

    test "malformed heuristics" do
      assert {:error, %{heuristics: [_]}} =
               Report.cast(
                 group(%{"heuristics" => %{"domains" => [%{"domain" => "a", "share" => 2}]}}),
                 state()
               )

      assert {:error, %{heuristics: [_]}} =
               Report.cast(group(%{"heuristics" => %{"score" => 120}}), state())
    end

    test "mixed key types and non-maps" do
      assert {:error, %{base: [_]}} = Report.cast(Map.put(group(), :kind, "group"), state())
      assert {:error, %{base: [_]}} = Report.cast("nope", state())
    end
  end
end
