defmodule Dripstone.Repo.Migrations.CreateTrackerTables do
  use Ecto.Migration

  def change do
    create table(:tracker_accounts, primary_key: false) do
      add :id, :string, primary_key: true
      add :feed_id, :string, null: false
      add :handle, :string, null: false
      add :display_name, :string
      add :instance, :string
      add :risk_score, :integer, null: false, default: 0
      add :signals, {:array, :map}, null: false, default: []
      add :first_seen_at, :utc_datetime
      add :last_seen_at, :utc_datetime
      add :last_checked_at, :utc_datetime
      add :assessment, :map
      add :topic, :string
    end

    create unique_index(:tracker_accounts, [:feed_id, :handle])

    create table(:tracker_networks, primary_key: false) do
      add :id, :string, primary_key: true
      add :name, :string, null: false
      add :detected_name, :string
      add :status, :string, null: false, default: "suspected"
      add :confidence, :integer, null: false, default: 0
      add :main_domain, :string
      add :summary_text, :string
      add :summary_generated_at, :utc_datetime
      add :platforms, {:array, :string}, null: false, default: []
      add :tags, {:array, :string}, null: false, default: []
      add :related_ids, {:array, :string}, null: false, default: []
      add :evidence, {:array, :map}, null: false, default: []
      add :removed_account_ids, {:array, :string}, null: false, default: []
      add :retired_into_id, :string
      add :first_seen_at, :utc_datetime
      add :last_true_at, :utc_datetime
      add :last_checked_at, :utc_datetime
      add :inserted_at, :utc_datetime
      add :assessment, :map
    end

    create table(:tracker_meta, primary_key: false) do
      add :key, :string, primary_key: true
      add :value, :integer, null: false
    end

    create table(:tracker_memberships, primary_key: false) do
      add :network_id, :string, null: false, primary_key: true
      add :account_id, :string, null: false, primary_key: true
      add :joined_at, :utc_datetime
      add :position, :integer, null: false, default: 0
    end

    create index(:tracker_memberships, [:account_id])

    create table(:tracker_posts, primary_key: false) do
      add :id, :string, primary_key: true
      add :account_id, :string, null: false
      add :post_id, :string, null: false
      add :posted_at, :utc_datetime
      add :text, :text
      add :domain, :string
      add :fetched_at, :utc_datetime
    end

    create index(:tracker_posts, [:account_id])

    create table(:tracker_links) do
      add :account_a_id, :string, null: false
      add :account_b_id, :string, null: false
      add :kind, :string, null: false
      add :strength, :string, null: false
      add :provenance, {:array, :map}, null: false, default: []
    end

    create unique_index(:tracker_links, [:account_a_id, :account_b_id, :kind])

    create table(:tracker_findings, primary_key: false) do
      add :id, :string, primary_key: true
      add :kind, :string, null: false
      add :observed_at, :utc_datetime, null: false
      add :model, :string
      add :network_id, :string
      add :accounts, {:array, :map}, null: false, default: []
      add :answers, :map
      add :position, :integer, null: false, default: 0
    end

    create index(:tracker_findings, [:network_id])
    create index(:tracker_findings, [:observed_at])

    create table(:tracker_feeds, primary_key: false) do
      add :feed_id, :string, primary_key: true
      add :status, :string, null: false, default: "not_connected"
      add :last_item_at, :utc_datetime
      add :items_24h, :integer, null: false, default: 0
      add :window_started_at, :utc_datetime
      add :last_error, :string
      add :last_error_at, :utc_datetime
    end

    create table(:tracker_alerts, primary_key: false) do
      add :id, :string, primary_key: true
      add :trigger_id, :string, null: false
      add :network_id, :string, null: false
      add :severity, :string, null: false
      add :status, :string, null: false, default: "open"
      add :title, :string, null: false
      add :raised_at, :utc_datetime, null: false
      add :observed_at, :utc_datetime
      add :updated_at, :utc_datetime
      add :evidence, {:array, :map}, null: false, default: []
      add :ai_rationale, :map
      add :comparison, :map
      add :previously_dismissed_id, :string
      add :decision_id, :string
      add :answers, :map
      add :model, :string
      add :finding_id, :string
    end

    create index(:tracker_alerts, [:network_id])
    create index(:tracker_alerts, [:status])

    create table(:tracker_decisions, primary_key: false) do
      add :id, :string, primary_key: true
      add :alert_id, :string, null: false
      add :network_id, :string, null: false
      add :action, :string, null: false
      add :by, :string, null: false
      add :at, :utc_datetime, null: false
      add :note, :string
      add :previous_alert_status, :string
      add :previous_network_status, :string
      add :resulting_network_status, :string
    end

    create index(:tracker_decisions, [:alert_id])
    create index(:tracker_decisions, [:network_id])

    create table(:tracker_notes, primary_key: false) do
      add :id, :string, primary_key: true
      add :network_id, :string, null: false
      add :body, :string, null: false
      add :by, :string, null: false
      add :at, :utc_datetime, null: false
    end

    create index(:tracker_notes, [:network_id])

    create table(:tracker_history, primary_key: false) do
      add :id, :string, primary_key: true
      add :network_id, :string, null: false
      add :actor, :string, null: false
      add :by, :string, null: false
      add :at, :utc_datetime, null: false
      add :summary, :string, null: false
    end

    create index(:tracker_history, [:network_id])
  end
end
