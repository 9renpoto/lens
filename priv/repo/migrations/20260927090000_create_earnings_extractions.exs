defmodule Lens.Repo.Migrations.CreateEarningsExtractions do
  use Ecto.Migration

  def change do
    create table(:earnings_extractions) do
      add(:original_id, references(:earnings_originals, type: :uuid, on_delete: :restrict),
        null: false
      )

      add(:extractor, :text, null: false)
      add(:extractor_version, :text, null: false)
      add(:status, :text, null: false)
      add(:text, :text)
      add(:failure_reason, :text)
      add(:finished_at, :utc_datetime_usec)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(index(:earnings_extractions, [:original_id, :id]))

    create(
      constraint(:earnings_extractions, :extraction_outcome,
        check: """
        (status = 'pending' AND text IS NULL AND failure_reason IS NULL AND finished_at IS NULL)
        OR (status = 'succeeded' AND text IS NOT NULL AND length(btrim(text)) > 0
            AND failure_reason IS NULL AND finished_at IS NOT NULL)
        OR (status = 'failed' AND text IS NULL AND failure_reason IS NOT NULL
            AND length(btrim(failure_reason)) > 0 AND finished_at IS NOT NULL)
        """
      )
    )
  end
end
