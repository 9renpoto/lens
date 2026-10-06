defmodule Lens.Repo.Migrations.CreateEarningsSources do
  use Ecto.Migration

  def change do
    create table(:earnings_sources, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(:target_id, references(:analysis_targets, type: :binary_id, on_delete: :restrict),
        null: false
      )

      add(:listing_url, :text, null: false)
      add(:enabled, :boolean, null: false, default: true)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:earnings_sources, [:target_id, :listing_url]))

    create(
      constraint(:earnings_sources, :earnings_source_url_length,
        check: "octet_length(listing_url) BETWEEN 1 AND 2048"
      )
    )
  end
end
