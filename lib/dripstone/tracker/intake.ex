defmodule Dripstone.Tracker.Intake do
  @moduledoc """
  The findings intake: turns a finding reported by detection into network changes
  and an alert. Pure: `run/3` takes a state and returns a new one.

  For a valid finding, in order:

    1. If the network is dismissed and the finding was observed at or before the
       dismissal, it is ignored (`action: :ignored, reason: :predates_dismissal`).
    2. The network is created, or updated from `network_updates`. Accounts an analyst
       removed are not re-added, and an analyst-set name is not overwritten; both are
       reported in `skipped`.
    3. If the network has an open alert for the same trigger, the finding is merged
       into it (evidence added, severity raised if higher). Otherwise a new alert is
       created; on a dismissed network it is marked as re-alerting and the network
       returns to Suspected.
    4. Every change is recorded in the network's history, marked `:system`.
  """

  alias Dripstone.Tracker.{Alert, Decision, Finding, Network, State}

  @detection "Detection"
  @severity_rank %{low: 1, medium: 2, high: 3}

  @type result :: %{
          action: :created | :merged | :ignored,
          alert: Alert.t() | nil,
          network_id: String.t(),
          skipped: [map()],
          reason: atom() | nil
        }

  @doc "Validates and applies a finding. A rejected finding changes nothing."
  @spec run(State.t(), map(), DateTime.t()) ::
          {:ok, result(), State.t()} | {:error, %{atom() => [String.t()]}}
  def run(%State{} = state, attrs, %DateTime{} = now) do
    with {:ok, finding} <- Finding.cast(attrs, state.networks, state.accounts) do
      apply_finding(state, finding, DateTime.truncate(now, :second))
    end
  end

  defp apply_finding(state, finding, now) do
    network = finding.network_id && Map.fetch!(state.networks, finding.network_id)
    dismissal = dismissal(state, network)

    if dismissal && not DateTime.after?(finding.observed_at, dismissal.at) do
      {:ok, result(:ignored, nil, network.id, [], :predates_dismissal), state}
    else
      {state, network, skipped} = upsert_network(state, network, finding, now)
      {state, alert, action} = upsert_alert(state, network, finding, dismissal, now)
      state = if dismissal, do: reopen(state, network, alert, now), else: state
      {:ok, result(action, alert, network.id, skipped, nil), state}
    end
  end

  defp result(action, alert, network_id, skipped, reason),
    do: %{action: action, alert: alert, network_id: network_id, skipped: skipped, reason: reason}

  # The latest dismissal of a currently dismissed network, or nil.
  defp dismissal(_state, nil), do: nil
  defp dismissal(_state, %Network{status: status}) when status != :dismissed, do: nil

  defp dismissal(state, %Network{id: id}) do
    state.decisions
    |> Map.values()
    |> Enum.filter(&match?(%Decision{network_id: ^id, action: :dismiss}, &1))
    |> Enum.max_by(& &1.at, DateTime, fn -> nil end)
  end

  ## Networks

  defp upsert_network(state, nil, %Finding{new_network: new} = finding, now) do
    at = finding.observed_at

    network = %Network{
      id: new.id,
      name: new.name,
      confidence: new.confidence,
      member_ids: new.member_ids,
      joined_at: Map.new(new.member_ids, &{&1, at}),
      platforms: new.platforms,
      main_domain: new.main_domain,
      summary: new.summary,
      evidence: if(new.evidence == [], do: finding.evidence, else: new.evidence),
      first_activity_at: at,
      last_activity_at: at,
      inserted_at: now
    }

    summary =
      "Detected with #{length(network.member_ids)} members (#{network.confidence}% confidence)"

    state =
      %{state | networks: Map.put(state.networks, network.id, network)}
      |> State.add_history(network.id, :system, @detection, summary, now)

    {state, network, []}
  end

  defp upsert_network(state, network, finding, now) do
    updates = finding.network_updates || %{}
    {network, changes, skipped} = apply_updates(network, updates, finding.observed_at)

    network = %{
      network
      | last_activity_at: latest(network.last_activity_at, finding.observed_at)
    }

    state = %{state | networks: Map.put(state.networks, network.id, network)}

    state =
      Enum.reduce(
        changes,
        state,
        &State.add_history(&2, network.id, :system, @detection, &1, now)
      )

    {state, network, skipped}
  end

  defp apply_updates(network, updates, observed_at) do
    {network, [], []}
    |> add_members(Map.get(updates, :add_member_ids, []), observed_at)
    |> rename(Map.get(updates, :name))
    |> set(:confidence, Map.get(updates, :confidence), &"Confidence #{&1}% → #{&2}%")
    |> set(:main_domain, Map.get(updates, :main_domain), &"Main domain #{&1 || "none"} → #{&2}")
    |> set(:summary, Map.get(updates, :summary), fn _old, _new -> "Summary updated" end)
    |> then(fn {network, changes, skipped} ->
      {network, Enum.reverse(changes), Enum.reverse(skipped)}
    end)
  end

  defp add_members({network, changes, skipped}, ids, at) do
    removed = MapSet.new(network.removed_account_ids)
    current = MapSet.new(network.member_ids)
    new_ids = Enum.reject(ids, &(&1 in current or &1 in removed))

    skipped =
      for id <- ids, id in removed, reduce: skipped do
        acc -> [%{account_id: id, reason: :removed_by_analyst} | acc]
      end

    case new_ids do
      [] ->
        {network, changes, skipped}

      _ ->
        network = %{
          network
          | member_ids: network.member_ids ++ new_ids,
            joined_at: Map.merge(network.joined_at, Map.new(new_ids, &{&1, at}))
        }

        {network, ["Added #{members_text(length(new_ids))}" | changes], skipped}
    end
  end

  defp members_text(1), do: "1 member"
  defp members_text(n), do: "#{n} members"

  defp rename(acc, nil), do: acc
  defp rename({%Network{name: name} = n, changes, skipped}, name), do: {n, changes, skipped}

  defp rename({%Network{detected_name: nil} = network, changes, skipped}, name),
    do: {%{network | name: name}, ["Renamed #{network.name} → #{name}" | changes], skipped}

  defp rename({network, changes, skipped}, _name),
    do: {network, changes, [%{field: :name, reason: :set_by_analyst} | skipped]}

  defp set(acc, _field, nil, _describe), do: acc

  defp set({network, changes, skipped}, field, value, describe) do
    case Map.fetch!(network, field) do
      ^value ->
        {network, changes, skipped}

      old ->
        {Map.put(network, field, value), [describe.(old, value) | changes], skipped}
    end
  end

  ## Alerts

  defp upsert_alert(state, network, finding, dismissal, now) do
    case open_alert(state, network.id, finding.trigger_id) do
      %Alert{} = alert ->
        merged = %{
          alert
          | title: finding.title,
            severity: max_severity(alert.severity, finding.severity),
            evidence: Enum.uniq(alert.evidence ++ finding.evidence),
            observed_at: latest(alert.observed_at, finding.observed_at),
            updated_at: now,
            ai_rationale: finding.ai_rationale || alert.ai_rationale,
            comparison: finding.comparison || alert.comparison
        }

        {put_alert(state, merged), merged, :merged}

      nil ->
        {id, state} = State.next_id(state, "alert")

        alert = %Alert{
          id: id,
          trigger_id: finding.trigger_id,
          network_id: network.id,
          severity: finding.severity,
          title: finding.title,
          raised_at: now,
          observed_at: finding.observed_at,
          updated_at: now,
          evidence: finding.evidence,
          ai_rationale: finding.ai_rationale,
          comparison: finding.comparison,
          previously_dismissed_alert_id: dismissal && dismissal.alert_id
        }

        {put_alert(state, alert), alert, :created}
    end
  end

  defp open_alert(state, network_id, trigger_id) do
    state.alerts
    |> Map.values()
    |> Enum.find(
      &match?(%Alert{network_id: ^network_id, trigger_id: ^trigger_id, status: :open}, &1)
    )
  end

  defp put_alert(state, alert), do: %{state | alerts: Map.put(state.alerts, alert.id, alert)}

  defp reopen(state, network, _alert, now) do
    network = %{network | status: :suspected}

    %{state | networks: Map.put(state.networks, network.id, network)}
    |> State.add_history(
      network.id,
      :system,
      @detection,
      "Re-alerted after dismissal: new evidence observed",
      now
    )
  end

  defp max_severity(a, b), do: if(@severity_rank[b] > @severity_rank[a], do: b, else: a)

  defp latest(nil, at), do: at
  defp latest(a, b), do: if(DateTime.after?(b, a), do: b, else: a)
end
