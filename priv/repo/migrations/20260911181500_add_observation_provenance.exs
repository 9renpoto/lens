defmodule Lens.Repo.Migrations.AddObservationProvenance do
  use Ecto.Migration

  def up do
    alter table(:observations) do
      add :entry_url, :text
      add :primary_source_url, :text
      add :feed_format, :string, null: false, default: "unknown"
      add :acquisition_kind, :string, null: false, default: "unknown"
      add :publisher_authority, :string, null: false, default: "unknown"
      add :acquisition_metadata_snapshot, :map, null: false, default: %{}
      add :reported_published_at, :utc_datetime_usec
    end

    create constraint(:observations, :observations_feed_format_valid,
             check: "feed_format IN ('rss_2_0', 'atom', 'rss_1_0', 'unknown')"
           )

    create constraint(:observations, :observations_acquisition_kind_valid,
             check: "acquisition_kind IN ('direct', 'conversion_service', 'rsshub', 'unknown')"
           )

    create constraint(:observations, :observations_publisher_authority_valid,
             check: "publisher_authority IN ('official', 'third_party', 'unknown')"
           )
  end

  def down do
    drop constraint(:observations, :observations_publisher_authority_valid)
    drop constraint(:observations, :observations_acquisition_kind_valid)
    drop constraint(:observations, :observations_feed_format_valid)

    alter table(:observations) do
      remove :reported_published_at
      remove :acquisition_metadata_snapshot
      remove :publisher_authority
      remove :acquisition_kind
      remove :feed_format
      remove :primary_source_url
      remove :entry_url
    end
  end
end
