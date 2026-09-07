defmodule Lens.Repo.Migrations.CreateContentStorage do
  use Ecto.Migration

  def change do
    create table(:sources, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :source_type, :string, null: false
      add :endpoint_url, :text, null: false
      add :title, :string
      add :enabled, :boolean, null: false, default: true
      add :poll_interval_seconds, :integer, null: false
      add :next_fetch_at, :utc_datetime_usec
      add :etag, :string
      add :last_modified, :string
      add :last_attempt_at, :utc_datetime_usec
      add :last_success_at, :utc_datetime_usec
      add :last_error, :text
      add :failure_count, :integer, null: false, default: 0
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:sources, [:endpoint_url])
    create constraint(:sources, :poll_interval_seconds_must_be_positive,
             check: "poll_interval_seconds > 0"
           )

    create constraint(:sources, :failure_count_must_not_be_negative,
             check: "failure_count >= 0"
           )

    create table(:documents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :identity_key, :text, null: false
      add :canonical_url, :text
      add :title, :text
      add :content, :text, null: false
      add :author, :text
      add :published_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}
      add :content_hash, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:documents, [:identity_key])
    create unique_index(:documents, [:canonical_url], where: "canonical_url IS NOT NULL")

    create table(:observations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :source_id, references(:sources, type: :binary_id, on_delete: :restrict), null: false
      add :document_id, references(:documents, type: :binary_id, on_delete: :restrict), null: false
      add :observed_at, :utc_datetime_usec, null: false
      add :content_hash, :string, null: false
      add :fetch_metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:observations, [:source_id, :observed_at])
    create index(:observations, [:document_id, :observed_at])
    create unique_index(:observations, [:source_id, :document_id, :observed_at])
  end
end
