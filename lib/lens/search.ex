defmodule Lens.Search do
  import Ecto.Query

  alias Lens.Content.Document
  alias Lens.Repo

  @max_query_length 500
  @max_limit 100
  @default_rebuild_batch_size 1_000

  @type result :: %{
          id: binary(),
          title: String.t() | nil,
          canonical_url: String.t() | nil,
          published_at: DateTime.t() | nil,
          excerpt: String.t()
        }

  @spec search(String.t(), keyword()) ::
          {:ok, [result()]} | {:error, :invalid_query | :invalid_pagination}
  def search(query, options \\ [])

  def search(query, options) when is_binary(query) do
    limit = Keyword.get(options, :limit, 20)
    offset = Keyword.get(options, :offset, 0)

    with true <- valid_query?(query), true <- valid_pagination?(limit, offset) do
      documents =
        from(document in Document,
          where: fragment("search_vector @@ websearch_to_tsquery('simple', ?)", ^query),
          order_by: [
            desc: fragment("ts_rank(search_vector, websearch_to_tsquery('simple', ?))", ^query),
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

      {:ok, documents}
    else
      false -> {:error, :invalid_query}
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

  defp valid_query?(query),
    do: String.trim(query) != "" and String.length(query) <= @max_query_length

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
        from(document in Document,
          where: document.id in ^document_ids,
          update: [set: [content: fragment("content")]]
        )
        |> Repo.update_all([])

        rebuild_batches(List.last(document_ids), batch_size)
    end
  end

  defp after_document(query, nil), do: query

  defp after_document(query, document_id),
    do: where(query, [document], document.id > ^document_id)
end
