defmodule Lens.Repo.Migrations.RecordExtractionOptions do
  use Ecto.Migration

  def change do
    alter table(:earnings_extractions) do
      add(:extraction_options, :map, null: false, default: %{})
    end

    create(
      constraint(:earnings_extractions, :extraction_options_bounds,
        check: """
        extraction_options = '{}'::jsonb OR (
          jsonb_typeof(extraction_options) = 'object'
          AND jsonb_typeof(extraction_options->'timeout_ms') = 'number'
          AND (extraction_options->>'timeout_ms')::integer BETWEEN 1 AND 30000
          AND jsonb_typeof(extraction_options->'max_output_bytes') = 'number'
          AND (extraction_options->>'max_output_bytes')::integer BETWEEN 1 AND 8388608
        )
        """
      )
    )
  end
end
