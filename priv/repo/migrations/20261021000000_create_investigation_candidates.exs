defmodule Lens.Repo.Migrations.CreateInvestigationCandidates do
  use Ecto.Migration

  def change do
    create table(:investigation_candidates, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:title, :text, null: false)
      add(:body, :text, null: false)
      add(:details_url, :text)
      add(:published_at, :utc_datetime_usec, null: false)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(index(:investigation_candidates, [:published_at, :id]))
  end
end
