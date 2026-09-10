defmodule Lens.Content do
  import Ecto.Query

  alias Lens.Content.{Document, Identity, Observation, Source}
  alias Lens.Repo

  @type attributes :: %{optional(atom() | String.t()) => term()}
  @type source_id :: binary()
  @type observation_result ::
          {:ok, %{document: Document.t(), observation: Observation.t()}}
          | {:error, %Ecto.Changeset{}}
  @default_source_run_ttl_seconds 300
  @max_retry_after_seconds 3_600

  @spec list_sources() :: [Source.t()]
  def list_sources, do: Repo.all(from(source in Source, order_by: [asc: source.inserted_at]))

  @spec get_source!(source_id()) :: Source.t()
  def get_source!(id), do: Repo.get!(Source, id)

  @spec fetch_source(source_id()) :: {:ok, Source.t()} | :error
  def fetch_source(id), do: fetch(Source, id)

  @spec create_source(attributes()) :: {:ok, Source.t()} | {:error, %Ecto.Changeset{}}
  def create_source(attrs) do
    attrs = schedule_initial_fetch(attrs)

    %Source{}
    |> Source.changeset(attrs)
    |> Repo.insert()
  end

  @spec update_source(Source.t(), attributes()) :: {:ok, Source.t()} | {:error, %Ecto.Changeset{}}
  def update_source(%Source{} = source, attrs) do
    source
    |> Source.changeset(clear_validators_for_changed_endpoint(source, attrs))
    |> Repo.update()
  end

  @spec change_source(Source.t(), attributes()) :: %Ecto.Changeset{}
  def change_source(%Source{} = source, attrs \\ %{}), do: Source.changeset(source, attrs)

  @spec get_document!(binary()) :: Document.t()
  def get_document!(id), do: Repo.get!(Document, id)

  @spec fetch_document(binary()) :: {:ok, Document.t()} | :error
  def fetch_document(id), do: fetch(Document, id)

  @spec list_observations(Document.t()) :: [Observation.t()]
  def list_observations(%Document{id: document_id}) do
    Repo.all(
      from(observation in Observation,
        where: observation.document_id == ^document_id,
        order_by: [desc: observation.observed_at]
      )
    )
  end

  @spec document_sources(Document.t()) :: [map()]
  def document_sources(%Document{id: document_id}) do
    Repo.all(
      from(observation in Observation,
        join: source in Source,
        on: source.id == observation.source_id,
        where: observation.document_id == ^document_id,
        distinct: observation.source_id,
        order_by: [asc: observation.source_id, desc: observation.observed_at],
        select: %{
          id: source.id,
          source_type: source.source_type,
          endpoint_url: source.endpoint_url,
          observed_at: observation.observed_at
        }
      )
    )
  end

  @spec claim_due_sources(DateTime.t(), non_neg_integer(), keyword()) :: [source_id()]
  def claim_due_sources(now, limit, options \\ [])

  def claim_due_sources(now, limit, options) when limit > 0 do
    release_expired_source_runs(
      now,
      Keyword.get(options, :lock_ttl_seconds, @default_source_run_ttl_seconds)
    )

    from(source in Source,
      where: source.enabled and not is_nil(source.next_fetch_at) and source.next_fetch_at <= ^now,
      order_by: [asc: source.next_fetch_at],
      limit: ^limit,
      select: source.id
    )
    |> Repo.all()
    |> Enum.filter(fn source_id ->
      {count, _} =
        Repo.insert_all("source_runs", [%{source_id: Ecto.UUID.dump!(source_id), locked_at: now}],
          on_conflict: :nothing
        )

      count == 1
    end)
  end

  def claim_due_sources(_now, _limit, _options), do: []

  @spec release_source_run(source_id()) :: {non_neg_integer(), nil | [term()]}
  def release_source_run(source_id) do
    source_id = Ecto.UUID.dump!(source_id)
    Repo.delete_all(from(run in "source_runs", where: run.source_id == ^source_id))
  end

  @spec schedule_next_fetch(source_id(), Lens.Ingestion.Result.t(), DateTime.t(), keyword()) ::
          {:ok, Source.t()} | {:error, %Ecto.Changeset{}}
  def schedule_next_fetch(source_id, result, now, options \\ []) do
    source = get_source!(source_id)

    seconds =
      case result.outcome do
        outcome when outcome in [:success, :not_modified] ->
          source.poll_interval_seconds

        :failure ->
          failure_delay(source, result, options)
      end

    update_source(source, %{next_fetch_at: DateTime.add(now, seconds, :second)})
  end

  @spec observe_document(Source.t() | source_id(), attributes(), keyword()) ::
          observation_result()
  def observe_document(source_or_id, attrs, options \\ [])

  def observe_document(%Source{} = source, attrs, options) do
    observe_document_from_source(source, attrs, options)
  end

  def observe_document(source_id, attrs, options) when is_binary(source_id) and is_map(attrs) do
    source_id
    |> source_for_observation()
    |> observe_document_from_source(attrs, options)
  end

  defp observe_document_from_source(%Source{} = source, attrs, options) do
    observed_at = Keyword.get(options, :observed_at, DateTime.utc_now())
    fetch_metadata = Keyword.get(options, :fetch_metadata, %{})

    Repo.transaction(fn ->
      entry = Identity.normalize_entry(source.id, attrs)
      document = upsert_document(entry)

      observation =
        %Observation{}
        |> Observation.changeset(
          Map.merge(
            %{
              source_id: source.id,
              document_id: document.id,
              observed_at: observed_at,
              content_hash: entry.content_hash,
              fetch_metadata: fetch_metadata
            },
            observation_provenance(source, entry)
          )
        )
        |> insert_or_rollback()

      %{document: document, observation: observation}
    end)
  end

  defp observation_provenance(source, entry) do
    %{
      entry_url: entry.canonical_url,
      primary_source_url: source.original_feed_url,
      feed_format: source.feed_format || "unknown",
      acquisition_kind: source.acquisition_kind || "unknown",
      publisher_authority: source.publisher_authority || "unknown",
      acquisition_metadata_snapshot: source.acquisition_metadata || %{},
      reported_published_at: entry.published_at
    }
  end

  defp source_for_observation(source_id) do
    Repo.get(Source, source_id) || %Source{id: source_id}
  end

  defp upsert_document(entry) do
    document_changeset = Document.changeset(%Document{}, entry)

    document =
      case Repo.insert(document_changeset, on_conflict: :nothing, conflict_target: :identity_key) do
        {:ok, _document} -> Repo.get_by!(Document, identity_key: entry.identity_key)
        {:error, changeset} -> Repo.rollback(changeset)
      end

    document
    |> Document.changeset(document_update_attributes(document, entry))
    |> update_or_rollback()
  end

  defp document_update_attributes(document, entry) do
    %{
      canonical_url: entry.canonical_url || document.canonical_url,
      title: entry.title || document.title,
      content: entry.content,
      author: entry.author || document.author,
      published_at: entry.published_at || document.published_at,
      metadata: Map.merge(document.metadata || %{}, entry.metadata),
      content_hash: entry.content_hash
    }
  end

  defp insert_or_rollback(changeset) do
    case Repo.insert(changeset) do
      {:ok, value} -> value
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp update_or_rollback(changeset) do
    case Repo.update(changeset) do
      {:ok, value} -> value
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp clear_validators_for_changed_endpoint(source, attrs) do
    endpoint_url = Map.get(attrs, :endpoint_url, Map.get(attrs, "endpoint_url"))

    if is_binary(endpoint_url) and endpoint_url != source.endpoint_url do
      Map.merge(Map.new(attrs), %{
        etag: nil,
        last_modified: nil,
        last_success_at: nil,
        last_error: nil,
        failure_count: 0,
        next_fetch_at: DateTime.utc_now()
      })
    else
      attrs
    end
  end

  defp schedule_initial_fetch(attrs) do
    if Map.has_key?(attrs, :next_fetch_at) or Map.has_key?(attrs, "next_fetch_at") do
      attrs
    else
      Map.put(attrs, next_fetch_key(attrs), DateTime.utc_now())
    end
  end

  defp next_fetch_key(attrs) do
    if Enum.all?(Map.keys(attrs), &is_binary/1), do: "next_fetch_at", else: :next_fetch_at
  end

  defp fetch(schema, id) when is_binary(id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         record when not is_nil(record) <- Repo.get(schema, id) do
      {:ok, record}
    else
      _ -> :error
    end
  end

  defp release_expired_source_runs(now, ttl_seconds)
       when is_integer(ttl_seconds) and ttl_seconds > 0 do
    expires_at = DateTime.add(now, -ttl_seconds, :second)
    Repo.delete_all(from(run in "source_runs", where: run.locked_at <= ^expires_at))
  end

  defp release_expired_source_runs(_now, _ttl_seconds), do: :ok

  defp failure_delay(_source, %{retry_after_seconds: seconds}, _options)
       when is_integer(seconds) and seconds >= 0,
       do: min(seconds, @max_retry_after_seconds)

  defp failure_delay(source, _result, options) do
    seconds =
      min(
        source.poll_interval_seconds * trunc(:math.pow(2, min(source.failure_count, 6))),
        @max_retry_after_seconds
      )

    options
    |> Keyword.get(:jitter, &jitter/1)
    |> then(& &1.(seconds))
    |> trunc()
    |> max(0)
    |> min(@max_retry_after_seconds)
  end

  defp jitter(seconds), do: seconds * (0.8 + :rand.uniform() * 0.4)
end
