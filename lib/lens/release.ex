defmodule Lens.Release do
  @moduledoc """
  Initialize disposable databases from the current schema without upgrades.
  """

  @app :lens

  @spec initialize() :: :ok
  def initialize, do: with_repos(&initialize_repo/1)

  @doc "Initialize an empty database, or verify that its schema matches this release."
  def prepare, do: with_repos(&prepare_repo/1)

  defp with_repos(fun) do
    Application.load(@app)
    {:ok, _} = Application.ensure_all_started(:ecto_sql)

    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      case repo.start_link() do
        {:ok, pid} ->
          try do
            fun.(repo)
          after
            Supervisor.stop(pid)
          end

        {:error, {:already_started, _}} ->
          fun.(repo)
      end
    end

    :ok
  end

  defp prepare_repo(repo) do
    if repo.query!("SELECT to_regclass('public.lens_schema') IS NOT NULL").rows == [[true]] do
      unless repo.query!("SELECT fingerprint FROM public.lens_schema").rows == [[fingerprint()]] do
        raise "schema differs from this release; recreate the disposable database"
      end
    else
      initialize_repo(repo)
    end
  end

  defp initialize_repo(repo) do
    {:ok, :ok} =
      repo.transaction(fn ->
        repo.query!("SELECT pg_advisory_xact_lock(213015)")

        unless repo.query!("""
               SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
               WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p', 'S', 'v', 'm', 'f')
               """).rows == [[0]] do
          raise "initialization requires an empty database; recreate the disposable database"
        end

        repo.query!(File.read!(schema_path()), [], query_type: :text)
        repo.query!("CREATE TABLE public.lens_schema (fingerprint text PRIMARY KEY)")
        repo.query!("INSERT INTO public.lens_schema VALUES ($1)", [fingerprint()])
        :ok
      end)

    :ok
  end

  defp fingerprint, do: :crypto.hash(:sha256, File.read!(schema_path())) |> Base.encode16()
  defp schema_path, do: Application.app_dir(@app, "priv/repo/schema.sql")
end
