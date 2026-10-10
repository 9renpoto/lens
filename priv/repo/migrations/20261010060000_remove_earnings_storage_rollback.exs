defmodule Lens.Repo.Migrations.RemoveEarningsStorageRollback do
  use Ecto.Migration

  def up do
    drop(table(:earnings_storage_controls))

    execute("""
    CREATE OR REPLACE FUNCTION reject_earnings_original_mutation() RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION 'earnings originals are immutable';
    END;
    $$ LANGUAGE plpgsql;
    """)
  end

  def down do
    raise Ecto.MigrationError,
          "storage rollback removal is forward-only; restore a coordinated backup instead"
  end
end
