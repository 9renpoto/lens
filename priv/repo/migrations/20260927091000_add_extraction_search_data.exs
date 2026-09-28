defmodule Lens.Repo.Migrations.AddExtractionSearchData do
  use Ecto.Migration

  def up do
    alter table(:earnings_extractions) do
      add(:search_text, :text, null: false, default: "")
    end

    execute("""
    CREATE FUNCTION earnings_search_vector(input text) RETURNS tsvector
    LANGUAGE plpgsql IMMUTABLE STRICT AS $function$
    BEGIN
      RETURN to_tsvector('simple', input);
    EXCEPTION WHEN program_limit_exceeded THEN
      RETURN NULL;
    END;
    $function$
    """)

    execute(
      "ALTER TABLE earnings_extractions ADD COLUMN search_vector tsvector GENERATED ALWAYS AS (earnings_search_vector(text)) STORED"
    )

    execute(
      "CREATE INDEX earnings_extractions_search_vector_index ON earnings_extractions USING GIN (search_vector)"
    )

    execute(
      "CREATE INDEX earnings_extractions_search_text_index ON earnings_extractions USING GIN (search_text gin_trgm_ops)"
    )

    flush()
    Lens.Search.rebuild()
  end

  def down do
    execute("DROP INDEX earnings_extractions_search_text_index")
    execute("DROP INDEX earnings_extractions_search_vector_index")
    execute("ALTER TABLE earnings_extractions DROP COLUMN search_vector")
    execute("DROP FUNCTION IF EXISTS earnings_search_vector(text)")
    alter(table(:earnings_extractions), do: remove(:search_text))
  end
end
