defmodule Dripstone.Repo.Migrations.AddTrackerAccountExternalId do
  use Ecto.Migration

  # The platform's permanent account id (e.g. a Bluesky DID). Handles can change;
  # this doesn't, so discovery matches accounts on it first.
  def change do
    alter table(:tracker_accounts) do
      add :external_id, :string
    end

    create index(:tracker_accounts, [:feed_id, :external_id])
  end
end
