defmodule Lens.Repo.Migrations.RetainCollectionStorageProvenance do
  use Ecto.Migration

  def change do
    alter table(:earnings_storage_work) do
      add(:source_id, references(:earnings_sources, type: :binary_id, on_delete: :restrict))
      add(:http_check, :map)
    end

    create(index(:earnings_storage_work, [:source_id], where: "status != 'completed'"))
  end
end
