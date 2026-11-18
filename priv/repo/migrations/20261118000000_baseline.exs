defmodule Lens.Repo.Migrations.Baseline do
  use Ecto.Migration

  def up do
    execute(fn ->
      schema = Application.app_dir(:lens, "priv/repo/migrations/20261118000000_baseline.sql")
      repo().query!(File.read!(schema), [], query_type: :text, timeout: :infinity)
    end)
  end

  def down do
    raise Ecto.MigrationError, "the Lens baseline cannot be rolled back"
  end
end
