defmodule Lens.Repo.Migrations.CreateEarningsAssessments do
  use Ecto.Migration

  def up do
    create table(:earnings_assessments, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:http_check_id, references(:earnings_http_checks, type: :binary_id), null: false)
      add(:target_id, references(:analysis_targets, type: :binary_id), null: false)
      add(:source_id, references(:earnings_sources, type: :binary_id), null: false)
      add(:outcome, :text, null: false)
      add(:document_kind, :text)
      add(:assessor, :text, null: false)
      add(:assessor_version, :text, null: false)
      add(:reason, :text, null: false)
      add(:identity, :map, null: false, default: %{})
      add(:evidence, :map, null: false)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(index(:earnings_assessments, [:http_check_id, :inserted_at, :id]))
    create(index(:earnings_assessments, [:target_id]))
    create(index(:earnings_assessments, [:source_id]))

    create(
      constraint(:earnings_assessments, :earnings_assessment_outcome,
        check: "outcome IN ('accepted', 'excluded', 'pending')"
      )
    )

    create(
      constraint(:earnings_assessments, :earnings_assessment_kind,
        check:
          "(document_kind IS NULL OR document_kind IN ('earnings_release', 'correction', 'earnings_presentation')) AND (outcome <> 'accepted' OR document_kind IS NOT NULL)"
      )
    )

    create(
      constraint(:earnings_assessments, :earnings_assessment_text,
        check:
          "char_length(btrim(assessor)) BETWEEN 1 AND 100 AND char_length(btrim(assessor_version)) BETWEEN 1 AND 100 AND char_length(btrim(reason)) BETWEEN 1 AND 1000"
      )
    )

    create(
      constraint(:earnings_assessments, :earnings_assessment_json,
        check:
          "jsonb_typeof(identity) = 'object' AND jsonb_typeof(evidence) = 'object' AND evidence <> '{}'::jsonb AND octet_length(identity::text) <= 65536 AND octet_length(evidence::text) <= 65536"
      )
    )

    execute("""
    CREATE FUNCTION protect_earnings_assessment() RETURNS trigger AS $$
    BEGIN
      IF TG_OP <> 'INSERT' THEN
        RAISE EXCEPTION 'earnings assessment history is immutable';
      END IF;
      IF NOT EXISTS (
        SELECT 1 FROM earnings_http_checks h
        JOIN earnings_acquisitions a ON a.id = h.acquisition_id
        JOIN earnings_sources s ON s.id = NEW.source_id
        WHERE h.id = NEW.http_check_id AND h.kind = 'pdf' AND h.status = 'success'
          AND a.status = 'success' AND a.original_id IS NOT NULL
          AND a.issuer_code = h.issuer_code AND s.target_id = NEW.target_id
          AND h.metadata->>'source_id' = s.id::text
          AND h.metadata->>'target_id' = s.target_id::text
      ) THEN
        RAISE EXCEPTION 'assessment requires a successful registered-source candidate';
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER earnings_assessments_protected
    BEFORE INSERT OR UPDATE OR DELETE ON earnings_assessments
    FOR EACH ROW EXECUTE FUNCTION protect_earnings_assessment();
    """)
  end

  def down do
    drop(table(:earnings_assessments))
    execute("DROP FUNCTION protect_earnings_assessment()")
  end
end
