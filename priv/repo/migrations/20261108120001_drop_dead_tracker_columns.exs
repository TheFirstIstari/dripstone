defmodule Dripstone.Repo.Migrations.DropDeadTrackerColumns do
  use Ecto.Migration

  def change do
    alter table(:tracker_accounts) do
      remove :last_checked_at, :utc_datetime
    end

    alter table(:tracker_networks) do
      remove :last_checked_at, :utc_datetime
    end

    alter table(:tracker_posts) do
      remove :fetched_at, :utc_datetime
    end
  end
end
