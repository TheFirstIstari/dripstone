defmodule Dripstone.Tracker do
  @moduledoc """
  The tracker context: the one interface the UI uses, and the one entry point
  detection reports findings through.

  Reads load persisted rows via `Dripstone.Tracker.Store`; writes apply against
  the persisted state and save it back in the same step.

  Changes return `{:ok, result}` or `{:error, reason}`, where `reason` is an atom
  (`:not_found`, `:retired`, `:not_open`, ...) or an `Ecto.Changeset` for invalid
  text input. They are broadcast on the `"tracker"` PubSub topic:

    * `{:alert_raised, alert}`: a new alert
    * `{:alert_updated, alert}`: an existing alert changed
    * `{:network_updated, network_id}`: a network changed
    * `{:account_updated, account_id}`: an account changed (from a finding)
  """

  alias Dripstone.Tracker.{Curation, Decisions, Graph, Intake, Queries, Report, Rules, Store}

  @default_by "Detection"

  @topic "tracker"

  ## Detection

  @doc """
  Reports a finding from detection: an account, group or trend finding carrying
  heuristics and the decision model's answers. See
  `openspec/docs/DETECTION_INTERFACE.md` for the fields, rules and results.

  Returns `{:ok, %{kind, finding_id, alerts: [%{action, alert}], network_id,
  account_ids, skipped, reason}}` or `{:error, errors}` (field => messages). A rejected
  finding changes nothing.
  """
  @spec report_finding(map()) :: {:ok, map()} | {:error, %{atom() => [String.t()]}}
  def report_finding(attrs) do
    with {:ok, state} <- Store.load(),
         {:ok, report} <- Report.cast(attrs, state),
         {:ok, result, new_state} <- Rules.run(state, report, now()) do
      :ok = Store.save(new_state)
      Enum.each(report_messages(result), &broadcast/1)
      {:ok, result}
    end
  end

  @doc false
  # Runs one *internal* finding straight through the intake. Detection never
  # calls this; it exists for tests that need a specific alert.
  def apply_finding(attrs) do
    with {:ok, state} <- Store.load(),
         {:ok, result, new_state} <- Intake.run(state, attrs, now()) do
      :ok = Store.save(new_state)
      Enum.each(messages(result), &broadcast/1)
      {:ok, result}
    end
  end

  ## Reads

  @doc "Maps a 0–100 risk score to `:low`, `:medium` or `:high`."
  defdelegate risk_level(score), to: Queries

  def overview, do: read(&Queries.overview(&1, DateTime.utc_now()))
  def list_alerts(params \\ %{}), do: read(&Queries.list_alerts(&1, params))
  def count_alerts(params \\ %{}), do: read(&Queries.count_alerts(&1, params))
  def get_alert(id), do: read(&Queries.get_alert(&1, id))
  def alert_detail(id, params \\ %{}), do: read(&Queries.alert_detail(&1, id, params))
  def alert_neighbors(id, params \\ %{}), do: read(&Queries.alert_neighbors(&1, id, params))
  def list_networks(params \\ %{}), do: read(&Queries.list_networks(&1, params))
  def list_network_options, do: read(&Queries.list_network_options/1)
  def get_network(id, view \\ :summary), do: read(&Queries.get_network(&1, id, view))

  def network_graph(id) do
    with {:ok, state} <- Store.load(),
         %Dripstone.Tracker.Network{} = network <- state.networks[id] do
      Graph.build(network, state.links)
    else
      _ -> nil
    end
  end

  def list_accounts(params \\ %{}), do: read(&Queries.list_accounts(&1, params))
  def get_account(id), do: read(&Queries.get_account(&1, id))
  def feed_health, do: read(&Queries.feed_health(&1, DateTime.utc_now()))

  def change_digest(since \\ nil),
    do: read(&Dripstone.Tracker.Digest.build(&1, DateTime.utc_now(), since))

  def list_tags(prefix \\ ""), do: read(&Queries.list_tags(&1, prefix))

  ## Decisions

  @doc "Changeset for the optional decision note."
  defdelegate decision_note_changeset(attrs \\ %{}), to: Decisions, as: :note_changeset

  def confirm_alert(id, attrs \\ %{}, by \\ @default_by),
    do: change(&Decisions.confirm(&1, id, attrs, now(), by))

  def dismiss_alert(id, attrs \\ %{}, by \\ @default_by),
    do: change(&Decisions.dismiss(&1, id, attrs, now(), by))

  def undo_decision(decision_id, by \\ @default_by),
    do: change(&Decisions.undo(&1, decision_id, now(), by))

  ## Curation

  defdelegate name_changeset(attrs \\ %{}), to: Curation
  defdelegate tag_changeset(attrs \\ %{}), to: Curation
  defdelegate note_changeset(attrs \\ %{}), to: Curation

  def rename_network(id, attrs, by \\ @default_by),
    do: change(&Curation.rename(&1, id, attrs, now(), by))

  def add_tag(id, attrs, by \\ @default_by),
    do: change(&Curation.add_tag(&1, id, attrs, now(), by))

  def remove_tag(id, tag, by \\ @default_by),
    do: change(&Curation.remove_tag(&1, id, tag, now(), by))

  def add_note(id, attrs, by \\ @default_by),
    do: change(&Curation.add_note(&1, id, attrs, now(), by))

  def add_members(id, account_ids, by \\ @default_by),
    do: change(&Curation.add_members(&1, id, account_ids, now(), by))

  def remove_members(id, account_ids, by \\ @default_by),
    do: change(&Curation.remove_members(&1, id, account_ids, now(), by))

  def move_members(from_id, to_id, account_ids, by \\ @default_by),
    do: change(&Curation.move_members(&1, from_id, to_id, account_ids, now(), by))

  def merge_networks(source_id, target_id, by \\ @default_by),
    do: change(&Curation.merge(&1, source_id, target_id, now(), by))

  def split_network(id, account_ids, attrs, by \\ @default_by),
    do: change(&Curation.split(&1, id, account_ids, attrs, now(), by))

  def relate_networks(a_id, b_id, note \\ nil, by \\ @default_by),
    do: change(&Curation.relate(&1, a_id, b_id, note, now(), by))

  def unrelate_networks(a_id, b_id, by \\ @default_by),
    do: change(&Curation.unrelate(&1, a_id, b_id, now(), by))

  ## Sample data

  @doc "Reseeds the sample rows relative to now (resets all changes)."
  def reset_sample_data! do
    :ok = Store.reset!()
    {:ok, _} = Store.load()
    :ok
  end

  ## PubSub

  @doc "Subscribes the calling process to tracker changes."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(Dripstone.PubSub, @topic)

  @doc false
  def broadcast(message), do: Phoenix.PubSub.broadcast(Dripstone.PubSub, @topic, message)

  defp read(fun) do
    {:ok, state} = Store.load()
    fun.(state)
  end

  # Writes load the persisted state, apply `fun`, save the result and broadcast
  # its messages. A rejected change saves nothing.
  defp change(fun) do
    with {:ok, state} <- Store.load(),
         {:ok, reply, %Dripstone.Tracker.State{} = new_state, messages} <- fun.(state) do
      :ok = Store.save(%{new_state | cache: %{}})
      Enum.each(messages, &broadcast/1)
      {:ok, reply}
    end
  end

  defp report_messages(result) do
    alerts =
      Enum.flat_map(result.alerts, &messages(Map.put(&1, :network_id, &1.alert.network_id)))

    networks = if result.network_id, do: [{:network_updated, result.network_id}], else: []
    accounts = Enum.map(result.account_ids, &{:account_updated, &1})
    Enum.uniq(alerts ++ networks ++ accounts)
  end

  defp messages(%{action: :ignored}), do: []

  defp messages(%{action: action, alert: alert, network_id: network_id}),
    do: [
      {:network_updated, network_id},
      {if(action == :created, do: :alert_raised, else: :alert_updated), alert}
    ]

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
