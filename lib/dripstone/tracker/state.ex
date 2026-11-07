defmodule Dripstone.Tracker.State do
  @moduledoc """
  Everything the tracker knows, as plain data. The store holds one of these;
  the intake and other operations are pure functions from one state to the next.
  `history` is newest first. `seq` feeds `next_id/2`.
  """

  alias Dripstone.Tracker.{Alert, Decision, HistoryEntry, Network, Note}

  defstruct accounts: %{},
            posts: [],
            links: [],
            feed_health: [],
            networks: %{},
            alerts: %{},
            decisions: %{},
            notes: %{},
            history: [],
            seq: 0

  @type t :: %__MODULE__{
          accounts: map(),
          posts: list(),
          links: list(),
          feed_health: list(),
          networks: %{String.t() => Network.t()},
          alerts: %{String.t() => Alert.t()},
          decisions: %{String.t() => Decision.t()},
          notes: %{String.t() => Note.t()},
          history: [HistoryEntry.t()],
          seq: non_neg_integer()
        }

  @doc "Returns a fresh id like `\"alert-12\"` and the state with the counter advanced."
  @spec next_id(t(), String.t()) :: {String.t(), t()}
  def next_id(%__MODULE__{seq: seq} = state, prefix),
    do: {"#{prefix}-#{seq + 1}", %{state | seq: seq + 1}}

  @doc "Records a history entry for a network."
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

    %{state | history: [entry | state.history]}
  end
end
