defmodule DripstoneWeb.AnswersUiTest do
  # Scenarios from the alert-inbox, network-views and account-views specs
  # deltas: what the screens show of the decision model's answers. Reports findings
  # into the app-wide store, so not async.
  use DripstoneWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Dripstone.Tracker
  alias Dripstone.Tracker.{SampleStore, State}

  setup :register_and_log_in_user

  setup do
    previous = SampleStore.get_state()
    :ok = SampleStore.put_state(%State{})
    on_exit(fn -> SampleStore.put_state(previous) end)
    :ok
  end

  defp noul(p), do: %{"type" => "noul", "noul" => p}
  defp choice(label, c), do: %{"type" => "choice", "choice" => label, "confidence" => c}
  defp now, do: DateTime.utc_now() |> DateTime.to_iso8601()

  defp group(handles, answers, extra \\ %{}) do
    {:ok, result} =
      %{
        "kind" => "group",
        "observed_at" => now(),
        "model" => "jev-1.13",
        "accounts" => Enum.map(handles, &%{"feed_id" => "x", "handle" => &1}),
        "answers" => answers
      }
      |> Map.merge(extra)
      |> Tracker.report_finding()

    result
  end

  defp account_finding(handle, attrs) do
    {:ok, %{account_ids: [id]}} =
      %{
        "kind" => "account",
        "observed_at" => now(),
        "account" => %{"feed_id" => "x", "handle" => handle}
      }
      |> Map.merge(attrs)
      |> Tracker.report_finding()

    id
  end

  describe "alert detail" do
    test "lists the answers behind the alert (spec: Answers behind the alert)", %{conn: conn} do
      answers = %{"coordinated" => noul(0.88), "relation" => choice("shared-link", 0.7)}
      %{alerts: [%{alert: alert}]} = group(~w(a b c), answers)

      {:ok, view, _html} = live(conn, "/alerts/#{alert.id}")

      assert has_element?(view, "#alert-answers-answer-coordinated", "88%")
      assert has_element?(view, "#alert-answers-answer-relation", "shared-link")
      assert has_element?(view, "#alert-answers-answer-relation", "70% sure")
      assert has_element?(view, "#alert-answers-source", "jev-1.13")
      refute has_element?(view, "#alert-answers-heuristics-only")
    end

    test "says when only heuristics were available (spec: No AI answers)", %{conn: conn} do
      %{network_id: network_id} = group(~w(a b c), %{"coordinated" => noul(0.9)})

      %{alerts: [%{alert: shift}]} =
        group(~w(a b c), nil, %{
          "network_id" => network_id,
          "model" => nil,
          "heuristics" => %{"domains" => [%{"domain" => "deals.example", "share" => 0.7}]}
        })

      assert shift.trigger_id == "promotion_shift"
      {:ok, view, _html} = live(conn, "/alerts/#{shift.id}")

      assert has_element?(view, "#alert-answers-heuristics-only")
      assert has_element?(view, "#ai-rationale #no-rationale")
    end
  end

  describe "network summary" do
    test "shows the latest assessment (spec: Assessed network)", %{conn: conn} do
      %{network_id: id} =
        group(~w(a b c), %{"coordinated" => noul(0.88), "relation" => choice("shared-link", 0.7)})

      {:ok, _} =
        Tracker.report_finding(%{
          "kind" => "trend",
          "observed_at" => now(),
          "network_id" => id,
          "answers" => %{"trajectory" => choice("forming", 0.6)}
        })

      {:ok, view, _html} = live(conn, "/networks/#{id}")

      assert has_element?(view, "#network-assessment-coordinated", "88%")
      assert has_element?(view, "#network-assessment-relation", "Shared link")
      assert has_element?(view, "#network-assessment-trajectory", "Forming")
      refute has_element?(view, "#network-assessment-none")
    end

    test "says when a network was never assessed (spec: Never assessed)", %{conn: conn} do
      %{network_id: id} = group(~w(a b), %{"coordinated" => noul(0.9)})

      # Clear the assessment the finding left, as for a network that predates findings.
      state = SampleStore.get_state()
      :ok = SampleStore.put_state(put_in(state.networks[id].assessment, nil))

      {:ok, view, _html} = live(conn, "/networks/#{id}")
      assert has_element?(view, "#network-assessment-none")
    end

    test "the graph legend names the relation link types (spec: Relation labels in the legend)",
         %{conn: conn} do
      %{network_id: id} =
        group(~w(a b c), %{"coordinated" => noul(0.9), "relation" => choice("repost-ring", 0.8)})

      group(~w(a b c), %{"coordinated" => noul(0.9), "relation" => choice("timing-sync", 0.8)}, %{
        "network_id" => id
      })

      {:ok, view, _html} = live(conn, "/networks/#{id}?view=graph")

      assert has_element?(view, "#toggle-repost_ring", "Repost ring")
      assert has_element?(view, "#toggle-timing_sync", "Timing sync")
      assert has_element?(view, ~s(#toggle-repost_ring span[style*="--color-link-repost-ring"]))
      assert has_element?(view, ~s(#network-graph line[data-kind=repost_ring]))
      assert has_element?(view, ~s(#network-graph line[data-kind=timing_sync]))
    end
  end

  describe "account detail" do
    test "signals without contributions show their value (spec: Signals without contributions)",
         %{conn: conn} do
      id =
        account_finding("promo", %{
          "model" => "jev-1.13",
          "heuristics" => %{"score" => 70, "labels" => ["regular_timing"]},
          "answers" => %{"is_bot" => noul(0.81)}
        })

      {:ok, view, _html} = live(conn, "/accounts/#{id}")

      assert has_element?(view, "#signal-0", "Regular timing")
      assert has_element?(view, "#signal-1", "Bot-like")
      assert has_element?(view, "#signal-1-value", "81%")
      assert has_element?(view, "#account-answers-answer-is_bot", "81%")
    end

    test "linked accounts show the relation link type (spec: Account with links)", %{conn: conn} do
      handles = ["hub" | for(i <- 1..11, do: "ring#{i}")]

      %{account_ids: [hub | _]} =
        group(handles, %{"coordinated" => noul(0.9), "relation" => choice("repost-ring", 0.8)})

      {:ok, view, _html} = live(conn, "/accounts/#{hub}")

      assert has_element?(view, "#linked-accounts", "Linked accounts (11)")
      assert has_element?(view, ~s(#links [data-kind=repost_ring]), "Repost ring")
    end

    test "an account finding updates an open account page live", %{conn: conn} do
      id = account_finding("live", %{"heuristics" => %{"score" => 20}})
      {:ok, view, _html} = live(conn, "/accounts/#{id}")
      refute has_element?(view, "#account-answers-answer-is_bot")

      account_finding("live", %{"answers" => %{"is_bot" => noul(0.9)}})
      assert has_element?(view, "#account-answers-answer-is_bot", "90%")
    end
  end
end
