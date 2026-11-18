defmodule Lens.ReleaseMigrationTest do
  use ExUnit.Case, async: false

  defmodule MigrationRepo do
    use Ecto.Repo, otp_app: :lens, adapter: Ecto.Adapters.Postgres
  end

  setup do
    database = "lens_migration_#{System.pid()}_#{System.unique_integer([:positive])}"

    config =
      Lens.Repo.config()
      |> Keyword.drop([:name, :pool])
      |> Keyword.put(:database, database)

    assert :ok = Ecto.Adapters.Postgres.storage_up(config)
    on_exit(fn -> assert :ok = Ecto.Adapters.Postgres.storage_down(config) end)
    start_supervised!({MigrationRepo, config})
    :ok
  end

  test "standard migrations initialize an empty database and preserve the supported baseline" do
    path = Application.app_dir(:lens, "priv/repo/migrations")

    assert [version] = Ecto.Migrator.run(MigrationRepo, path, :up, all: true)
    assert Ecto.Migrator.migrated_versions(MigrationRepo) == [version]

    assert MigrationRepo.query!("""
           SELECT
             to_regclass('public.feed_material_revisions') IS NOT NULL,
             to_regclass('public.earnings_sources') IS NOT NULL,
             to_regclass('public.earnings_assessments') IS NOT NULL,
             to_regclass('public.analysis_memberships') IS NOT NULL
           """).rows == [[true, true, true, true]]

    assert [] = Ecto.Migrator.run(MigrationRepo, path, :up, all: true)
  end
end
