defmodule Lens.Repo.Migrations.CreateEarningsPDFPublications do
  use Ecto.Migration

  def change do
    create table(:earnings_pdf_publications, primary_key: false) do
      add(
        :material_id,
        references(:feed_material_extractions,
          column: :material_id,
          type: :binary_id,
          on_delete: :restrict
        ),
        primary_key: true
      )

      add(:update_id, :binary_id, null: false)
      add(:reference_hash, :binary, null: false)
    end

    create(unique_index(:earnings_pdf_publications, [:update_id, :reference_hash]))
  end
end
