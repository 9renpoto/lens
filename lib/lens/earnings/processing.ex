defmodule Lens.Earnings.Processing do
  @moduledoc "Derive text from PostgreSQL originals without invoking acquisition."
  alias Lens.Earnings.{Extractions, Extraction, Original, PDFExtractor}
  alias Lens.Repo
  import Ecto.Query

  def retry_failed(original_id, options \\ []) do
    allocate_and_process(original_id, options, true)
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
      results = Enum.map(ids, fn id -> {id, extract_summary(id, options)} end)
      {:ok, %{results: results, next_after: List.last(ids)}}
    else
      {:error, :invalid_options}
    end
  end

  defp valid_cursor?(nil), do: true
  defp valid_cursor?(id), do: match?({:ok, _}, Ecto.UUID.cast(id))

  def extract(original_id, options \\ []) do
    allocate_and_process(original_id, options, false)
  end

  defp valid_bounds?(options) do
    timeout = Keyword.get(options, :timeout_ms, 20_000)
    output = Keyword.get(options, :max_output_bytes, 8_388_608)

    is_integer(timeout) and timeout in 1..30_000 and
      is_integer(output) and output in 1..8_388_608
  end

  defp allocate_and_process(original_id, options, retry?) do
    with {:ok, id} <- Ecto.UUID.cast(original_id),
         true <- valid_bounds?(options),
         {:ok, attempt} <- allocate_attempt(id, options, retry?) do
      case Lens.Earnings.original_bytes(id, Keyword.take(options, [:rustfs])) do
        {:ok, bytes} -> process(bytes, attempt, options)
        {:error, reason} -> Extractions.fail(attempt.id, failure_name(reason))
        :error -> Extractions.fail(attempt.id, "original_unavailable")
      end
    else
      :error -> {:error, :not_found}
      false -> {:error, :invalid_options}
      {:error, reason} -> {:error, reason}
    end
  end

  defp allocate_attempt(original_id, options, retry?) do
    Repo.transaction(fn ->
      original =
        Repo.one(from(o in Original, where: o.id == ^original_id, lock: "FOR UPDATE"))

      if is_nil(original), do: Repo.rollback(:not_found)

      if retry? do
        latest =
          Repo.one(
            from(e in Extraction,
              where: e.original_id == ^original_id,
              order_by: [desc: e.id],
              limit: 1
            )
          )

        unless latest && latest.status == "failed", do: Repo.rollback(:not_failed)
      end

      extractor = Keyword.get(options, :extractor, PDFExtractor)

      case Extractions.begin(
             original_id,
             inspect(extractor),
             "unavailable",
             effective_bounds(options)
           ) do
        {:ok, attempt} -> attempt
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp failure_name(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp failure_name({:http_error, status}) when is_integer(status), do: "http_#{status}"
  defp failure_name(_), do: "original_unavailable"

  defp process(bytes, attempt, options) do
    extractor = Keyword.get(options, :extractor, PDFExtractor)

    case extractor.extract(bytes, options) do
      {:ok, %{text: text, version: version}} ->
        case Extractions.succeed(attempt.id, text, extractor_version: version) do
          {:error, :invalid_text} ->
            Extractions.fail(attempt.id, "invalid_text", extractor_version: version)

          result ->
            result
        end

      {:error, %{reason: reason, version: version}} ->
        Extractions.fail(attempt.id, reason, extractor_version: version)
    end
  end

  defp effective_bounds(options) do
    %{
      "timeout_ms" => Keyword.get(options, :timeout_ms, 20_000),
      "max_output_bytes" => Keyword.get(options, :max_output_bytes, 8_388_608)
    }
  end

  defp extract_summary(original_id, options) do
    case extract(original_id, options) do
      {:ok, extraction} ->
        {:ok,
         Map.take(extraction, [
           :id,
           :original_id,
           :status,
           :failure_reason,
           :extractor_version,
           :extraction_options
         ])}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
