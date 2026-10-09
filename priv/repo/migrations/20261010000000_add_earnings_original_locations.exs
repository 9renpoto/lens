defmodule Lens.Repo.Migrations.AddEarningsOriginalLocations do
  use Ecto.Migration

  def up do
    alter table(:earnings_originals) do
      modify(:bytes, :binary, null: true)
    end

    drop(constraint(:earnings_originals, :earnings_originals_size_check))

    create(
      constraint(:earnings_originals, :earnings_originals_size_check,
        check:
          "byte_size > 0 AND byte_size <= 20971520 AND (bytes IS NULL OR byte_size = octet_length(bytes))"
      )
    )

    execute("""
    CREATE OR REPLACE FUNCTION reject_earnings_original_mutation() RETURNS trigger AS $$
    BEGIN
      IF TG_OP = 'UPDATE'
         AND OLD.bytes IS NULL
         AND NEW.bytes IS NOT NULL
         AND ROW(NEW.id, NEW.sha256, NEW.byte_size, NEW.inserted_at)
             IS NOT DISTINCT FROM
             ROW(OLD.id, OLD.sha256, OLD.byte_size, OLD.inserted_at)
         AND octet_length(NEW.bytes) = NEW.byte_size
      THEN
        RETURN NEW;
      END IF;

      RAISE EXCEPTION 'earnings originals are immutable';
    END;
    $$ LANGUAGE plpgsql;
    """)

    create table(:earnings_original_storage_locations, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:original_id, references(:earnings_originals, type: :binary_id), null: false)
      add(:backend, :string, null: false)
      add(:key, :text)
      add(:sha256, :string, null: false)
      add(:byte_size, :integer, null: false)
      add(:verified_at, :utc_datetime_usec, null: false)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(unique_index(:earnings_original_storage_locations, [:original_id, :backend]))
    create(unique_index(:earnings_original_storage_locations, [:id, :original_id]))

    execute("""
    CREATE FUNCTION reject_earnings_original_storage_location_mutation() RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION 'earnings original storage locations are immutable';
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER earnings_original_storage_locations_immutable
    BEFORE UPDATE OR DELETE ON earnings_original_storage_locations
    FOR EACH ROW EXECUTE FUNCTION reject_earnings_original_storage_location_mutation();
    """)

    create(
      constraint(:earnings_original_storage_locations, :earnings_original_storage_backend,
        check:
          "(backend = 'postgresql' AND key IS NULL) OR (backend = 'rustfs' AND key IS NOT NULL)"
      )
    )

    create(
      constraint(:earnings_original_storage_locations, :earnings_original_storage_digest,
        check: "sha256 ~ '^[0-9a-f]{64}$' AND byte_size BETWEEN 1 AND 20971520"
      )
    )

    create table(:earnings_original_read_locations, primary_key: false) do
      add(:original_id, references(:earnings_originals, type: :binary_id), primary_key: true)

      add(:location_id, :binary_id, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    execute("""
    ALTER TABLE earnings_original_read_locations
    ADD CONSTRAINT earnings_original_read_location_match
    FOREIGN KEY (location_id, original_id)
    REFERENCES earnings_original_storage_locations (id, original_id)
    """)

    create table(:earnings_storage_controls, primary_key: false) do
      add(:id, :integer, primary_key: true)
      add(:rollback_active, :boolean, null: false, default: false)
      add(:rollback_started_at, :utc_datetime_usec)
    end

    create(
      constraint(:earnings_storage_controls, :earnings_storage_controls_state,
        check:
          "id = 1 AND ((rollback_active AND rollback_started_at IS NOT NULL) OR " <>
            "(NOT rollback_active AND rollback_started_at IS NULL))"
      )
    )

    execute("INSERT INTO earnings_storage_controls (id, rollback_active) VALUES (1, FALSE)")
  end

  def down do
    execute("""
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM earnings_originals WHERE bytes IS NULL) THEN
        RAISE EXCEPTION 'cannot remove original locations while RustFS-only originals remain';
      END IF;

      IF EXISTS (SELECT 1 FROM earnings_storage_controls WHERE rollback_active) THEN
        RAISE EXCEPTION 'cannot remove original locations while rollback is active';
      END IF;
    END;
    $$;
    """)

    drop(table(:earnings_storage_controls))
    drop(table(:earnings_original_read_locations))

    execute(
      "DROP TRIGGER earnings_original_storage_locations_immutable ON earnings_original_storage_locations"
    )

    execute("DROP FUNCTION reject_earnings_original_storage_location_mutation()")
    drop(table(:earnings_original_storage_locations))

    execute("""
    CREATE OR REPLACE FUNCTION reject_earnings_original_mutation() RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION 'earnings originals are immutable';
    END;
    $$ LANGUAGE plpgsql;
    """)

    drop(constraint(:earnings_originals, :earnings_originals_size_check))

    create(
      constraint(:earnings_originals, :earnings_originals_size_check,
        check: "byte_size = octet_length(bytes) AND byte_size <= 20971520 AND byte_size > 0"
      )
    )

    alter table(:earnings_originals) do
      modify(:bytes, :binary, null: false)
    end
  end
end
