defmodule Dripstone.Tracker.RulesTest do
  # Scenarios from openspec/specs/alert-intake/spec.md (added by add-jev-intake).
  # Some tests change the Rules config, so not async.
  use ExUnit.Case, async: false

  import Dripstone.TrackerFixtures, only: [dismiss: 3]

  alias Dripstone.Tracker.{Account, Report, Rules, State}

  @t ~U[2026-11-07 19:40:00Z]

  defp later(minutes), do: DateTime.add(@t, minutes * 60, :second)

  defp noul(p), do: %{"type" => "noul", "noul" => p}
  defp choice(label, c \\ 0.7), do: %{"type" => "choice", "choice" => label, "confidence" => c}
  defp ref(handle, feed \\ "x"), do: %{"feed_id" => feed, "handle" => handle}

  defp group(handles, answers, extra \\ %{}) do
    Map.merge(
      %{
        "kind" => "group",
        "observed_at" => @t,
        "model" => "jev-1.13",
        "accounts" => Enum.map(handles, &ref/1),
        "answers" => answers
      },
      extra
    )
  end

  defp trend(network_id, answers, at \\ @t),
    do: %{
      "kind" => "trend",
      "observed_at" => at,
      "model" => "jev-1.13",
      "network_id" => network_id,
      "answers" => answers
    }

  defp account(handle, extra) do
    Map.merge(
      %{"kind" => "account", "observed_at" => @t, "account" => ref(handle)},
      extra
    )
  end

  defp run(state, attrs, now \\ @t) do
    {:ok, report} = Report.cast(attrs, state)
    {:ok, result, state} = Rules.run(state, report, now)
    {result, state}
  end

  defp handles(n, prefix \\ "h"), do: for(i <- 1..n, do: "#{prefix}#{i}")

  defp account_id(state, handle),
    do: Enum.find_value(Map.values(state.accounts), &(&1.handle == handle && &1.id))

  defp lines(alert), do: Enum.map(alert.evidence, & &1.explanation)

  # A network created from a coordinated group of `n` handles.
  defp network_of(n, answers \\ %{"coordinated" => noul(0.9)}, extra \\ %{}) do
    {%{alerts: [%{alert: alert}], network_id: id}, state} =
      run(%State{}, group(handles(n), answers, extra))

    {state, id, alert}
  end

  describe "account findings" do
    test "a new account is created from heuristics and answers (spec: New account assessed)" do
      answers = %{
        "is_bot" => noul(0.81),
        "spam" => %{
          "type" => "score",
          "score" => 1.43,
          "legend" => %{"0" => "none", "1" => "some", "2" => "heavy"}
        },
        "topic" => choice("crypto", 0.74)
      }

      {result, state} =
        run(
          %State{},
          account("promo_daily", %{
            "heuristics" => %{"score" => 72, "labels" => ["regular_timing"]},
            "answers" => answers,
            "model" => "jev-1.13"
          })
        )

      assert %{kind: :account, alerts: [], account_ids: [id]} = result
      account = state.accounts[id]

      assert %Account{feed_id: "x", handle: "promo_daily", risk_score: 72, topic: "crypto"} =
               account

      assert Enum.map(account.signals, &{&1.name, &1.value, &1.contribution}) == [
               {"Regular timing", nil, nil},
               {"Bot-like", "81%", nil},
               {"Spam", "some (1.43 of 2)", nil},
               {"Topic", "crypto (74%)", nil}
             ]

      assert account.assessment.model == "jev-1.13"
      assert state.alerts == %{}
    end

    test "account findings raise no alert, however bot-like" do
      {result, state} =
        run(
          %State{},
          account("bot", %{
            "heuristics" => %{"score" => 88},
            "answers" => %{"is_bot" => noul(0.97)}
          })
        )

      assert result.alerts == []
      assert [%{risk_score: 88}] = Map.values(state.accounts)
    end

    test "without AI answers the account is updated from heuristics alone" do
      {result, state} =
        run(
          %State{},
          account("plain", %{"heuristics" => %{"score" => 30, "labels" => ["high_volume"]}})
        )

      assert result.alerts == []
      assert [%{risk_score: 30, signals: [%{name: "High volume"}]}] = Map.values(state.accounts)
    end

    test "re-assessment keeps earlier posts (spec: Re-assessment keeps earlier posts)" do
      post = fn id, minute, text ->
        %{"id" => id, "published_at" => DateTime.to_iso8601(later(minute)), "text" => text}
      end

      {_, state} =
        run(%State{}, account("p", %{"posts" => [post.("x1", 1, "a"), post.("x2", 2, "b")]}))

      {_, state} =
        run(state, account("p", %{"posts" => [post.("x2", 2, "b2"), post.("x3", 3, "c")]}))

      [posts] = Map.values(state.posts)
      assert Enum.map(posts, &{&1.post_id, &1.text}) == [{"x3", "c"}, {"x2", "b2"}, {"x1", "a"}]
    end

    test "re-reporting the same posts keeps stable ids and seq" do
      post = fn id, minute ->
        %{"id" => id, "published_at" => DateTime.to_iso8601(later(minute)), "text" => id}
      end

      posts = [post.("x1", 1), post.("x2", 2)]
      {_, state} = run(%State{}, account("p", %{"posts" => posts}))
      [before] = Map.values(state.posts)
      ids = Enum.map(before, &{&1.post_id, &1.id})
      seq = state.seq

      {_, state} = run(state, account("p", %{"posts" => posts}))
      [after_posts] = Map.values(state.posts)

      assert Enum.map(after_posts, &{&1.post_id, &1.id}) == ids
      # Finding id still minted once per report; no post ids burned.
      assert state.seq == seq + 1
    end

    test "posts with unparseable timestamps are kept at the end, never dropped" do
      posts = [
        %{"id" => "x1", "published_at" => DateTime.to_iso8601(later(1))},
        %{"id" => "x3", "published_at" => "not a date"},
        %{"id" => "x2", "published_at" => DateTime.to_iso8601(later(2))}
      ]

      {_, state} = run(%State{}, account("p", %{"posts" => posts}))

      [stored] = Map.values(state.posts)

      assert [%{post_id: "x2"}, %{post_id: "x1"}, %{post_id: "x3", posted_at: nil}] = stored
      assert [%{last_seen_at: last_seen}] = Map.values(state.accounts)
      assert last_seen == later(2)
    end
  end

  describe "group findings" do
    test "coordinated strangers form a new network (spec: Coordinated strangers)" do
      {result, state} = run(%State{}, group(handles(4), %{"coordinated" => noul(0.91)}))

      assert [%{action: :created, alert: alert}] = result.alerts
      assert alert.trigger_id == "new_network"
      assert alert.severity == :high
      assert alert.model == "jev-1.13"
      assert %{"coordinated" => %{type: :noul}} = alert.answers

      network = state.networks[result.network_id]
      assert network.status == :suspected
      assert network.confidence == 91
      assert length(network.member_ids) == 4
      assert network.assessment.coordinated == 0.91
    end

    test "not coordinated: nothing is created (spec: Not coordinated)" do
      {result, state} = run(%State{}, group(handles(3), %{"coordinated" => noul(0.4)}))

      assert %{alerts: [], network_id: nil, reason: :below_threshold} = result
      assert state.networks == %{}
      assert state.alerts == %{}
    end

    test "no AI answers: reported as such" do
      {result, _state} = run(%State{}, group(handles(3), nil))
      assert result.reason == :no_answers
    end

    test "membership answers pick the members (spec: Membership answers pick the members)" do
      answers = %{
        "coordinated" => noul(0.9),
        "member:x:h4" => noul(0.2),
        "member:x:h5" => noul(0.5),
        "member:x:h1" => noul(0.95)
      }

      {result, state} = run(%State{}, group(handles(5), answers))
      network = state.networks[result.network_id]
      member_handles = network.member_ids |> Enum.map(&state.accounts[&1].handle) |> Enum.sort()
      assert member_handles == ["h1", "h2", "h3"]
    end

    test "without membership answers every account is a member" do
      {result, state} = run(%State{}, group(handles(5), %{"coordinated" => noul(0.9)}))
      assert length(state.networks[result.network_id].member_ids) == 5
    end

    test "repeat members resolve via the account index without new accounts (#146)" do
      {_, state} = run(%State{}, group(handles(4), %{"coordinated" => noul(0.9)}))
      count = map_size(state.accounts)

      {result, state2} = run(state, group(handles(4), %{"coordinated" => noul(0.9)}))
      assert map_size(state2.accounts) == count

      for h <- handles(4) do
        assert state2.account_by_handle[{"x", h}] in result.account_ids
      end
    end

    test "severity follows the configured bands (spec: Severity from probability)" do
      for {p, severity} <- [{0.95, :high}, {0.83, :medium}, {0.72, :low}] do
        {%{alerts: [%{alert: alert}]}, _} =
          run(%State{}, group(handles(2), %{"coordinated" => noul(p)}))

        assert alert.severity == severity, "#{p} should be #{severity}"
      end
    end

    test "evidence is written from the answers (spec: Relation evidence)" do
      answers = %{"coordinated" => noul(0.88), "relation" => choice("shared-link", 0.7)}
      {%{alerts: [%{alert: alert}]}, _state} = run(%State{}, group(handles(3), answers))

      assert [coordinated, relation] = alert.evidence
      assert coordinated.strength == :strong
      assert coordinated.explanation =~ "coordinated way (88%)"
      assert coordinated.explanation =~ ~r/^jev-1\.13: /
      assert coordinated.source == :answers
      assert relation.explanation =~ "shared-link"
      assert relation.strength == :moderate
      assert relation.kind == :shared_link
      assert length(relation.account_ids) == 3
    end

    test "evidence names the model that answered, not always Jev" do
      answers = %{"coordinated" => noul(0.9)}

      {%{alerts: [%{alert: sim}]}, _} =
        run(%State{}, group(handles(2), answers, %{"model" => "simulator"}))

      {%{alerts: [%{alert: unnamed}]}, _} =
        run(%State{}, Map.delete(group(handles(2), answers), "model"))

      assert hd(sim.evidence).explanation =~ ~r/^simulator: /
      assert hd(unnamed.evidence).explanation =~ ~r/^The model: /
    end

    test "names the network from its members' topics and feeds" do
      {_, state} = run(%State{}, account("h1", %{"answers" => %{"topic" => choice("crypto")}}))
      {result, state} = run(state, group(["h1", "h2"], %{"coordinated" => noul(0.9)}))
      assert state.networks[result.network_id].name == "Crypto cluster on X"
    end

    test "the catch-all topic \"other\" doesn't name the network" do
      {_, state} = run(%State{}, account("h1", %{"answers" => %{"topic" => choice("other")}}))
      {result, state} = run(state, group(["h1", "h2"], %{"coordinated" => noul(0.9)}))
      assert state.networks[result.network_id].name == "Unnamed cluster on X"
    end

    test "alerts from a finding record its id" do
      {%{alerts: [%{alert: alert}], finding_id: finding_id}, _} =
        run(%State{}, group(handles(2), %{"coordinated" => noul(0.9)}))

      assert alert.finding_id == finding_id
    end

    test "a group mostly inside a known network is a finding for that network" do
      {state, network_id, _alert} = network_of(4)

      {result, _state} =
        run(state, group(["h1", "h2", "h3", "new"], %{"coordinated" => noul(0.9)}))

      assert result.network_id == network_id
      assert [%{alert: %{trigger_id: "network_growth"}}] = result.alerts
    end
  end

  describe "network growth" do
    test "new members are added with a before/after count (spec: Two new members)" do
      {state, network_id, _} = network_of(12)
      handles = handles(12) ++ ["n1", "n2"]

      {result, state} =
        run(state, group(handles, %{"coordinated" => noul(0.9)}, %{"network_id" => network_id}))

      assert [%{action: :created, alert: alert}] = result.alerts
      assert alert.trigger_id == "network_growth"
      assert alert.comparison == %{label: "Members", before: "12", after: "14"}
      assert length(state.networks[network_id].member_ids) == 14
    end

    test "accounts an analyst removed are not re-added" do
      {state, network_id, _} = network_of(3)
      removed = account_id(state, "h3")

      state =
        update_in(state.networks[network_id], fn n ->
          %{n | member_ids: n.member_ids -- [removed], removed_account_ids: [removed]}
        end)

      {result, state} =
        run(
          state,
          group(handles(3), %{"coordinated" => noul(0.9)}, %{"network_id" => network_id})
        )

      assert result.alerts == []
      assert result.skipped == [%{account_id: removed, reason: :removed_by_analyst}]
      refute removed in state.networks[network_id].member_ids
    end

    test "re-assessed answers replace earlier ones (spec: Re-assessed answers replace earlier ones)" do
      {state, network_id, _} = network_of(3)

      grow = fn state, extra, p ->
        run(
          state,
          group(handles(3) ++ extra, %{"coordinated" => noul(p)}, %{"network_id" => network_id})
        )
      end

      {%{alerts: [%{alert: first}]}, state} = grow.(state, ["n1"], 0.88)
      {%{alerts: [%{action: :merged, alert: second}]}, _state} = grow.(state, ["n1", "n2"], 0.91)

      assert second.id == first.id
      assert Enum.any?(lines(second), &(&1 =~ "(91%)"))
      refute Enum.any?(lines(second), &(&1 =~ "(88%)"))
    end

    test "a stale finding on a dismissed network is ignored with the reason" do
      {state, network_id, _} = network_of(3)
      state = dismiss(state, network_id, later(10))

      {result, _state} =
        run(
          state,
          group(handles(3) ++ ["n1"], %{"coordinated" => noul(0.9)}, %{"network_id" => network_id})
        )

      assert %{alerts: [], reason: :predates_dismissal} = result
    end
  end

  describe "promotion shift" do
    test "a changed top domain raises an alert, no AI needed (spec: Domain changes)" do
      {state, network_id, _} =
        network_of(3, %{"coordinated" => noul(0.9)}, %{
          "heuristics" => %{"domains" => [%{"domain" => "deals-a.example", "share" => 0.62}]}
        })

      assert state.networks[network_id].main_domain == "deals-a.example"

      {result, state} =
        run(
          state,
          group(handles(3), nil, %{
            "network_id" => network_id,
            "heuristics" => %{"domains" => [%{"domain" => "deals-b.example", "share" => 0.55}]}
          })
        )

      assert [%{alert: alert}] = result.alerts
      assert alert.trigger_id == "promotion_shift"

      assert alert.comparison == %{
               label: "Main promoted domain",
               before: "deals-a.example",
               after: "deals-b.example (55%)"
             }

      assert state.networks[network_id].main_domain == "deals-b.example"
    end

    test "a top domain under half the links shifts nothing" do
      {state, network_id, _} = network_of(3)

      {result, _state} =
        run(
          state,
          group(handles(3), nil, %{
            "network_id" => network_id,
            "heuristics" => %{"domains" => [%{"domain" => "x.example", "share" => 0.4}]}
          })
        )

      assert result.alerts == []
    end
  end

  describe "trend findings" do
    defp with_trajectory(label) do
      {state, network_id, _} = network_of(3)
      {_, state} = run(state, trend(network_id, %{"trajectory" => choice(label)}))
      {state, network_id}
    end

    test "the trajectory is recorded (spec: Trajectory recorded)" do
      {state, network_id} = with_trajectory("stable")
      assert state.networks[network_id].assessment.trajectory == "stable"
    end

    test "a dormant network waking up is a reactivation (spec: Dormant network wakes up)" do
      {state, network_id} = with_trajectory("fading")

      {result, _state} =
        run(state, trend(network_id, %{"trajectory" => choice("forming", 0.66)}, later(5)))

      assert [%{alert: alert}] = result.alerts
      assert alert.trigger_id == "network_reactivation"
      assert alert.comparison == %{label: "Trajectory", before: "fading", after: "forming"}
    end

    test "an active network intensifying is coordination rising (spec: Active network intensifies)" do
      {state, network_id} = with_trajectory("stable")

      {result, _state} =
        run(
          state,
          trend(
            network_id,
            %{"increasing" => noul(0.82), "trajectory" => choice("stable")},
            later(5)
          )
        )

      assert [%{alert: %{trigger_id: "coordination_rising", severity: :medium}}] = result.alerts
    end

    test "a calm trend raises nothing" do
      {state, network_id} = with_trajectory("stable")
      {result, _} = run(state, trend(network_id, %{"increasing" => noul(0.2)}))
      assert %{alerts: [], reason: :below_threshold} = result
    end
  end

  describe "links with provenance" do
    test "a link records its origin (spec: Link records its origin)" do
      answers = %{"coordinated" => noul(0.9), "relation" => choice("timing-sync")}
      {result, state} = run(%State{}, group(["a", "b"], answers))

      assert [link] = state.links
      assert link.kind == :timing_sync
      assert link.strength == :strong

      assert link.provenance == [
               %{finding_id: result.finding_id, question: "relation", model: "jev-1.13", at: @t}
             ]

      assert [%{id: id}] = state.findings
      assert id == result.finding_id
    end

    test "relation none creates no link" do
      {_, state} =
        run(
          %State{},
          group(["a", "b"], %{"coordinated" => noul(0.9), "relation" => choice("none")})
        )

      assert state.links == []
    end

    test "the findings log and link provenance stay within their caps" do
      previous = Application.get_env(:dripstone, Rules)
      Application.put_env(:dripstone, Rules, provenance_per_link: 2, findings_log: 3)
      on_exit(fn -> restore(previous) end)

      answers = %{"coordinated" => noul(0.9), "relation" => choice("shared-link")}

      state =
        Enum.reduce(1..5, %State{}, fn _, state ->
          {_, state} = run(state, group(["a", "b"], answers))
          state
        end)

      assert [%{provenance: provenance}] = state.links
      assert length(provenance) == 2
      assert length(state.findings) == 3
    end
  end

  defp restore(nil), do: Application.delete_env(:dripstone, Rules)
  defp restore(value), do: Application.put_env(:dripstone, Rules, value)
end
