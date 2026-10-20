defmodule Lens.Repo.Migrations.RetireEarningsStorageRecovery do
  use Ecto.Migration

  def up do
    execute(
      "LOCK TABLE earnings_storage_work, earnings_storage_retry_audits IN ACCESS EXCLUSIVE MODE"
    )

    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM earnings_storage_work
        WHERE status != 'completed' OR bytes IS NOT NULL
      ) THEN
        RAISE EXCEPTION 'unfinished storage work prevents recovery retirement';
      END IF;
    END;
    $$;
    """)

    drop(table(:earnings_storage_retry_audits))
    drop(table(:earnings_storage_work))
  end

  def down do
    raise "storage recovery retirement is forward-only"
  end
end
