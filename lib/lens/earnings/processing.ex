defmodule Lens.Earnings.Processing do
  @moduledoc "Derive text from PostgreSQL originals without invoking acquisition."
  alias Lens.Earnings
  alias Lens.Earnings.{Extractions, PDFExtractor}
  alias Lens.Earnings.Extraction
  alias Lens.Repo
  import Ecto.Query

  def retry_failed(original_id, options \\ []) do
    with {:ok, id} <- Ecto.UUID.cast(original_id) do
      latest =
        Repo.one(
          from(e in Extraction, where: e.original_id == ^id, order_by: [desc: e.id], limit: 1)
        )

      if latest && latest.status == "failed",
        do: extract(id, options),
        else: {:error, :not_failed}
    else
      :error -> {:error, :not_found}
    end
  end

  def regenerate(options) do
    limit = Keyword.get(options, :limit)
    cursor = Keyword.get(options, :after_original)

    if is_integer(limit) and limit in 1..100 and valid_cursor?(cursor) and valid_bounds?(options) do
      query =
        from(e in Extraction,
          where: e.status in ["succeeded", "failed"],
          distinct: true,
          order_by: [asc: e.original_id],
          select: e.original_id,
          limit: ^limit
        )

      query = if cursor, do: where(query, [e], e.original_id > ^cursor), else: query
      ids = Repo.all(query)
      results = Enum.map(ids, fn id -> {id, extract(id, options)} end)
      {:ok, %{results: results, next_after: List.last(ids)}}
    else
      {:error, :invalid_options}
    end
  end

  defp valid_cursor?(nil), do: true
  defp valid_cursor?(id), do: match?({:ok, _}, Ecto.UUID.cast(id))

  def extract(original_id, options \\ []) do
    if valid_bounds?(options) do
      process(original_id, options)
    else
      {:error, :invalid_options}
    end
  end

  defp valid_bounds?(options) do
    timeout = Keyword.get(options, :timeout_ms, 20_000)
    output = Keyword.get(options, :max_output_bytes, 8_388_608)

    is_integer(timeout) and timeout in 1..30_000 and
      is_integer(output) and output in 1..8_388_608
  end

  defp process(original_id, options) do
    extractor = Keyword.get(options, :extractor, PDFExtractor)

    with {:ok, bytes} <- retained_bytes(original_id),
         {:ok, attempt} <-
           Extractions.begin(
             original_id,
             inspect(extractor),
             "unavailable",
             effective_bounds(options)
           ) do
      case extractor.extract(bytes, options) do
        {:ok, %{text: text, version: version}} ->
          case Extractions.succeed(attempt.id, text, extractor_version: version) do
            {:error, :invalid_text} -> Extractions.fail(attempt.id, "invalid_text")
            result -> result
          end

        {:error, %{reason: reason, version: version}} ->
          Extractions.fail(attempt.id, reason, extractor_version: version)
      end
    end
  end

  defp effective_bounds(options) do
    %{
      "timeout_ms" => Keyword.get(options, :timeout_ms, 20_000),
      "max_output_bytes" => Keyword.get(options, :max_output_bytes, 8_388_608)
    }
  end

  defp retained_bytes(id) do
    case Earnings.original_bytes(id) do
      {:ok, bytes} -> {:ok, bytes}
      :error -> {:error, :not_found}
    end
  end
end
