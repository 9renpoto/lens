defmodule Lens.Repo.Migrations.HardenAnalysisMemberships do
  use Ecto.Migration

  def change do
    execute("CREATE EXTENSION IF NOT EXISTS btree_gist", "SELECT 1")

    execute(
      """
      ALTER TABLE analysis_memberships
      ADD CONSTRAINT analysis_memberships_no_overlapping_intervals
      EXCLUDE USING gist (
        target_id WITH =,
        index_name WITH =,
        daterange(effective_from, effective_to, '[]') WITH &&
      )
      """,
      """
      ALTER TABLE analysis_memberships
      DROP CONSTRAINT analysis_memberships_no_overlapping_intervals
      """
    )
  end
end
