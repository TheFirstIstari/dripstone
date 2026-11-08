defmodule Dripstone.Tracker.ReportFindingsTest do
  # Tracker.report_findings/1 and account matching by external id
  # (add-bluesky-live-pipeline tasks 5.1 and 5.2). Uses the Live rows: not async.
  use Dripstone.DataCase, async: false

  alias Dripstone.Tracker
  alias Dripstone.Tracker.{Report, Rules, State, Store}

  defp now, do: DateTime.to_iso8601(DateTime.utc_now())
  defp noul(p), do: %{"type" => "noul", "noul" => p}

  defp account(handle, did),
    do: %{
      "kind" => "account",
      "observed_at" => now(),
      "account" => %{"feed_id" => "bluesky", "handle" => handle, "external_id" => did},
      "heuristics" => %{"score" => 60}
    }

  defp group(refs),
    do: %{
      "kind" => "group",
      "observed_at" => now(),
      "accounts" => refs,
      "answers" => %{"coordinated" => noul(0.9)}
    }

  defp accounts_on(feed),
    do: elem(Store.load(), 1).accounts |> Map.values() |> Enum.filter(&(&1.feed_id == feed))

  test "a candidate group's findings land together, in order, in one batch" do
    :ok = Tracker.subscribe()

    refs = [
      %{"feed_id" => "bluesky", "handle" => "a.bsky.social", "external_id" => "did:plc:a"},
      %{"feed_id" => "bluesky", "handle" => "b.bsky.social", "external_id" => "did:plc:b"}
    ]

    assert {:ok, [acc_a, acc_b, grp]} =
             Tracker.report_findings([
               account("a.bsky.social", "did:plc:a"),
               account("b.bsky.social", "did:plc:b"),
               group(refs)
             ])

    assert acc_a.kind == :account and acc_b.kind == :account
    assert [%{alert: %{trigger_id: "new_network"}}] = grp.alerts

    # The group reused the accounts the batch created earlier.
    assert Enum.sort(grp.account_ids) == Enum.sort(acc_a.account_ids ++ acc_b.account_ids)
    assert_receive {:alert_raised, %{trigger_id: "new_network"}}

    ours = accounts_on("bluesky") |> Enum.filter(&(&1.handle in ["a.bsky.social", "b.bsky.social"]))
    assert ours |> Enum.map(& &1.external_id) |> Enum.sort() == ["did:plc:a", "did:plc:b"]
  end

  test "one rejected finding rejects the whole batch and changes nothing" do
    {:ok, before} = Store.load()

    assert {:error, {1, %{kind: _}}} =
             Tracker.report_findings([
               account("c.bsky.social", "did:plc:c"),
               %{"kind" => "nope", "observed_at" => now()}
             ])

    {:ok, after_} = Store.load()
    assert map_size(after_.accounts) == map_size(before.accounts)
  end

  test "an account is matched by its external id across a handle change" do
    run = fn state, attrs ->
      {:ok, report} = Report.cast(attrs, state)
      {:ok, result, state} = Rules.run(state, report, DateTime.utc_now())
      {result, state}
    end

    {%{account_ids: [id]}, state} = run.(%State{}, account("old.bsky.social", "did:plc:z"))
    {%{account_ids: [same]}, state} = run.(state, account("new.bsky.social", "did:plc:z"))

    assert same == id
    assert state.accounts[id].handle == "new.bsky.social"
    assert state.account_by_handle[{"bluesky", "new.bsky.social"}] == id
    refute Map.has_key?(state.account_by_handle, {"bluesky", "old.bsky.social"})
  end
end
