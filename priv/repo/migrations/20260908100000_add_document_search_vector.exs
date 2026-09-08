defmodule Lens.Repo.Migrations.AddDocumentSearchVector do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE documents ADD COLUMN search_vector tsvector GENERATED ALWAYS AS (
      setweight(to_tsvector('simple', coalesce(title, '')), 'A') ||
      setweight(to_tsvector('simple', content), 'B')
    ) STORED
    """)

    execute("CREATE INDEX documents_search_vector_index ON documents USING GIN (search_vector)")
  end

  def down do
    execute("DROP INDEX documents_search_vector_index")
    execute("ALTER TABLE documents DROP COLUMN search_vector")
  end
end
