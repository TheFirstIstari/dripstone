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
         %Alert{decision_id: ^decision_id} = alert <- state.alerts[decision.alert_id] do
      alert = %{alert | status: decision.previous_alert_status, decision_id: nil, updated_at: now}
      network = %{state.networks[decision.network_id] | status: decision.previous_network_status}

      state =
        %{
          state
          | alerts: Map.put(state.alerts, alert.id, alert),
            networks: Map.put(state.networks, network.id, network),
            decisions: Map.delete(state.decisions, decision_id)
        }
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
        previous_network_status: network.status
      }

      alert = %{alert | status: alert_status(action), decision_id: id, updated_at: now}
      network = %{network | status: network_status(state, network, alert, action)}

      state =
        %{
          state
          | alerts: Map.put(state.alerts, alert.id, alert),
            networks: Map.put(state.networks, network.id, network),
            decisions: Map.put(state.decisions, id, decision)
        }
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

  defp alert_status(:confirm), do: :confirmed
  defp alert_status(:dismiss), do: :dismissed

  defp network_status(_state, _network, _alert, :confirm), do: :confirmed

  defp network_status(state, network, alert, :dismiss) do
    confirmed? =
      Enum.any?(state.alerts, fn {id, a} ->
        id != alert.id and a.network_id == network.id and a.status == :confirmed
      end)

    if confirmed?, do: network.status, else: :dismissed
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
