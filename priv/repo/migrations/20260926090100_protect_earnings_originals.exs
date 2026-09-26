defmodule Lens.Repo.Migrations.ProtectEarningsOriginals do
  use Ecto.Migration

  def up do
    execute("""
    CREATE FUNCTION reject_earnings_original_mutation() RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION 'earnings originals are immutable';
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER earnings_originals_immutable
    BEFORE UPDATE OR DELETE ON earnings_originals
    FOR EACH ROW EXECUTE FUNCTION reject_earnings_original_mutation();
    """)
  end

  def down do
    execute("DROP TRIGGER earnings_originals_immutable ON earnings_originals")
    execute("DROP FUNCTION reject_earnings_original_mutation()")
  end
end
