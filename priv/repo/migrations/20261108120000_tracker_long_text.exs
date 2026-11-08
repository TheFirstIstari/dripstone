defmodule Dripstone.Repo.Migrations.TrackerLongText do
  use Ecto.Migration

  def change do
    alter table(:tracker_notes) do
      modify :body, :text, null: false, from: :string
    end

    alter table(:tracker_history) do
      modify :summary, :text, null: false, from: :string
    end

    alter table(:tracker_decisions) do
      modify :note, :text, from: :string
    end
  end
end
