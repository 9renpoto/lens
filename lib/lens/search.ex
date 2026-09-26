defmodule Lens.Search do
  import Ecto.Query

  alias Lens.Content.Document
  alias Lens.Repo
  alias Lens.Search.Normalizer

  @max_query_length 500
  @max_limit 100
  @default_rebuild_batch_size 1_000

  @type result :: %{
          id: binary(),
          title: String.t() | nil,
          canonical_url: String.t() | nil,
          published_at: DateTime.t() | nil,
          excerpt: String.t(),
          provenance_url: String.t()
        }

  @spec search(String.t(), keyword()) ::
          {:ok, [result()]} | {:error, :invalid_query | :invalid_pagination}
  def search(query, options \\ [])

  def search(query, options) when is_binary(query) do
    limit = Keyword.get(options, :limit, 20)
    offset = Keyword.get(options, :offset, 0)

    with {:ok, normalized_query} <- valid_query?(query),
         true <- valid_pagination?(limit, offset) do
      documents =
        from(document in Document,
          where:
            fragment(
              "search_vector @@ websearch_to_tsquery('simple', ?) OR search_text ILIKE '%' || ? || '%' ESCAPE E'\\\\'",
              ^normalized_query,
              ^normalized_query
            ),
          order_by: [
            desc:
              fragment(
                "CASE WHEN search_title ILIKE '%' || ? || '%' ESCAPE E'\\\\' THEN 1 ELSE 0 END",
                ^normalized_query
              ),
            desc:
              fragment(
                "ts_rank(search_vector, websearch_to_tsquery('simple', ?))",
                ^normalized_query
              ),
            asc: document.id
          ],
          limit: ^limit,
          offset: ^offset,
          select: %{
            id: document.id,
            title: document.title,
            canonical_url: document.canonical_url,
            published_at: document.published_at,
            excerpt: fragment("left(regexp_replace(content, '\\s+', ' ', 'g'), 300)")
          }
        )
        |> Repo.all()

      results =
        Enum.map(documents, fn doc ->
          Map.put(doc, :provenance_url, "/api/documents/#{doc.id}/provenance")
        end)

      {:ok, results}
    else
      :error -> {:error, :invalid_query}
      :invalid_pagination -> {:error, :invalid_pagination}
    end
  end

  def search(_, _), do: {:error, :invalid_query}

  @spec rebuild(keyword()) :: :ok | {:error, :invalid_batch_size}
  def rebuild(options \\ []) do
    batch_size = Keyword.get(options, :batch_size, @default_rebuild_batch_size)

    if is_integer(batch_size) and batch_size > 0 do
      rebuild_batches(nil, batch_size)
    else
      {:error, :invalid_batch_size}
    end
  end

  defp valid_query?(query) do
    if String.length(query) <= @max_query_length,
      do: Normalizer.normalize_query(query),
      else: :error
  end

  defp valid_pagination?(limit, offset)
       when is_integer(limit) and is_integer(offset) and limit > 0 and limit <= @max_limit and
              offset >= 0,
       do: true

  defp valid_pagination?(_, _), do: :invalid_pagination

  defp rebuild_batches(last_id, batch_size) do
    document_ids =
      Document
      |> order_by([document], asc: document.id)
      |> limit(^batch_size)
      |> select([document], document.id)
      |> after_document(last_id)
      |> Repo.all()

    case document_ids do
      [] ->
        :ok

      _ ->
        documents = Repo.all(from(document in Document, where: document.id in ^document_ids))

        Enum.each(documents, fn document ->
          Repo.update_all(
            from(current in Document, where: current.id == ^document.id),
            set: [
              search_text: Normalizer.document_text(document.title, document.content),
              search_title: Normalizer.title_text(document.title)
            ]
          )
        end)

        rebuild_batches(List.last(document_ids), batch_size)
    end
  end

  defp after_document(query, nil), do: query

  defp after_document(query, document_id),
    do: where(query, [document], document.id > ^document_id)
end
