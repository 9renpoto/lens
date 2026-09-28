defmodule Lens.Search.Earnings do
  @moduledoc false
  import Ecto.Query
  alias Lens.Earnings.{Acquisition, Extraction, Release}
  alias Lens.Repo
  alias Lens.Search.Normalizer

  def query(normalized_query, match? \\ true) do
    eligible =
      from(a in Acquisition,
        where: a.status == "success" and not is_nil(a.release_id),
        group_by: [a.release_id, a.original_id],
        select: %{
          release_id: a.release_id,
          original_id: a.original_id,
          first_at: min(a.acquired_at),
          url: min(a.url)
        }
      )

    latest =
      from(o in subquery(eligible),
        distinct: o.release_id,
        order_by: [asc: o.release_id, desc: o.first_at, desc: o.original_id]
      )

    selected =
      from(e in Extraction,
        join: o in subquery(eligible),
        on: e.original_id == o.original_id,
        where: e.status == "succeeded",
        distinct: o.release_id,
        order_by: [asc: o.release_id, desc: o.first_at, desc: o.original_id, desc: e.id],
        select: %{
          release_id: o.release_id,
          extraction_id: e.id,
          original_id: o.original_id,
          url: o.url
        }
      )

    from(s in subquery(selected),
      join: e in Extraction,
      on: e.id == s.extraction_id,
      join: r in Release,
      on: r.id == s.release_id,
      join: l in subquery(latest),
      on: l.release_id == r.id,
      where:
        not (^match?) or
          fragment(
            "search_vector @@ websearch_to_tsquery('simple', ?) OR search_text ILIKE '%' || ? || '%' ESCAPE E'\\\\'",
            ^normalized_query,
            ^normalized_query
          ),
      select: %{
        id: r.id,
        title:
          fragment(
            "? || ' ' || ?::text || ' ' || ? || ' ' || ?",
            r.issuer_code,
            r.fiscal_year_end,
            r.period,
            r.category
          ),
        canonical_url: s.url,
        published_at: type(^nil, :utc_datetime_usec),
        excerpt: fragment("left(regexp_replace(?, '\\s+', ' ', 'g'), 300)", e.text),
        resource_type: "earnings_release",
        original_id: s.original_id,
        extraction_id: s.extraction_id,
        stale: s.original_id != l.original_id,
        search_mode:
          fragment("CASE WHEN ?.search_vector IS NULL THEN 'substring' ELSE 'full_text' END", e),
        title_match: 0,
        rank:
          fragment(
            "coalesce(ts_rank(search_vector, websearch_to_tsquery('simple', ?)), 0)",
            ^normalized_query
          )
      }
    )
  end

  def rebuild(batch_size) do
    # An older migration invokes Search.rebuild before this table/column exists.
    %{rows: [[available]]} =
      Repo.query!(
        "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'earnings_extractions' AND column_name = 'search_text')"
      )

    if available, do: rebuild_batches(0, batch_size), else: :ok
  end

  defp rebuild_batches(last_id, size) do
    batch =
      Repo.all(
        from(e in Extraction,
          where: e.id > ^last_id,
          order_by: [asc: e.id],
          limit: ^size,
          select: %{id: e.id, text: e.text}
        )
      )

    case batch do
      [] ->
        :ok

      _ ->
        Enum.each(batch, fn e ->
          Repo.update_all(
            from(current in Extraction,
              where:
                current.id == ^e.id and
                  fragment("? IS NOT DISTINCT FROM ?", current.text, ^e.text)
            ),
            set: [search_text: Normalizer.document_text(nil, e.text)]
          )
        end)

        rebuild_batches(List.last(batch).id, size)
    end
  end
end
