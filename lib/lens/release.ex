defmodule Lens.Release do
  @moduledoc """
  Prepare PostgreSQL for a Lens release without starting the application.
  """

  alias Ecto.Migrator

  @app :lens
  @baseline_version 20_261_118_000_000
  @legacy_fingerprint "0A7C1A8DD186C16317163E76B5C4DF7D08CB19985015E2B001E52BC0BF33B620"
  @prepare_lock 213_015
  @migration_opts [prefix: "public"]
  @guide "docs/deployment.md#database-initialization"

  defmodule AdoptBaseline do
    @moduledoc false
    use Ecto.Migration

    # The legacy initializer already applied this exact schema.
    def up, do: :ok
  end

  @doc "Initialize an empty database using the release migrations."
  @spec initialize() :: :ok
  def initialize do
    with_repos(fn repo ->
      unless empty?(repo) and not relation?(repo, "schema_migrations") do
        raise "initialization requires an empty database"
      end

      migrate!(repo)
    end)
  end

  @doc "Initialize an empty database or upgrade a supported Lens database."
  @spec prepare() :: :ok
  def prepare do
    with_repos(fn repo ->
      cond do
        managed?(repo) -> :ok
        legacy_baseline?(repo) -> migrate!(repo, :adopt_baseline)
        empty?(repo) -> :ok
        true -> unknown_schema!()
      end

      migrate!(repo)
    end)
  end

  defp with_repos(fun) do
    Application.load(@app)

    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      {:ok, :ok, _started} = Migrator.with_repo(repo, &with_prepare_lock(&1, fun))
    end

    :ok
  end

  # Serialize baseline recognition and migration table creation across release commands.
  # A waiting caller must give its connection back so Ecto can run migration transactions.
  defp with_prepare_lock(repo, fun) do
    result =
      repo.checkout(
        fn ->
          case repo.query!("SELECT pg_try_advisory_lock($1)", [@prepare_lock]).rows do
            [[true]] ->
              try do
                fun.(repo)
              after
                repo.query!("SELECT pg_advisory_unlock($1)", [@prepare_lock])
              end

            [[false]] ->
              :busy
          end
        end,
        timeout: :infinity
      )

    case result do
      :ok ->
        :ok

      :busy ->
        Process.sleep(100)
        with_prepare_lock(repo, fun)
    end
  end

  defp managed?(repo) do
    if relation?(repo, "schema_migrations") do
      statuses =
        Migrator.migrations(repo, [Migrator.migrations_path(repo)],
          prefix: "public",
          skip_table_creation: true
        )

      {applied, remaining} = Enum.split_while(statuses, &match?({:up, _, _}, &1))

      if Enum.any?(applied, &match?({:up, _, "** FILE NOT FOUND **"}, &1)) or
           Enum.any?(remaining, &match?({:up, _, _}, &1)) do
        unknown_schema!()
      end

      case applied do
        [] -> false
        [{:up, @baseline_version, _} | _] -> true
        _ -> unknown_schema!()
      end
    else
      false
    end
  end

  defp legacy_baseline?(repo) do
    if relation?(repo, "lens_schema") do
      unless repo.query!("SELECT fingerprint FROM public.lens_schema").rows ==
               [[@legacy_fingerprint]] do
        unknown_schema!()
      end

      true
    else
      false
    end
  end

  defp empty?(repo) do
    repo.query!("""
    SELECT NOT EXISTS (
      SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p', 'S', 'v', 'm', 'f')
        AND c.relname <> 'schema_migrations'
    )
    """).rows == [[true]]
  end

  defp relation?(repo, name) do
    repo.query!("SELECT to_regclass($1) IS NOT NULL", ["public." <> name]).rows == [[true]]
  end

  defp unknown_schema! do
    raise "Unknown Lens schema. Check the database and release version in the deployment guide (#{@guide})."
  end

  defp migrate!(repo, step \\ :pending) do
    case step do
      :adopt_baseline -> Migrator.up(repo, @baseline_version, AdoptBaseline, @migration_opts)
      :pending -> Migrator.run(repo, :up, Keyword.put(@migration_opts, :all, true))
    end

    :ok
  rescue
    error ->
      reraise RuntimeError,
              "Database preparation failed. Follow the recovery steps in the deployment guide (#{@guide}). " <>
                Exception.message(error),
              __STACKTRACE__
  end
end
