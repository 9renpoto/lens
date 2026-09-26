defmodule Lens.Repo.Migrations.ProtectEarningsProvenance do
  use Ecto.Migration

  def up do
    execute("""
    CREATE FUNCTION reject_earnings_release_mutation() RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION 'earnings release identity is immutable';
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER earnings_releases_immutable
    BEFORE UPDATE OR DELETE ON earnings_releases
    FOR EACH ROW EXECUTE FUNCTION reject_earnings_release_mutation();
    """)

    execute("""
    CREATE FUNCTION protect_earnings_acquisition() RETURNS trigger AS $$
    BEGIN
      IF TG_OP = 'UPDATE'
         AND OLD.release_id IS NULL
         AND NEW.release_id IS NOT NULL
         AND OLD.status = 'success'
         AND ROW(NEW.id, NEW.acquisition_id, NEW.issuer_code, NEW.url,
                 NEW.acquired_at, NEW.status, NEW.failure_reason,
                 NEW.original_id, NEW.inserted_at)
             IS NOT DISTINCT FROM
             ROW(OLD.id, OLD.acquisition_id, OLD.issuer_code, OLD.url,
                 OLD.acquired_at, OLD.status, OLD.failure_reason,
                 OLD.original_id, OLD.inserted_at)
         AND EXISTS (SELECT 1 FROM earnings_releases r
                     WHERE r.id = NEW.release_id AND r.issuer_code = NEW.issuer_code)
      THEN
        RETURN NEW;
      END IF;

      RAISE EXCEPTION 'earnings acquisition provenance is immutable';
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER earnings_acquisitions_immutable
    BEFORE UPDATE OR DELETE ON earnings_acquisitions
    FOR EACH ROW EXECUTE FUNCTION protect_earnings_acquisition();
    """)
  end

  def down do
    execute("DROP TRIGGER earnings_acquisitions_immutable ON earnings_acquisitions")
    execute("DROP FUNCTION protect_earnings_acquisition()")
    execute("DROP TRIGGER earnings_releases_immutable ON earnings_releases")
    execute("DROP FUNCTION reject_earnings_release_mutation()")
  end
end
