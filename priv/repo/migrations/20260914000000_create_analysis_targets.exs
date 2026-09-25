defmodule Lens.Repo.Migrations.CreateAnalysisTargets do
  use Ecto.Migration

  def change do
    create table(:analysis_targets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :security_code, :string, null: false
      add :market, :string, null: false
      add :display_name, :string, null: false
      add :sector, :string, null: false
      add :tags, {:array, :string}, default: [], null: false
      add :active, :boolean, default: true, null: false
      add :source_reference, :text
      add :verified_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:analysis_targets, [:security_code])

    create table(:analysis_memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :target_id, references(:analysis_targets, type: :binary_id, on_delete: :delete_all),
        null: false

      add :index_name, :string, default: "nikkei_225", null: false
      add :effective_from, :date, null: false
      add :effective_to, :date
      add :source_reference, :text
      add :verified_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:analysis_memberships, [:target_id])
    create index(:analysis_memberships, [:index_name, :effective_from, :effective_to])

    create constraint(:analysis_memberships, :effective_to_must_be_on_or_after_effective_from,
             check: "effective_to IS NULL OR effective_to >= effective_from"
           )
  end
end
