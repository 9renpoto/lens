defmodule Lens.Ingestion.MaterialIndex do
  @moduledoc "Extract and index each acquired feed material independently."
  import Ecto.Query
  alias Lens.{Earnings, ErrorReporter, Repo}
  alias Lens.Earnings.PDFExtractor
  alias Lens.Ingestion.Material
  alias Lens.Search.Normalizer

  def index_many(materials, options \\ []) do
    Enum.flat_map(materials, fn material ->
      case index(material, options) do
        :ok ->
          []

        {:error, stage, reason} ->
          ErrorReporter.report(stage, reason)
          [%{stage: stage, reason: reason}]
      end
    end)
  end

  defp index(material, options) do
    with {:ok, text} <- text(material, options),
         true <- valid_text?(text) || {:error, :extraction, :invalid_text},
         :ok <- save(material, text) do
      :ok
    end
  rescue
    _ -> {:error, :indexing, :processing_failed}
  end

  defp text(%Material{kind: "html", text: text}, _), do: {:ok, text}

  defp text(%Material{kind: "pdf", original_id: id}, options) do
    extractor = Keyword.get(options, :extractor, PDFExtractor)

    with {:ok, bytes} <- Earnings.original_bytes(id, Keyword.take(options, [:rustfs])),
         {:ok, %{text: text}} <- extractor.extract(bytes, options) do
      {:ok, text}
    else
      _ -> {:error, :extraction, :extraction_failed}
    end
  rescue
    _ -> {:error, :extraction, :extraction_failed}
  end

  defp text(_, _), do: {:error, :extraction, :unsupported_format}

  defp valid_text?(text) when is_binary(text),
    do: String.valid?(text) and not String.contains?(text, <<0>>) and String.trim(text) != ""

  defp valid_text?(_), do: false

  defp save(material, text) do
    case Repo.transaction(
           fn ->
             Repo.insert_all(
               "feed_material_extractions",
               [
                 %{
                   material_id: Ecto.UUID.dump!(material.id),
                   text: text,
                   search_text: Normalizer.document_text(nil, text)
                 }
               ],
               log: false
             )

             key = identity_key(material)

             Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [key],
               log: false
             )

             previous =
               Repo.one(
                 from(r in "feed_material_revisions",
                   where: r.identity_key == ^key,
                   order_by: [desc: r.id],
                   limit: 1,
                   select: %{material_id: r.material_id, content_hash: r.content_hash}
                 )
               )

             revision_hash = revision_hash(material)

             if is_nil(previous) or previous.content_hash != revision_hash do
               Repo.insert_all(
                 "feed_material_revisions",
                 [
                   %{
                     material_id: Ecto.UUID.dump!(material.id),
                     identity_key: key,
                     content_hash: revision_hash,
                     previous_material_id: if(previous, do: previous.material_id, else: nil)
                   }
                 ],
                 log: false
               )
             end

             :ok
           end,
           mode: :savepoint
         ) do
      {:ok, :ok} -> :ok
      _ -> {:error, :indexing, :persistence_failed}
    end
  rescue
    _ -> {:error, :indexing, :persistence_failed}
  end

  defp revision_hash(%Material{kind: "html"} = material) do
    :crypto.hash(
      :sha256,
      :erlang.term_to_binary({material.content_hash, material.provenance}, [:deterministic])
    )
    |> Base.encode16(case: :lower)
  end

  defp revision_hash(material), do: material.content_hash

  defp identity_key(material) do
    metadata = Map.get(material.source_snapshot, "material_identity_policy", %{})
    uri = URI.parse(material.requested_url)
    ignored = metadata["material_identity_ignore_query_params"] || []
    ignore_fragment = metadata["material_identity_ignore_fragment"] || false

    unless is_list(ignored) and Enum.all?(ignored, &(is_binary(&1) and &1 != "")) and
             is_boolean(ignore_fragment),
           do: raise(ArgumentError, "invalid material identity policy")

    query =
      if is_binary(uri.query) and ignored != [] do
        parts = String.split(uri.query, "&")

        kept =
          Enum.reject(parts, fn part ->
            key = part |> String.split("=", parts: 2) |> hd() |> URI.decode_www_form()
            key in ignored
          end)

        if kept == [], do: nil, else: Enum.join(kept, "&")
      else
        uri.query
      end

    normalized =
      URI.to_string(%{
        uri
        | query: query,
          fragment: if(ignore_fragment, do: nil, else: uri.fragment)
      })

    :crypto.hash(:sha256, :erlang.term_to_binary({material.kind, normalized}))
    |> Base.encode16(case: :lower)
  end

  def rebuild(batch_size), do: rebuild_batches(nil, batch_size)

  defp rebuild_batches(cursor, size) do
    query =
      from(e in "feed_material_extractions",
        order_by: [asc: e.material_id],
        limit: ^size,
        select: %{id: e.material_id, text: e.text}
      )

    query = if cursor, do: where(query, [e], e.material_id > ^cursor), else: query

    case Repo.all(query) do
      [] ->
        :ok

      rows ->
        Enum.each(rows, fn row ->
          Repo.update_all(
            from(e in "feed_material_extractions",
              where: e.material_id == ^row.id and e.text == ^row.text
            ),
            [set: [search_text: Normalizer.document_text(nil, row.text)]],
            log: false
          )
        end)

        rebuild_batches(List.last(rows).id, size)
    end
  end

  def query(normalized_query, match? \\ true) do
    latest =
      from(r in "feed_material_revisions",
        distinct: r.identity_key,
        order_by: [asc: r.identity_key, desc: r.id],
        select: %{material_id: r.material_id}
      )

    from(e in "feed_material_extractions",
      join: r in subquery(latest),
      on: r.material_id == e.material_id,
      join: m in Material,
      on: m.id == e.material_id,
      where:
        not (^match?) or
          fragment(
            "?.search_vector @@ websearch_to_tsquery('simple', ?) OR ?.search_text ILIKE '%' || ? || '%' ESCAPE E'\\\\'",
            e,
            ^normalized_query,
            e,
            ^normalized_query
          ),
      select: %{
        id: m.id,
        title: fragment("?->>'title'", m.entry_snapshot),
        canonical_url: m.final_url,
        published_at: type(^nil, :utc_datetime_usec),
        excerpt: fragment("left(regexp_replace(?, '\\s+', ' ', 'g'), 300)", e.text),
        resource_type: "feed_material",
        original_id: m.original_id,
        extraction_id: type(^nil, :id),
        stale: false,
        search_mode:
          fragment("CASE WHEN ?.search_vector IS NULL THEN 'substring' ELSE 'full_text' END", e),
        title_match: 0,
        rank:
          fragment(
            "coalesce(ts_rank(?.search_vector, websearch_to_tsquery('simple', ?)), 0)",
            e,
            ^normalized_query
          )
      }
    )
  end
end
