defmodule Lens.Repo.Migrations.AddSourceProvenanceClassification do
  use Ecto.Migration

  def up do
    alter table(:sources) do
      add :feed_format, :string, null: false, default: "unknown"
      add :acquisition_kind, :string, null: false, default: "unknown"
      add :publisher_authority, :string, null: false, default: "unknown"
      add :original_feed_url, :text
      add :acquisition_metadata, :map, null: false, default: %{}
    end

    execute("UPDATE sources SET feed_format = 'atom' WHERE source_type = 'atom'")
    execute("UPDATE sources SET acquisition_kind = 'rsshub' WHERE source_type = 'rsshub'")

    create constraint(:sources, :sources_feed_format_valid,
             check: "feed_format IN ('rss_2_0', 'atom', 'rss_1_0', 'unknown')"
           )

    create constraint(:sources, :sources_acquisition_kind_valid,
             check: "acquisition_kind IN ('direct', 'conversion_service', 'rsshub', 'unknown')"
           )

    create constraint(:sources, :sources_publisher_authority_valid,
             check: "publisher_authority IN ('official', 'third_party', 'unknown')"
           )
  end

  def down do
    drop constraint(:sources, :sources_publisher_authority_valid)
    drop constraint(:sources, :sources_acquisition_kind_valid)
    drop constraint(:sources, :sources_feed_format_valid)

    alter table(:sources) do
      remove :acquisition_metadata
      remove :original_feed_url
      remove :publisher_authority
      remove :acquisition_kind
      remove :feed_format
    end
  end
end
