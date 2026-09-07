defmodule Lens.Ingestion do
  alias Lens.Content
  alias Lens.Content.Source
  alias Lens.Ingestion.{Fetcher, Parser, Result}

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
    attempted_at = DateTime.utc_now()

    case Fetcher.fetch(source, options) do
      {:not_modified, headers} ->
        update_success(source, headers, attempted_at)
        %Result{outcome: :not_modified, status: 304, valid_entries: [], invalid_entries: []}

      {:ok, response} ->
        ingest_response(source, response, attempted_at, options)

      {:error, error} ->
        update_failure(source, error, attempted_at)
        %Result{outcome: :failure, valid_entries: [], invalid_entries: [], error: error}
    end
  end

  defp ingest_response(source, response, attempted_at, options) do
    with {:ok, entries} <- Parser.parse(response.body, source.endpoint_url),
         {:ok, entries} <-
           limit_entries(entries, Keyword.get(options, :max_entries, @default_max_entries)) do
      {valid_entries, invalid_entries} = persist_entries(source, entries, response, attempted_at)
      update_success(source, response.headers, attempted_at)

      %Result{
        outcome: :success,
        status: response.status,
        valid_entries: valid_entries,
        invalid_entries: invalid_entries
      }
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

    Content.update_source(source, %{
      last_attempt_at: attempted_at,
      last_error: error,
      failure_count: source.failure_count + 1
    })
  end

  defp errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, _options} -> message end)
  end
end
