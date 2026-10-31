defmodule Lens.Ingestion do
  require Logger

  alias Lens.Content
  alias Lens.Content.Source
  alias Lens.Ingestion.{EarningsUpdates, Fetcher, Materials, Parser, Result}
  alias Lens.ErrorReporter

  @default_max_entries 1_000

  @type source_id :: binary()
  @type options :: keyword()

  @spec ingest(Source.t() | source_id(), options()) :: Result.t()
  def ingest(source_or_id, options \\ [])

  def ingest(source_id, options) when is_binary(source_id) do
    source_id
    |> Content.get_source!()
    |> ingest(options)
  end

  def ingest(%Source{} = source, options) do
    source = Content.get_source!(source.id)
    safely_ingest(source, options)
  end

  defp safely_ingest(source, options) do
    do_ingest(source, options)
  rescue
    error ->
      if source.ingestion_mode == "earnings_updates" do
        try do
          update_failure(source, error, DateTime.utc_now())
        rescue
          _ -> ErrorReporter.report(:discovery, error)
        end

        %Result{
          outcome: :failure,
          error: "earnings discovery failed",
          valid_entries: [],
          invalid_entries: []
        }
      else
        reraise error, __STACKTRACE__
      end
  end

  defp do_ingest(source, options) do
    attempted_at = DateTime.utc_now()
    started_at = System.monotonic_time()

    result =
      case Fetcher.fetch(request_source(source), options) do
        {:not_modified, _headers}
        when source.ingestion_mode == "earnings_updates" and is_nil(source.feed_baselined_at) ->
          update_failure(source, "baseline requires a complete feed", attempted_at)

          %Result{
            outcome: :failure,
            error: "baseline requires a complete feed",
            valid_entries: [],
            invalid_entries: []
          }

        {:not_modified, headers} ->
          update_success(source, headers, attempted_at)
          %Result{outcome: :not_modified, status: 304, valid_entries: [], invalid_entries: []}

        {:ok, response} ->
          ingest_response(source, response, attempted_at, options)

        {:error, error, headers} ->
          update_failure(source, error, attempted_at)

          %Result{
            outcome: :failure,
            valid_entries: [],
            invalid_entries: [],
            error: error,
            retry_after_seconds: retry_after_seconds(headers)
          }
      end

    Logger.info("source ingestion completed",
      source_id: source.id,
      outcome: result.outcome,
      duration_ms: elapsed_ms(started_at),
      valid_entries: length(result.valid_entries),
      invalid_entries: length(result.invalid_entries)
    )

    result
  end

  defp ingest_response(source, response, attempted_at, options) do
    with {:ok, entries} <- Parser.parse(response.body, source.endpoint_url),
         {:ok, entries} <-
           limit_entries(entries, Keyword.get(options, :max_entries, @default_max_entries)) do
      persist_response(source, entries, response, attempted_at, options)
    else
      {:error, error} ->
        update_failure(source, error, attempted_at)

        %Result{
          outcome: :failure,
          status: response.status,
          valid_entries: [],
          invalid_entries: [],
          error: error
        }
    end
  end

  defp persist_response(
         %Source{ingestion_mode: "earnings_updates"} = source,
         entries,
         response,
         attempted_at,
         options
       ) do
    case EarningsUpdates.observe(source, entries, response.headers, attempted_at) do
      {:ok, %{signals: signals, invalid_entries: invalid}} ->
        Enum.each(signals, fn signal ->
          Phoenix.PubSub.broadcast(
            Lens.PubSub,
            "earnings_feed_updates",
            {:earnings_feed_update, signal}
          )
        end)

        acquired = Materials.acquire_many(signals, Keyword.get(options, :materials, []))

        indexing_errors =
          Lens.Ingestion.MaterialIndex.index_many(
            acquired.materials,
            Keyword.get(options, :materials, [])
          )

        Enum.each(acquired.materials, fn material ->
          Phoenix.PubSub.broadcast(
            Lens.PubSub,
            "earnings_materials",
            {:earnings_material_acquired, material}
          )
        end)

        %Result{
          outcome: :success,
          status: response.status,
          valid_entries: [],
          invalid_entries: invalid,
          update_signals: signals,
          materials: acquired.materials,
          material_errors: acquired.errors ++ indexing_errors
        }

      {:error, error} ->
        update_failure(source, error, attempted_at)

        %Result{
          outcome: :failure,
          error: "earnings discovery failed",
          valid_entries: [],
          invalid_entries: []
        }
    end
  end

  defp persist_response(source, entries, response, attempted_at, _options) do
    {valid_entries, invalid_entries} = persist_entries(source, entries, response, attempted_at)
    update_success(source, response.headers, attempted_at)

    %Result{
      outcome: :success,
      status: response.status,
      valid_entries: valid_entries,
      invalid_entries: invalid_entries
    }
  end

  defp persist_entries(source, entries, response, observed_at) do
    fetch_metadata = %{"status" => response.status, "bytes" => byte_size(response.body)}

    entries
    |> Enum.with_index()
    |> Enum.reduce({[], []}, fn {entry, index}, {valid, invalid} ->
      case entry_for_persistence(entry) do
        {:ok, entry} ->
          case Content.observe_document(source, entry,
                 observed_at: DateTime.add(observed_at, index, :microsecond),
                 fetch_metadata: fetch_metadata
               ) do
            {:ok, observation} -> {[observation | valid], invalid}
            {:error, changeset} -> {valid, [%{index: index, error: errors(changeset)} | invalid]}
          end

        {:error, error} ->
          {valid, [%{index: index, error: error} | invalid]}
      end
    end)
    |> then(fn {valid, invalid} -> {Enum.reverse(valid), Enum.reverse(invalid)} end)
  end

  defp entry_for_persistence(entry) do
    content = entry.content || entry.title

    if is_binary(content) and content != "" do
      {:ok, Map.put(entry, :content, content)}
    else
      {:error, "entry has no title or content"}
    end
  end

  defp limit_entries(entries, max_entries) when length(entries) <= max_entries, do: {:ok, entries}
  defp limit_entries(_entries, _max_entries), do: {:error, "feed exceeds entry limit"}

  defp update_success(source, headers, attempted_at) do
    source = Content.get_source!(source.id)

    Content.update_source(source, %{
      etag: Map.get(headers, "etag", source.etag),
      last_modified: Map.get(headers, "last-modified", source.last_modified),
      last_attempt_at: attempted_at,
      last_success_at: attempted_at,
      last_error: nil,
      failure_count: 0
    })
  end

  defp update_failure(source, error, attempted_at) do
    source = Content.get_source!(source.id)
    if source.ingestion_mode == "earnings_updates", do: ErrorReporter.report(:discovery, error)

    Content.update_source(source, %{
      last_attempt_at: attempted_at,
      last_error: if(source.ingestion_mode == "earnings_updates", do: nil, else: error),
      failure_count: source.failure_count + 1
    })
  end

  defp request_source(
         %Source{ingestion_mode: "earnings_updates", feed_baselined_at: nil} = source
       ),
       do: %{source | etag: nil, last_modified: nil}

  defp request_source(source), do: source

  defp errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, _options} -> message end)
  end

  defp elapsed_ms(started_at) do
    System.monotonic_time()
    |> Kernel.-(started_at)
    |> System.convert_time_unit(:native, :millisecond)
  end

  defp retry_after_seconds(headers) do
    case Integer.parse(to_string(Map.get(headers, "retry-after", ""))) do
      {seconds, ""} when seconds >= 0 -> min(seconds, 3_600)
      _ -> nil
    end
  end
end
