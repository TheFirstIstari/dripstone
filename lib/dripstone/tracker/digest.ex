defmodule Dripstone.Tracker.Digest do
  @moduledoc """
  The periodic per-user change digest: new edges, flipped labels and re-alerts
  since a cutoff, read from the versioned history (`State.history`) plus the
  alert map.

  Importance follows the same rule as live notification toasts (`DripstoneWeb.Nav`):
  only high-severity changes make the digest; lower-severity ones stay silent
  updates. Severity is the Jev-importance proxy (sample data derives it from
  confidence; the intake records it per alert).
  """

  alias Dripstone.Tracker.{Alert, HistoryEntry, State}

  @type item :: %{
          kind: :new_edge | :flipped_label | :re_alert,
          at: DateTime.t(),
          network_id: String.t(),
          summary: String.t(),
          severity: Alert.severity()
        }

  @doc """
  Builds the digest for `state`: entries at or after `since`, newest first.
  `since` defaults to seven days before `now` (the weekly digest window).
  """
  @spec build(State.t(), DateTime.t(), DateTime.t() | nil) :: [item()]
  def build(state, now \\ DateTime.utc_now(), since \\ nil)

  def build(%State{} = state, now, nil), do: build(state, now, week_ago(now))

  def build(%State{} = state, now, since) when is_struct(since, DateTime) do
    alerts = important_alerts(state, since)
    from_history(state, since) ++ from_alerts(state, alerts, now)
  end

  @doc "The default cutoff: seven days before `now`."
  @spec week_ago(DateTime.t()) :: DateTime.t()
  def week_ago(now \\ DateTime.utc_now()), do: DateTime.add(now, -7 * 86_400, :second)

  # New edges and flipped labels surface as history entries. A change counts
  # when its network has a high-severity alert: still open for new edges
  # (ongoing important attention), any status for flipped labels (the flip
  # itself closes the alert, e.g. confirm/dismiss).
  defp from_history(state, since) do
    alerts = Map.values(state.alerts)

    open =
      alerts
      |> Enum.filter(&(&1.severity == :high and &1.status == :open))
      |> MapSet.new(& &1.network_id)

    any = alerts |> Enum.filter(&(&1.severity == :high)) |> MapSet.new(& &1.network_id)

    state.history
    |> Enum.filter(&recent?(&1, since))
    |> Enum.flat_map(&classify(&1, open, any))
    |> Enum.sort_by(&{&1.at, &1.summary}, &later_or_equal?/2)
  end

  defp classify(%HistoryEntry{} = entry, open, any) do
    cond do
      entry.network_id in open and new_edge?(entry) ->
        [item(:new_edge, entry)]

      entry.network_id in any and flipped_label?(entry) ->
        [item(:flipped_label, entry)]

      true ->
        []
    end
  end

  defp item(kind, entry) do
    %{
      kind: kind,
      at: entry.at,
      network_id: entry.network_id,
      summary: entry.summary,
      severity: :high
    }
  end

  # A detection-recorded membership gain ("Added N member(s)"), a new
  # network's first detection ("Detected with N members"), or fresh evidence
  # merged onto an open alert ("New evidence on …") is a new edge.
  # Analyst member moves/merges ("Moved …", "Merged …") are silent curation,
  # not new detection edges.
  defp new_edge?(%HistoryEntry{actor: :system, summary: summary}) do
    String.starts_with?(summary, ["Added ", "Detected with ", "New evidence on "])
  end

  defp new_edge?(_entry), do: false

  # Flipped labels: a confirm/dismiss decision on an alert (the network's
  # status flips), or a detection re-alert after dismissal.
  defp flipped_label?(%HistoryEntry{summary: summary}) do
    String.starts_with?(summary, ["Confirmed alert ", "Dismissed alert ", "Re-alerted after "])
  end

  # Re-alerts surface from the alerts themselves (marked at intake on dismissed
  # networks), so the digest links to the live alert.
  defp from_alerts(state, alerts, _now) do
    Enum.map(alerts, fn alert ->
      network = state.networks[alert.network_id]

      %{
        kind: :re_alert,
        at: alert.raised_at,
        network_id: alert.network_id,
        summary: "Re-alerted: #{alert.title} (#{(network && network.name) || alert.network_id})",
        severity: alert.severity
      }
    end)
  end

  defp important_alerts(state, since) do
    state.alerts
    |> Map.values()
    |> Enum.filter(
      &(&1.severity == :high and &1.status == :open and
          not is_nil(&1.previously_dismissed_alert_id))
    )
    |> Enum.filter(&(DateTime.compare(&1.raised_at, since) != :lt))
    |> Enum.sort_by(&{&1.raised_at, &1.id}, &later_or_equal?/2)
  end

  defp recent?(%HistoryEntry{at: at}, since), do: DateTime.compare(at, since) != :lt

  defp later_or_equal?({at_a, a}, {at_b, b}) do
    case DateTime.compare(at_a, at_b) do
      :gt -> true
      :lt -> false
      :eq -> a >= b
    end
  end
end
