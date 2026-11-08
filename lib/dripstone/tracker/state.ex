defmodule Dripstone.Tracker.State do
  @moduledoc """
  Everything the tracker knows, as plain data. The store holds one of these;
  the intake and other operations are pure functions from one state to the next.

  `posts` is keyed by account id (newest first). `history` is newest first.
  `seq` feeds `next_id/2`. `findings` logs the latest reported findings (newest
  first, capped) so link provenance can be traced back to them.
  """

  alias Dripstone.Tracker.{Alert, Decision, HistoryEntry, Network, Note}

  defstruct accounts: %{},
            posts: %{},
            links: [],
            feed_health: [],
            networks: %{},
            alerts: %{},
            decisions: %{},
            notes: %{},
            history: [],
            findings: [],
            seq: 0,
            # Lookup indexes (maintained by put_account/put_alert/put_decision below):
            # account_by_handle maps {feed_id, handle} to account id so intake
            # never scans all accounts; open_by_trigger maps {network_id,
            # trigger_id} to the open alert id; confirmed_by_network counts
            # confirmed alerts per network for dismiss decisions; latest_dismissal
            # maps network id to its latest dismiss decision.
            account_by_handle: %{},
            open_by_trigger: %{},
            confirmed_by_network: %{},
            latest_dismissal: %{}

  @type t :: %__MODULE__{
          accounts: map(),
          posts: %{String.t() => list()},
          links: list(),
          feed_health: list(),
          networks: %{String.t() => Network.t()},
          alerts: %{String.t() => Alert.t()},
          decisions: %{String.t() => Decision.t()},
          notes: %{String.t() => Note.t()},
          history: [HistoryEntry.t()],
          findings: [map()],
          seq: non_neg_integer(),
          account_by_handle: %{{String.t(), String.t()} => String.t()},
          open_by_trigger: %{{String.t(), String.t()} => String.t()},
          confirmed_by_network: %{String.t() => non_neg_integer()},
          latest_dismissal: %{String.t() => Decision.t()}
        }

  @doc "Returns a fresh id like `\"alert-12\"` and the state with the counter advanced."
  @spec next_id(t(), String.t()) :: {String.t(), t()}
  def next_id(%__MODULE__{seq: seq} = state, prefix),
    do: {"#{prefix}-#{seq + 1}", %{state | seq: seq + 1}}

  @max_history 500

  @doc "Maximum number of history entries kept (newest first)."
  @spec max_history() :: pos_integer()
  def max_history, do: @max_history

  @doc "Records a history entry for a network, keeping only the newest entries."
  @spec add_history(t(), String.t(), :analyst | :system, String.t(), String.t(), DateTime.t()) ::
          t()
  def add_history(state, network_id, actor, by, summary, at) do
    {id, state} = next_id(state, "hist")

    entry = %HistoryEntry{
      id: id,
      network_id: network_id,
      actor: actor,
      by: by,
      at: at,
      summary: summary
    }

    %{state | history: Enum.take([entry | state.history], @max_history)}
  end

  @doc "Stores an account, keeping the {feed_id, handle} index current."
  @spec put_account(t(), term()) :: t()
  def put_account(state, account) do
    %{
      state
      | accounts: Map.put(state.accounts, account.id, account),
        account_by_handle:
          Map.put(state.account_by_handle, {account.feed_id, account.handle}, account.id)
    }
  end

  @doc "Stores an alert, keeping the open-by-trigger index current."
  @spec put_alert(t(), term()) :: t()
  def put_alert(state, alert) do
    key = {alert.network_id, alert.trigger_id}

    open_by_trigger =
      if alert.status == :open do
        Map.put(state.open_by_trigger, key, alert.id)
      else
        case Map.fetch(state.open_by_trigger, key) do
          {:ok, id} when id == alert.id -> Map.delete(state.open_by_trigger, key)
          _ -> state.open_by_trigger
        end
      end

    confirmed_by_network = adjust_confirmed(state, Map.get(state.alerts, alert.id), alert)

    %{
      state
      | alerts: Map.put(state.alerts, alert.id, alert),
        open_by_trigger: open_by_trigger,
        confirmed_by_network: confirmed_by_network
    }
  end

  @doc "Rebuilds every lookup index from the authoritative maps. Use when loading persisted state or hand-built test states."
  @spec reindex(t()) :: t()
  def reindex(state) do
    account_by_handle =
      Map.new(state.accounts, fn {id, account} -> {{account.feed_id, account.handle}, id} end)

    {open_by_trigger, confirmed_by_network} =
      Enum.reduce(state.alerts, {%{}, %{}}, fn {_id, alert}, {open, confirmed} ->
        open =
          if alert.status == :open,
            do: Map.put(open, {alert.network_id, alert.trigger_id}, alert.id),
            else: open

        confirmed =
          if alert.status == :confirmed,
            do: Map.update(confirmed, alert.network_id, 1, &(&1 + 1)),
            else: confirmed

        {open, confirmed}
      end)

    latest_dismissal =
      state.decisions
      |> Map.values()
      |> Enum.filter(&(&1.action == :dismiss))
      |> Enum.group_by(& &1.network_id)
      |> Map.new(fn {network_id, decisions} ->
        {network_id, Enum.max_by(decisions, & &1.at, DateTime)}
      end)

    %{
      state
      | account_by_handle: account_by_handle,
        open_by_trigger: open_by_trigger,
        confirmed_by_network: confirmed_by_network,
        latest_dismissal: latest_dismissal
    }
  end

  defp adjust_confirmed(state, nil, %{status: :confirmed, network_id: network_id}),
    do: Map.update(state.confirmed_by_network, network_id, 1, &(&1 + 1))

  defp adjust_confirmed(state, nil, _alert), do: state.confirmed_by_network

  defp adjust_confirmed(state, %{status: :confirmed}, %{status: :confirmed}),
    do: state.confirmed_by_network

  defp adjust_confirmed(state, %{status: :confirmed, network_id: network_id}, _alert) do
    case state.confirmed_by_network do
      %{^network_id => 1} -> Map.delete(state.confirmed_by_network, network_id)
      %{^network_id => n} -> Map.put(state.confirmed_by_network, network_id, n - 1)
      _ -> state.confirmed_by_network
    end
  end

  defp adjust_confirmed(state, _old, %{status: :confirmed, network_id: network_id}),
    do: Map.update(state.confirmed_by_network, network_id, 1, &(&1 + 1))

  defp adjust_confirmed(state, _old, _alert), do: state.confirmed_by_network

  @doc "Stores a decision, keeping the latest-dismissal index current."
  @spec put_decision(t(), Decision.t()) :: t()
  def put_decision(state, %{action: :dismiss} = decision) do
    network_id = decision.network_id

    latest =
      case Map.fetch(state.latest_dismissal, network_id) do
        {:ok, current} ->
          if DateTime.compare(decision.at, current.at) == :lt, do: current, else: decision

        :error ->
          decision
      end

    state = %{state | decisions: Map.put(state.decisions, decision.id, decision)}
    %{state | latest_dismissal: Map.put(state.latest_dismissal, decision.network_id, latest)}
  end

  def put_decision(state, decision),
    do: %{state | decisions: Map.put(state.decisions, decision.id, decision)}

  @doc "Deletes a decision, keeping the latest-dismissal index current."
  @spec delete_decision(t(), String.t()) :: t()
  def delete_decision(state, decision_id) do
    case state.decisions do
      %{^decision_id => decision} ->
        state = %{state | decisions: Map.delete(state.decisions, decision_id)}

        if decision.action == :dismiss and
             (state.latest_dismissal[decision.network_id] || %{}) |> Map.get(:id) == decision_id do
          latest =
            state.decisions
            |> Map.values()
            |> Enum.filter(&(&1.action == :dismiss and &1.network_id == decision.network_id))
            |> Enum.max_by(& &1.at, DateTime, fn -> nil end)

          case latest do
            nil ->
              %{state | latest_dismissal: Map.delete(state.latest_dismissal, decision.network_id)}

            _ ->
              %{
                state
                | latest_dismissal: Map.put(state.latest_dismissal, decision.network_id, latest)
              }
          end
        else
          state
        end

      _ ->
        state
    end
  end
end
