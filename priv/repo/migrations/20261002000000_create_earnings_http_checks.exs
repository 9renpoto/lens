defmodule Lens.Repo.Migrations.CreateEarningsHTTPChecks do
  use Ecto.Migration

  def up do
    create table(:earnings_http_checks, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:check_id, :string, null: false, size: 180)
      add(:issuer_code, :string, null: false)
      add(:kind, :string, null: false)
      add(:url, :text, null: false)
      add(:final_url, :text, null: false)
      add(:checked_at, :utc_datetime_usec, null: false)
      add(:published_on, :date)
      add(:status, :string, null: false)
      add(:failure_reason, :string)
      add(:http_status, :integer)
      add(:requests, :integer, null: false)
      add(:retryable, :boolean, null: false)
      add(:response_headers, :map, null: false, default: %{})
      add(:metadata, :map, null: false, default: %{})
      add(:sha256, :string)
      add(:byte_size, :bigint)

      add(
        :acquisition_id,
        references(:earnings_acquisitions, type: :binary_id, on_delete: :restrict)
      )

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(unique_index(:earnings_http_checks, [:check_id]))
    create(unique_index(:earnings_http_checks, [:acquisition_id]))
    create(index(:earnings_http_checks, [:issuer_code, :checked_at, :id]))

    create(
      constraint(:earnings_http_checks, :earnings_http_check_bounds,
        check:
          "issuer_code IN ('6857','9983','8035') AND kind IN ('pdf','listing') AND requests BETWEEN 0 AND 4 AND (http_status IS NULL OR http_status BETWEEN 100 AND 599) AND (byte_size IS NULL OR byte_size BETWEEN 0 AND CASE WHEN kind = 'pdf' THEN 20971520 ELSE 2097152 END)"
      )
    )

    create(
      constraint(:earnings_http_checks, :earnings_http_check_outcome,
        check:
          "(status = 'success' AND failure_reason IS NULL AND http_status IS NOT NULL AND http_status = 200 AND requests > 0 AND sha256 IS NOT NULL AND sha256 ~ '^[0-9a-f]{64}$' AND byte_size IS NOT NULL) OR (status = 'not_modified' AND failure_reason IS NULL AND http_status IS NOT NULL AND http_status = 304 AND requests > 0 AND sha256 IS NULL AND byte_size IS NULL) OR (status = 'failed' AND failure_reason IS NOT NULL AND sha256 IS NULL AND byte_size IS NULL)"
      )
    )

    create(
      constraint(:earnings_http_checks, :earnings_http_check_acquisition,
        check:
          "(kind = 'pdf' AND (status = 'success' OR (status = 'failed' AND requests > 0)) AND acquisition_id IS NOT NULL) OR ((kind = 'listing' OR status = 'not_modified' OR requests = 0) AND acquisition_id IS NULL)"
      )
    )

    create(
      constraint(:earnings_http_checks, :earnings_http_check_response,
        check:
          "(requests > 0 OR (final_url = url AND http_status IS NULL AND response_headers = '{}'::jsonb)) AND (status = 'failed' OR retryable = false)"
      )
    )

    execute("""
    CREATE FUNCTION protect_earnings_http_check() RETURNS trigger AS $$
    BEGIN
      IF TG_OP <> 'INSERT' THEN
        RAISE EXCEPTION 'earnings HTTP check facts are immutable';
      END IF;
      IF NEW.acquisition_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM earnings_acquisitions a
        WHERE a.id = NEW.acquisition_id AND a.issuer_code = NEW.issuer_code
          AND a.status = NEW.status AND a.acquired_at = NEW.checked_at
          AND a.acquisition_id = 'http:' || NEW.check_id
          AND a.failure_reason IS NOT DISTINCT FROM NEW.failure_reason
          AND (NEW.status <> 'success' OR EXISTS (
            SELECT 1 FROM earnings_originals o WHERE o.id = a.original_id
              AND o.sha256 = NEW.sha256 AND o.byte_size = NEW.byte_size
          ))
          AND a.url = CASE WHEN NEW.status = 'success' THEN NEW.final_url ELSE NEW.url END
      ) THEN
        RAISE EXCEPTION 'HTTP check acquisition facts do not match'
          USING ERRCODE = '23514', CONSTRAINT = 'earnings_http_check_acquisition_facts';
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER earnings_http_checks_protected
    BEFORE INSERT OR UPDATE OR DELETE ON earnings_http_checks
    FOR EACH ROW EXECUTE FUNCTION protect_earnings_http_check();
    """)
  end

  def down do
    drop(table(:earnings_http_checks))
    execute("DROP FUNCTION protect_earnings_http_check()")
  end
end
