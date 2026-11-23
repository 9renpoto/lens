defmodule Lens.ReleaseMigrationTest do
  use ExUnit.Case, async: false

  alias Lens.Release

  @baseline_version 20_261_118_000_000
  @next_version 20_261_118_000_001
  @unknown_version 99_991_231_000_000
  @legacy_fingerprint "0A7C1A8DD186C16317163E76B5C4DF7D08CB19985015E2B001E52BC0BF33B620"

  defmodule MigrationRepo do
    use Ecto.Repo, otp_app: :lens, adapter: Ecto.Adapters.Postgres
  end

  setup tags do
    database = "lens_migration_#{System.pid()}_#{System.unique_integer([:positive])}"

    config =
      Lens.Repo.config()
      |> Keyword.drop([:name, :pool])
      |> Keyword.merge(database: database, priv: "priv/repo", pool_size: 2)

    config =
      if tags[:pending_migration], do: with_pending_migration(config, database), else: config

    assert :ok = Ecto.Adapters.Postgres.storage_up(config)

    previous_repos = Application.fetch_env!(:lens, :ecto_repos)
    Application.put_env(:lens, :ecto_repos, [MigrationRepo])
    Application.put_env(:lens, MigrationRepo, config)

    on_exit(fn ->
      Application.put_env(:lens, :ecto_repos, previous_repos)
      Application.delete_env(:lens, MigrationRepo)
      assert :ok = Ecto.Adapters.Postgres.storage_down(config)
    end)

    start_supervised!({MigrationRepo, config})
    :ok
  end

  test "standard migrations initialize an empty database and preserve the supported baseline" do
    assert [@baseline_version | _] = Ecto.Migrator.run(MigrationRepo, :up, all: true)

    assert query!("""
           SELECT
             to_regclass('public.feed_material_revisions') IS NOT NULL,
             to_regclass('public.earnings_sources') IS NOT NULL,
             to_regclass('public.earnings_assessments') IS NOT NULL,
             to_regclass('public.analysis_memberships') IS NOT NULL
           """) == [[true, true, true, true]]

    assert [] = Ecto.Migrator.run(MigrationRepo, :up, all: true)
  end

  test "concurrent preparation initializes once and can be repeated" do
    preparations = for _ <- 1..2, do: Task.async(&Release.prepare/0)
    assert [:ok, :ok] = Task.await_many(preparations, 15_000)
    assert [@baseline_version | _] = initial_versions = versions()
    assert :ok = Release.prepare()
    assert versions() == initial_versions
  end

  @tag :pending_migration
  test "preparation adopts the deployed schema and applies pending migrations without losing relationships" do
    initialize_legacy!(@legacy_fingerprint)

    query!("""
    WITH target AS (
      INSERT INTO public.analysis_targets
        (id, security_code, market, display_name, sector, inserted_at, updated_at)
      VALUES (gen_random_uuid(), 'ZZ99', 'Example Market', 'Example Issuer', 'Example Sector', now(), now())
      RETURNING id
    )
    INSERT INTO public.analysis_memberships
      (id, target_id, index_name, effective_from, inserted_at, updated_at)
    SELECT gen_random_uuid(), id, 'example_index', '2026-01-01', now(), now() FROM target
    """)

    assert :ok = Release.prepare()
    assert :ok = Release.prepare()
    assert versions() == [@baseline_version, @next_version]

    assert query!("""
           SELECT target.security_code, membership.index_name
           FROM public.analysis_targets target
           JOIN public.analysis_memberships membership ON membership.target_id = target.id
           """) == [["ZZ99", "example_index"]]

    assert query!("SELECT fingerprint FROM public.lens_schema") == [[@legacy_fingerprint]]

    assert {:error, %Postgrex.Error{postgres: %{code: :foreign_key_violation}}} =
             MigrationRepo.query(
               "UPDATE public.analysis_memberships SET target_id = gen_random_uuid()"
             )
  end

  test "preparation rejects an unknown fingerprint without creating migration history" do
    initialize_legacy!("unknown-schema")

    assert_raise RuntimeError, ~r/unknown Lens schema.*deployment guide/i, &Release.prepare/0
    assert query!("SELECT fingerprint FROM public.lens_schema") == [["unknown-schema"]]
    assert query!("SELECT to_regclass('public.schema_migrations') IS NULL") == [[true]]
  end

  test "preparation rejects an untracked nonempty database" do
    query!("CREATE TABLE public.untracked (id integer)")
    assert_raise RuntimeError, ~r/unknown Lens schema.*deployment guide/i, &Release.prepare/0
    assert query!("SELECT to_regclass('public.schema_migrations') IS NULL") == [[true]]
  end

  test "preparation rejects a migration version absent from this release" do
    assert :ok = Release.prepare()
    initial_versions = versions()

    MigrationRepo.query!(
      "INSERT INTO public.schema_migrations (version) VALUES ($1)",
      [@unknown_version]
    )

    assert_raise RuntimeError, ~r/unknown Lens schema.*deployment guide/i, &Release.prepare/0
    assert versions() == initial_versions ++ [@unknown_version]
  end

  @tag :pending_migration
  test "a failed pending migration rolls back its DDL and remains pending for retry" do
    initialize_legacy!(@legacy_fingerprint)
    query!("CREATE TABLE public.release_conflict (id integer)")

    assert_raise RuntimeError,
                 ~r/database preparation failed.*deployment guide/i,
                 &Release.prepare/0

    assert versions() == [@baseline_version]
    assert query!("SELECT to_regclass('public.release_probe') IS NULL") == [[true]]
    assert query!("SELECT fingerprint FROM public.lens_schema") == [[@legacy_fingerprint]]

    query!("DROP TABLE public.release_conflict")
    assert :ok = Release.prepare()
    assert versions() == [@baseline_version, @next_version]
    assert query!("SELECT to_regclass('public.release_probe') IS NOT NULL") == [[true]]
  end

  test "explicit initialization refuses a database that already has records" do
    initialize_legacy!(@legacy_fingerprint)
    assert_raise RuntimeError, ~r/empty database/, &Release.initialize/0
    assert query!("SELECT fingerprint FROM public.lens_schema") == [[@legacy_fingerprint]]
  end

  defp initialize_legacy!(fingerprint) do
    schema =
      Application.app_dir(:lens, "priv/repo/migrations/20261118000000_baseline.sql")
      |> File.read!()

    MigrationRepo.query!(schema, [], query_type: :text)
    query!("CREATE TABLE public.lens_schema (fingerprint text PRIMARY KEY)")
    MigrationRepo.query!("INSERT INTO public.lens_schema VALUES ($1)", [fingerprint])
  end

  defp versions do
    query!("SELECT version FROM public.schema_migrations ORDER BY version")
    |> List.flatten()
  end

  defp query!(sql), do: MigrationRepo.query!(sql).rows

  defp with_pending_migration(config, database) do
    directory = Application.app_dir(:lens, Path.join(database, "migrations"))
    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(Path.dirname(directory)) end)

    source = Application.app_dir(:lens, "priv/repo/migrations/20261118000000_baseline.exs")
    File.cp!(source, Path.join(directory, Path.basename(source)))

    File.write!(Path.join(directory, "20261118000001_release_probe.exs"), """
    defmodule Lens.TestMigrations.ReleaseProbe do
      use Ecto.Migration

      def up do
        execute("CREATE TABLE public.release_probe (id integer)")
        execute("CREATE TABLE public.release_conflict (id integer)")
      end
    end
    """)

    Keyword.put(config, :priv, database)
  end
end
