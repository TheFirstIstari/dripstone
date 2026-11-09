defmodule Dripstone.Tracker.Decisions do
  @moduledoc """
  Analyst decisions on alerts: confirm, dismiss and undo. Pure functions over
  `Dripstone.Tracker.State`.

  Each change returns `{:ok, reply, state, messages}`, where `messages` are the
  PubSub broadcasts the store sends after applying it, or `{:error, reason}`.
  A note longer than 500 characters returns `{:error, %Ecto.Changeset{}}`.
  """

  import Ecto.Changeset

  alias Dripstone.Tracker.{Alert, Decision, State}

  @reviewer "Detection"
  @max_note 500

  @doc "Changeset for the optional decision note (max #{@max_note} characters)."
  @spec note_changeset(map()) :: Ecto.Changeset.t()
  def note_changeset(attrs \\ %{}) do
    {%{}, %{note: :string}}
    |> cast(attrs, [:note])
    |> validate_length(:note, max: @max_note)
  end

  @doc "Confirms an open alert: the alert and its network become Confirmed."
  def confirm(state, alert_id, attrs, now, by \\ @reviewer),
    do: decide(state, alert_id, attrs, :confirm, now, by)

  @doc """
  Dismisses an open alert as a false positive. The network becomes Dismissed unless
  it has a Confirmed alert. Future findings can still re-alert it.
  """
  def dismiss(state, alert_id, attrs, now, by \\ @reviewer),
    do: decide(state, alert_id, attrs, :dismiss, now, by)

  @doc "Undoes a decision, restoring the alert's and network's previous statuses."
  def undo(%State{} = state, decision_id, now, by \\ @reviewer) do
    with {:ok, decision} <- fetch(state.decisions, decision_id),
         %Alert{decision_id: ^decision_id} = alert <- state.alerts[decision.alert_id],
         :ok <- network_unchanged(state, decision) do
      alert = %{alert | status: decision.previous_alert_status, decision_id: nil, updated_at: now}
      network = %{state.networks[decision.network_id] | status: decision.previous_network_status}

      state =
        state
        |> State.put_alert(alert)
        |> State.delete_decision(decision_id)
        |> Map.update!(:networks, &Map.put(&1, network.id, network))
        |> State.add_history(
          network.id,
          :analyst,
          by,
          "Undid #{verb(decision.action)} of “#{alert.title}”",
          now
        )

      {:ok, %{alert: alert, network: network}, state,
       [{:alert_updated, alert}, {:network_updated, network.id}]}
    else
      {:error, reason} -> {:error, reason}
      _superseded -> {:error, :superseded}
    end
  end

  defp decide(%State{} = state, alert_id, attrs, action, now, by) do
    with {:ok, alert} <- fetch(state.alerts, alert_id),
         :ok <- if(alert.status == :open, do: :ok, else: {:error, :not_open}),
         {:ok, params} <- apply_action(note_changeset(attrs), :insert) do
      network = state.networks[alert.network_id]
      {id, state} = State.next_id(state, "dec")

      decision = %Decision{
        id: id,
        alert_id: alert.id,
        network_id: network.id,
        action: action,
        by: by,
        at: now,
        note: blank_to_nil(params[:note]),
        previous_alert_status: alert.status,
        previous_network_status: network.status,
        resulting_network_status: network_status(state, network, alert, action)
      }

      alert = %{alert | status: alert_status(action), decision_id: id, updated_at: now}
      network = %{network | status: decision.resulting_network_status}

      state =
        state
        |> State.put_alert(alert)
        |> State.put_decision(decision)
        |> Map.update!(:networks, &Map.put(&1, network.id, network))
        |> State.add_history(
          network.id,
          :analyst,
          by,
          "#{String.capitalize(past(action))} alert “#{alert.title}”",
          now
        )

      {:ok, %{alert: alert, decision: decision, network: network}, state,
       [{:alert_updated, alert}, {:network_updated, network.id}]}
    end
  end

  # The network may have changed since the decision (a newer decision on another
  # alert of the same network). Undoing then would clobber that newer outcome.
  # A status comparison alone is not enough: two confirms in a row leave the
  # network Confirmed, yet undoing the first would still wipe the second's
  # decision. Any newer decision on the same network therefore blocks the undo.
  defp network_unchanged(state, decision) do
    current = state.networks[decision.network_id] && state.networks[decision.network_id].status

    if superseded_by_newer?(state, decision) or current != decision.resulting_network_status,
      do: {:error, :superseded},
      else: :ok
  end

  defp superseded_by_newer?(state, decision) do
    Enum.any?(state.decisions, fn {id, other} ->
      id != decision.id and other.network_id == decision.network_id and newer?(other, decision)
    end)
  end

  # `at` is second-truncated so ties fall back to the id sequence from next_id/2.
  defp newer?(%Decision{at: this_at, id: this_id}, %Decision{at: other_at, id: other_id}) do
    case DateTime.compare(this_at, other_at) do
      :gt -> true
      :lt -> false
      :eq -> seq(this_id) > seq(other_id)
    end
  end

  defp seq("dec-" <> rest) do
    case Integer.parse(rest) do
      {n, ""} -> n
      _ -> 0
    end
  end

  defp seq(_), do: 0

  defp alert_status(:confirm), do: :confirmed
  defp alert_status(:dismiss), do: :dismissed

  defp network_status(_state, _network, _alert, :confirm), do: :confirmed

  defp network_status(state, network, _alert, :dismiss) do
    # `decide` only runs on :open alerts, so any confirmed alert in the count is
    # a different alert on the same network.
    if (state.confirmed_by_network[network.id] || 0) > 0, do: network.status, else: :dismissed
  end

  defp past(:confirm), do: "confirmed"
  defp past(:dismiss), do: "dismissed"
  defp verb(:confirm), do: "confirmation"
  defp verb(:dismiss), do: "dismissal"

  defp fetch(map, id) do
    case Map.fetch(map, id) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, :not_found}
    end
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(text) do
    case String.trim(text) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
