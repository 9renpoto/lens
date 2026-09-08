defmodule Lens.Repo.Migrations.CreateSourceRuns do
  use Ecto.Migration

  def change do
    create table(:source_runs, primary_key: false) do
      add :source_id, references(:sources, type: :binary_id, on_delete: :delete_all), primary_key: true
      add :locked_at, :utc_datetime_usec, null: false
    end
  end
end
