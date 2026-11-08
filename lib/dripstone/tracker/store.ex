defmodule Dripstone.Tracker.Store do
  @moduledoc false
  # Ecto persistence behind the tracker. `load/0` rebuilds a `State` from the
  # rows (seeding the sample rows on first boot); `save/1` writes the whole
  # state back. The pure modules (Report, Rules, Intake, Decisions, Curation,
  # Queries) keep working on `State`; this module only translates between rows
  # and structs. Sample rows come from `SampleLoader` (generated relative to
  # now); the hand-built showcase corpus is only a test/dev alternative via
  # `load(showcase: true)`.
  # Key mappings (domain struct -> row):
  # * answers/assessments/evidence/signals keep their atom keys as plain maps
  #   (jsonb); datetimes inside become ISO-8601 strings on write and parse back
  #   on read, because Postgres has no atom or DateTime-in-jsonb type.
  # * temporal triple: network `first_activity_at`/`last_activity_at` ->
  #   `first_seen_at`/`last_true_at`; `inserted_at` is row-creation time, kept
  #   as-is. Account `first_seen_at`/`last_seen_at` map directly.

  import Ecto.Query

  alias Dripstone.Repo

  alias Dripstone.Tracker.{
    Account,
    Alert,
    Decision,
    Evidence,
    FeedHealth,
    HistoryEntry,
    Link,
    Network,
    Note,
    Post,
    Signal,
    State
  }

  alias Dripstone.Tracker.Store.Account, as: AccountRow
  alias Dripstone.Tracker.Store.Alert, as: AlertRow
  alias Dripstone.Tracker.Store.Decision, as: DecisionRow
  alias Dripstone.Tracker.Store.Feed, as: FeedRow
  alias Dripstone.Tracker.Store.Finding, as: FindingRow
  alias Dripstone.Tracker.Store.History, as: HistoryRow
  alias Dripstone.Tracker.Store.Link, as: LinkRow
  alias Dripstone.Tracker.Store.Membership, as: MembershipRow
  alias Dripstone.Tracker.Store.Meta, as: MetaRow
  alias Dripstone.Tracker.Store.Network, as: NetworkRow
  alias Dripstone.Tracker.Store.Note, as: NoteRow
  alias Dripstone.Tracker.Store.Post, as: PostRow

  @seed_key "seeded"
  @seq_key "seq"

  @doc "Loads the persisted state, seeding the sample rows on first boot."
  @spec load(keyword()) :: {:ok, State.t()} | {:error, term()}
  def load(opts \\ []) do
    case Process.get(__MODULE__) do
      %State{} = state ->
        {:ok, state}

      nil ->
        # Demo is memory-only (DemoStore); Live is the rows.
        if Dripstone.Tracker.dataset() == :demo,
          do: {:ok, Dripstone.Tracker.DemoStore.load()},
          else: load_persisted(opts)
    end
  end

  defp load_persisted(opts) when is_list(opts) do
    case Keyword.fetch(opts, :showcase) do
      {:ok, true} -> seed_from(fn -> Dripstone.Showcase.load("v1.json", opts) end)
      _ -> seed_from(fn -> seed(opts) end)
    end
  end

  defp seed_from(fun) do
    if seeded?() do
      {:ok, read_state()}
    else
      with {:ok, state} <- fun.() do
        {:ok, persist_all(state)}
      end
    end
  end

  # The hand-built corpus stays available for tests/dev. Otherwise
  # `config :dripstone, :load_sample_data` decides what an empty database starts
  # with: `true` (dev, test) seeds the generated sample rows, `:showcase` the
  # showcase corpus, and `false` (prod, #50) an empty state, so invented findings
  # are never written into the production database.
  defp seed([{:showcase_dir, _} | _] = opts), do: Dripstone.Showcase.load("v1.json", opts)

  defp seed(_opts) do
    case Application.get_env(:dripstone, :load_sample_data, true) do
      false -> {:ok, %State{}}
      :showcase -> Dripstone.Showcase.load("v1.json", [])
      _ -> {:ok, Dripstone.Tracker.SampleLoader.load()}
    end
  end

  @doc false
  # Test-only override for the state `load/0` returns, so read-path tests can run
  # against fixture states without touching rows. Unset with `override(nil)`.
  @spec override(State.t() | nil) :: :ok
  def override(nil) do
    Process.delete(__MODULE__)
    :ok
  end

  def override(%State{} = state) do
    Process.put(__MODULE__, state)
    :ok
  end

  @doc """
  Runs `fun` as the tracker's single writer.

  Every load-modify-save path (`Tracker.change/1`, `report_finding/1`,
  `apply_finding/1`, the simulator) runs inside this serializer, so
  concurrent writes queue instead of interleaving and losing one update.
  """
  # shortcut: BEAM-local serializer only; clustered nodes sharing the DB could
  # still race — upgrade to `pg_advisory_xact_lock` if we ever run those.
  @spec write((-> result)) :: result when result: var
  def write(fun) do
    if Dripstone.Tracker.dataset() == :demo,
      do: Dripstone.Tracker.DemoStore.run(fun),
      else: Dripstone.Tracker.Writer.run(fun)
  end

  @doc "Writes the whole tracker state back."
  @spec save(State.t()) :: :ok
  def save(%State{} = state) do
    if Dripstone.Tracker.dataset() == :demo,
      do: Dripstone.Tracker.DemoStore.save(state),
      else: save_rows(state)
  end

  defp save_rows(state) do
    # Same table order as persist_all/1 and reset!/0: every path deletes then
    # reinserts the tracker tables in one order, so concurrent writers never
    # deadlock waiting on each other's locks. Rows go in with one `insert_all`
    # per table (not one round-trip per row) to hold the transaction briefly.
    Repo.transaction(fn ->
      write_accounts(state)
      write_networks(state)
      write_alerts(state)
      write_decisions(state)
      write_notes(state)
      write_history(state)
      write_aux(state)
      write_findings(state)

      Repo.insert!(%MetaRow{key: @seq_key, value: state.seq},
        on_conflict: {:replace, [:value]},
        conflict_target: :key
      )

      Repo.insert!(%MetaRow{key: @seed_key, value: 1},
        on_conflict: {:replace, [:value]},
        conflict_target: :key
      )
    end)

    :ok
  end

  @doc "Deletes every tracker row (used only by tests)."
  @spec reset!() :: :ok
  def reset! do
    # Same table order as save/1 and persist_all/1 (accounts first, meta last),
    # so the reset path never takes table locks in a conflicting order.
    for schema <- [
          AccountRow,
          NetworkRow,
          MembershipRow,
          AlertRow,
          DecisionRow,
          NoteRow,
          HistoryRow,
          PostRow,
          LinkRow,
          FeedRow,
          FindingRow,
          MetaRow
        ] do
      Repo.delete_all(schema)
    end

    :ok
  end

  @doc "True when the seed rows are already stored."
  @spec seeded?() :: boolean()
  def seeded?, do: not is_nil(Repo.get(MetaRow, @seed_key))

  ## Boot

  defp persist_all(state) do
    Repo.transaction(fn ->
      write_accounts(state)
      write_networks(state)
      write_alerts(state)
      write_decisions(state)
      write_notes(state)
      write_history(state)
      write_aux(state)
      write_findings(state)
      Repo.insert!(%MetaRow{key: @seq_key, value: state.seq})
      Repo.insert!(%MetaRow{key: @seed_key, value: 1})
    end)

    read_state()
  end

  ## Read

  defp read_state do
    accounts = Map.new(Repo.all(AccountRow), &{&1.id, to_account(&1)})

    memberships =
      Repo.all(from m in MembershipRow, order_by: [asc: m.network_id, asc: m.position])

    joined = Enum.group_by(memberships, & &1.network_id)

    networks =
      Map.new(Repo.all(NetworkRow), fn row ->
        network = to_network(row, Map.get(joined, row.id, []))
        {network.id, network}
      end)

    %State{
      accounts: accounts,
      posts: posts_by_account(),
      links: Enum.map(Repo.all(LinkRow), &to_link/1),
      feed_health: Enum.map(Repo.all(FeedRow), &to_feed/1),
      networks: networks,
      alerts: Map.new(Repo.all(AlertRow), &{&1.id, to_alert(&1)}),
      findings: findings(),
      decisions: Map.new(Repo.all(DecisionRow), &{&1.id, to_decision(&1)}),
      notes: Map.new(Repo.all(NoteRow), &{&1.id, to_note(&1)}),
      history:
        Repo.all(from h in HistoryRow, order_by: [desc: h.at, desc: h.id])
        |> Enum.map(&to_history/1),
      cache: %{},
      seq: seq()
    }
    |> State.reindex()
  end

  defp seq do
    case Repo.get(MetaRow, @seq_key) do
      %MetaRow{value: seq} -> seq
      nil -> 0
    end
  end

  defp posts_by_account do
    PostRow
    |> order_by([p], asc: p.id)
    |> Repo.all()
    |> Enum.group_by(& &1.account_id)
    |> Map.new(fn {id, rows} -> {id, Enum.map(rows, &to_post/1) |> undated_last()} end)
  end

  # Dated posts newest first; posts without a timestamp at the end, by id.
  # shortcut: mirrors Rules.merge_posts ordering, and only runs once per load.
  defp undated_last(posts) do
    {dated, undated} = Enum.split_with(posts, & &1.posted_at)

    Enum.sort_by(dated, & &1.posted_at, {:desc, DateTime}) ++
      Enum.sort_by(undated, & &1.id)
  end

  defp findings do
    FindingRow
    |> order_by([f], asc: f.position)
    |> Repo.all()
    |> Enum.map(&to_finding/1)
  end

  ## Write

  defp write_accounts(state) do
    Repo.delete_all(AccountRow)

    rows =
      Enum.map(state.accounts, fn {_id, %Account{} = a} ->
        %{
          id: a.id,
          feed_id: a.feed_id,
          handle: a.handle,
          display_name: a.display_name,
          instance: a.instance,
          risk_score: a.risk_score,
          signals: Enum.map(a.signals, &signal_to_row/1),
          first_seen_at: ts(a.first_seen_at),
          last_seen_at: ts(a.last_seen_at),
          last_checked_at: nil,
          assessment: a.assessment && atomize_strings(a.assessment),
          topic: a.topic
        }
      end)

    if rows != [], do: Repo.insert_all(AccountRow, rows)
  end

  defp write_networks(state) do
    Repo.delete_all(MembershipRow)
    Repo.delete_all(NetworkRow)

    networks =
      Enum.map(state.networks, fn {_id, %Network{} = n} ->
        %{
          id: n.id,
          name: n.name,
          detected_name: n.detected_name,
          status: to_string(n.status),
          confidence: n.confidence,
          main_domain: n.main_domain,
          summary_text: n.summary && n.summary.text,
          summary_generated_at: ts(n.summary && n.summary.generated_at),
          platforms: n.platforms,
          tags: n.tags,
          related_ids: n.related_ids,
          evidence: Enum.map(n.evidence, &evidence_to_row/1),
          removed_account_ids: n.removed_account_ids,
          retired_into_id: n.retired_into,
          first_seen_at: ts(n.first_activity_at),
          last_true_at: ts(n.last_activity_at),
          last_checked_at: nil,
          inserted_at: ts(n.inserted_at),
          assessment: n.assessment && atomize_strings(n.assessment)
        }
      end)

    memberships =
      Enum.flat_map(state.networks, fn {_id, %Network{} = n} ->
        n.member_ids
        |> Enum.with_index()
        |> Enum.map(fn {account_id, position} ->
          %{
            network_id: n.id,
            account_id: account_id,
            joined_at: ts(Map.get(n.joined_at, account_id)),
            position: position
          }
        end)
      end)

    if networks != [], do: Repo.insert_all(NetworkRow, networks)
    if memberships != [], do: Repo.insert_all(MembershipRow, memberships)
  end

  defp write_alerts(state) do
    Repo.delete_all(AlertRow)

    rows =
      Enum.map(state.alerts, fn {_id, %Alert{} = a} ->
        %{
          id: a.id,
          trigger_id: a.trigger_id,
          network_id: a.network_id,
          severity: to_string(a.severity),
          status: to_string(a.status),
          title: a.title,
          raised_at: ts(a.raised_at),
          observed_at: ts(a.observed_at),
          updated_at: ts(a.updated_at),
          evidence: Enum.map(a.evidence, &evidence_to_row/1),
          ai_rationale: a.ai_rationale && atomize_strings(a.ai_rationale),
          comparison: a.comparison && atomize_strings(a.comparison),
          previously_dismissed_id: a.previously_dismissed_alert_id,
          decision_id: a.decision_id,
          answers: a.answers && stringify(a.answers),
          model: a.model,
          finding_id: a.finding_id
        }
      end)

    if rows != [], do: Repo.insert_all(AlertRow, rows)
  end

  defp write_decisions(state) do
    Repo.delete_all(DecisionRow)

    rows =
      Enum.map(state.decisions, fn {_id, %Decision{} = d} ->
        %{
          id: d.id,
          alert_id: d.alert_id,
          network_id: d.network_id,
          action: to_string(d.action),
          by: d.by,
          at: ts(d.at),
          note: d.note,
          previous_alert_status: d.previous_alert_status && to_string(d.previous_alert_status),
          previous_network_status:
            d.previous_network_status && to_string(d.previous_network_status),
          resulting_network_status:
            d.resulting_network_status && to_string(d.resulting_network_status)
        }
      end)

    if rows != [], do: Repo.insert_all(DecisionRow, rows)
  end

  defp write_notes(state) do
    Repo.delete_all(NoteRow)

    rows =
      Enum.map(state.notes, fn {_id, %Note{} = n} ->
        %{id: n.id, network_id: n.network_id, body: n.body, by: n.by, at: ts(n.at)}
      end)

    if rows != [], do: Repo.insert_all(NoteRow, rows)
  end

  defp write_history(state) do
    Repo.delete_all(HistoryRow)

    rows =
      Enum.map(state.history, fn %HistoryEntry{} = h ->
        %{
          id: h.id,
          network_id: h.network_id,
          actor: to_string(h.actor),
          by: h.by,
          at: ts(h.at),
          summary: h.summary
        }
      end)

    if rows != [], do: Repo.insert_all(HistoryRow, rows)
  end

  defp write_aux(state) do
    Repo.delete_all(PostRow)
    Repo.delete_all(LinkRow)
    Repo.delete_all(FeedRow)

    posts =
      Enum.flat_map(state.posts, fn {account_id, posts} ->
        Enum.map(posts, fn %Post{} = p ->
          %{
            id: p.id,
            account_id: account_id,
            post_id: p.post_id,
            posted_at: ts(p.posted_at),
            text: p.text,
            domain: p.domain
          }
        end)
      end)

    links =
      Enum.map(state.links, fn %Link{} = l ->
        {a, b} = l.account_ids

        %{
          account_a_id: a,
          account_b_id: b,
          kind: to_string(l.kind),
          strength: to_string(l.strength),
          provenance: Enum.map(l.provenance, &atomize_strings/1)
        }
      end)

    feeds =
      Enum.map(state.feed_health, fn %FeedHealth{} = f ->
        %{
          feed_id: f.feed_id,
          status: to_string(f.status),
          last_item_at: ts(f.last_item_at),
          items_24h: f.items_24h,
          window_started_at: ts(f.window_started_at),
          last_error: f.last_error,
          last_error_at: ts(f.last_error_at)
        }
      end)

    if posts != [], do: Repo.insert_all(PostRow, posts)
    if links != [], do: Repo.insert_all(LinkRow, links)
    if feeds != [], do: Repo.insert_all(FeedRow, feeds)
  end

  defp write_findings(state) do
    Repo.delete_all(FindingRow)

    rows =
      state.findings
      |> Enum.with_index()
      |> Enum.map(fn {entry, position} ->
        %{
          id: entry.id,
          kind: to_string(entry.kind),
          observed_at: ts(entry.observed_at),
          model: entry.model,
          network_id: entry.network_id,
          accounts: Enum.map(entry.accounts, &stringify/1),
          answers: entry.answers && stringify(entry.answers),
          position: position
        }
      end)

    if rows != [], do: Repo.insert_all(FindingRow, rows)
  end

  # Postgres `:utc_datetime` columns are second-precision; caller datetimes may
  # carry microseconds, which Ecto rejects on insert.
  defp ts(nil), do: nil
  defp ts(%DateTime{} = dt), do: DateTime.truncate(dt, :second)

  ## Rows to structs

  defp to_account(%AccountRow{} = row) do
    %Account{
      id: row.id,
      feed_id: row.feed_id,
      handle: row.handle,
      display_name: row.display_name,
      instance: row.instance,
      created_at: nil,
      first_seen_at: row.first_seen_at,
      last_seen_at: row.last_seen_at,
      risk_score: row.risk_score,
      signals: Enum.map(row.signals, &to_signal/1),
      assessment: row.assessment && to_assessment(row.assessment),
      topic: row.topic
    }
  end

  defp to_signal(map) when is_map(map) do
    %Signal{
      name: map["name"] || map[:name],
      explanation: map["explanation"] || map[:explanation],
      contribution: map["contribution"] || map[:contribution],
      value: map["value"] || map[:value]
    }
  end

  defp to_network(%NetworkRow{} = row, memberships) do
    member_ids = Enum.map(memberships, & &1.account_id)

    %Network{
      id: row.id,
      name: row.name,
      detected_name: row.detected_name,
      status: to_atom(row.status, :suspected),
      confidence: row.confidence,
      member_ids: member_ids,
      joined_at: Map.new(memberships, &{&1.account_id, &1.joined_at}),
      platforms: row.platforms,
      main_domain: row.main_domain,
      summary:
        row.summary_text && %{text: row.summary_text, generated_at: row.summary_generated_at},
      evidence: Enum.map(row.evidence, &to_evidence/1),
      first_activity_at: row.first_seen_at,
      last_activity_at: row.last_true_at,
      tags: row.tags,
      removed_account_ids: row.removed_account_ids,
      related_ids: row.related_ids,
      retired_into: row.retired_into_id,
      inserted_at: row.inserted_at,
      assessment: row.assessment && to_assessment(row.assessment)
    }
  end

  defp to_post(%PostRow{} = row) do
    %Post{
      id: row.id,
      account_id: row.account_id,
      post_id: row.post_id,
      posted_at: row.posted_at,
      text: row.text,
      domain: row.domain
    }
  end

  defp to_link(%LinkRow{} = row) do
    %Link{
      account_ids: {row.account_a_id, row.account_b_id},
      kind: to_atom(row.kind, :shared_link),
      strength: to_atom(row.strength, :weak),
      provenance: Enum.map(row.provenance, &to_provenance/1)
    }
  end

  # Provenance entries are `%{finding_id, question, model, at}`; only the
  # question comes back as an atom and `at` as a datetime.
  defp to_provenance(map) when is_map(map) do
    %{
      finding_id: map["finding_id"] || map[:finding_id],
      question: map["question"] || map[:question],
      model: map["model"] || map[:model],
      at: parse_at(map["at"] || map[:at])
    }
  end

  defp parse_at(%DateTime{} = at), do: at

  defp parse_at(at) when is_binary(at) do
    case DateTime.from_iso8601(at) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_at(_), do: nil

  defp to_feed(%FeedRow{} = row) do
    %FeedHealth{
      feed_id: row.feed_id,
      status: to_atom(row.status, :not_connected),
      last_item_at: row.last_item_at,
      items_24h: row.items_24h,
      window_started_at: row.window_started_at,
      last_error: row.last_error,
      last_error_at: row.last_error_at
    }
  end

  defp to_alert(%AlertRow{} = row) do
    %Alert{
      id: row.id,
      trigger_id: row.trigger_id,
      network_id: row.network_id,
      severity: to_atom(row.severity, :low),
      status: to_atom(row.status, :open),
      title: row.title,
      raised_at: row.raised_at,
      observed_at: row.observed_at,
      updated_at: row.updated_at,
      evidence: Enum.map(row.evidence, &to_evidence/1),
      ai_rationale: row.ai_rationale && deatomize(row.ai_rationale),
      comparison: row.comparison && deatomize(row.comparison),
      previously_dismissed_alert_id: row.previously_dismissed_id,
      decision_id: row.decision_id,
      answers: row.answers && deatomize_answers(row.answers),
      model: row.model,
      finding_id: row.finding_id
    }
  end

  defp to_evidence(map) when is_map(map) do
    %Evidence{
      explanation: map["explanation"] || map[:explanation],
      strength: (map["strength"] || map[:strength] || "weak") |> to_atom(:weak),
      kind: (map["kind"] || map[:kind] || "other") |> to_atom(:other),
      account_ids: map["account_ids"] || map[:account_ids] || [],
      source: (map["source"] || map[:source]) |> to_atom(nil)
    }
  end

  defp to_finding(%FindingRow{} = row) do
    %{
      id: row.id,
      kind: to_atom(row.kind, :other),
      observed_at: row.observed_at,
      model: row.model,
      network_id: row.network_id,
      accounts: Enum.map(row.accounts, &to_ref/1),
      answers: row.answers && deatomize_raw(row.answers)
    }
  end

  # Account refs are `%{feed_id:, handle:}` with string values; keep it so an
  # `"x"` feed never comes back as an atom.
  defp to_ref(map) when is_map(map) do
    %{feed_id: map["feed_id"] || map[:feed_id], handle: map["handle"] || map[:handle]}
  end

  defp to_decision(%DecisionRow{} = row) do
    %Decision{
      id: row.id,
      alert_id: row.alert_id,
      network_id: row.network_id,
      action: to_atom(row.action, :confirm),
      by: row.by,
      at: row.at,
      note: row.note,
      previous_alert_status: to_atom(row.previous_alert_status, nil),
      previous_network_status: to_atom(row.previous_network_status, nil),
      resulting_network_status: to_atom(row.resulting_network_status, nil)
    }
  end

  defp to_note(%NoteRow{} = row) do
    %Note{id: row.id, network_id: row.network_id, body: row.body, by: row.by, at: row.at}
  end

  defp to_history(%HistoryRow{} = row) do
    %HistoryEntry{
      id: row.id,
      network_id: row.network_id,
      actor: to_atom(row.actor, :system),
      by: row.by,
      at: row.at,
      summary: row.summary
    }
  end

  ## Structs to rows

  defp signal_to_row(%Signal{} = s) do
    %{
      "name" => s.name,
      "explanation" => s.explanation,
      "contribution" => s.contribution,
      "value" => s.value
    }
  end

  defp evidence_to_row(%Evidence{} = e) do
    %{
      "explanation" => e.explanation,
      "strength" => to_string(e.strength),
      "kind" => to_string(e.kind),
      "account_ids" => e.account_ids,
      "source" => e.source && to_string(e.source)
    }
  end

  # Answers are keyed by question name (strings) but their values hold atom keys
  # (`%{type: :noul, value: p}`, choice, score, other); stringify keys one level
  # down and keep the `type` atom readable for the UI's pattern matches.
  defp stringify(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), answer_to_row(v)} end)
  end

  defp answer_to_row(%{type: type} = answer) do
    Map.new(answer, fn
      {:type, _} -> {"type", to_string(type)}
      {k, %DateTime{} = v} -> {to_string(k), DateTime.to_iso8601(v)}
      {k, v} when is_atom(k) or is_binary(k) -> {to_string(k), row_value(v)}
    end)
  end

  defp answer_to_row(v), do: row_value(v)

  defp row_value(%DateTime{} = v), do: DateTime.to_iso8601(v)
  defp row_value(%{} = v), do: stringify(v)
  defp row_value(v) when is_list(v), do: Enum.map(v, &row_value/1)
  defp row_value(v) when is_atom(v) and not is_nil(v), do: to_string(v)
  defp row_value(v), do: v

  defp atomize_strings(%{} = map) do
    Map.new(map, fn
      {k, %DateTime{} = v} -> {to_string(k), DateTime.to_iso8601(v)}
      {k, v} when is_atom(k) or is_binary(k) -> {to_string(k), atomize_value(v)}
    end)
  end

  defp atomize_value(%DateTime{} = v), do: DateTime.to_iso8601(v)
  defp atomize_value(v) when is_atom(v) and not is_nil(v), do: to_string(v)

  defp atomize_value(%{} = v) do
    if Enum.all?(Map.keys(v), &(is_binary(&1) or is_atom(&1))), do: atomize_strings(v), else: v
  end

  defp atomize_value(v) when is_list(v), do: Enum.map(v, &atomize_value/1)
  defp atomize_value(v), do: v

  defp deatomize(%{} = map) do
    Map.new(map, fn {k, v} -> {maybe_atom(k), deatomize_value(v)} end)
  end

  # Assessments are fixed-shape maps (`%{answers, model, observed_at}` on
  # accounts; coordination/relation/trajectory keys on networks). Values pass
  # through except answers (rebuilt above) and datetimes, which parse back.
  defp to_assessment(%{} = map) do
    Map.new(map, fn
      {"answers", v} when is_map(v) -> {:answers, deatomize_answers(v)}
      {"answers", v} -> {:answers, v}
      {"observed_at", v} -> {:observed_at, parse_at(v)}
      {"group_observed_at", v} -> {:group_observed_at, parse_at(v)}
      {"trend_observed_at", v} -> {:trend_observed_at, parse_at(v)}
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
      {k, v} -> {k, v}
    end)
  rescue
    ArgumentError -> Map.new(map, fn {k, v} -> {k, v} end)
  end

  defp deatomize_value(v) when is_binary(v) do
    case DateTime.from_iso8601(v) do
      {:ok, at, _} -> at
      _ -> maybe_atom(v)
    end
  end

  defp deatomize_value(%{} = v), do: deatomize(v)
  defp deatomize_value(v) when is_list(v), do: Enum.map(v, &deatomize_value/1)
  defp deatomize_value(v), do: v

  # Answers keep string question keys; each answer's fields come back as atoms
  # (`type` included) so the UI's pattern matches and `Answers.display/1` keep
  # working. Datetimes stay ISO strings here: findings carry raw answers and
  # `Answers.parse/1` accepts strings.
  defp deatomize_answers(%{} = map) do
    Map.new(map, fn {k, v} -> {k, deatomize_answer(v)} end)
  end

  defp deatomize_answer(%{} = answer) do
    case answer["type"] || answer[:type] do
      "noul" ->
        %{type: :noul, value: num(answer["value"] || answer[:value])}

      "choice" ->
        %{
          type: :choice,
          label: answer["label"] || answer[:label],
          confidence: num(answer["confidence"] || answer[:confidence]),
          probabilities: raw(answer["probabilities"] || answer[:probabilities])
        }

      "score" ->
        %{
          type: :score,
          value: num(answer["value"] || answer[:value]),
          score: num(answer["score"] || answer[:score]),
          levels: num(answer["levels"] || answer[:levels]),
          legend: raw(answer["legend"] || answer[:legend]),
          confidence: num(answer["confidence"] || answer[:confidence])
        }

      _ ->
        %{type: :other, raw: raw(answer["raw"] || answer[:raw])}
    end
  end

  defp deatomize_answer(v), do: deatomize_raw(v)

  defp num(v) when is_number(v), do: v / 1
  defp num(v), do: v

  defp raw(%{} = map), do: Map.new(map, fn {k, v} -> {k, raw(v)} end)
  defp raw(v) when is_list(v), do: Enum.map(v, &raw/1)
  defp raw(v), do: v

  defp deatomize_raw(%{} = map), do: Map.new(map, fn {k, v} -> {k, deatomize_raw(v)} end)
  defp deatomize_raw(v) when is_list(v), do: Enum.map(v, &deatomize_raw/1)
  defp deatomize_raw(v), do: v

  defp maybe_atom(key) when is_atom(key), do: key

  defp maybe_atom(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> key
  end

  defp to_atom(value, _default) when is_atom(value), do: value

  defp to_atom(value, default) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> default
  end

  defp to_atom(_, default), do: default
end
