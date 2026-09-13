defmodule Lens.Repo.Migrations.AddCjkSearchText do
  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")

    alter table(:documents) do
      add(:search_text, :text, null: false, default: "")
      add(:search_title, :text, null: false, default: "")
    end

    execute("CREATE INDEX documents_search_text_trgm_index ON documents USING GIN (search_text gin_trgm_ops)")

    flush()
    Lens.Search.rebuild()
  end

  def down do
    execute("DROP INDEX documents_search_text_trgm_index")

    alter table(:documents) do
      remove(:search_title)
      remove(:search_text)
    end
  end
end
