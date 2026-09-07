defmodule Lens.Content do
  import Ecto.Query

  alias Lens.Content.{Document, Identity, Observation, Source}
  alias Lens.Repo

  def list_sources, do: Repo.all(from(source in Source, order_by: [asc: source.inserted_at]))

  def get_source!(id), do: Repo.get!(Source, id)

  def create_source(attrs) do
    %Source{}
    |> Source.changeset(attrs)
    |> Repo.insert()
  end

  def update_source(%Source{} = source, attrs) do
    source
    |> Source.changeset(attrs)
    |> Repo.update()
  end

  def change_source(%Source{} = source, attrs \\ %{}), do: Source.changeset(source, attrs)

  def get_document!(id), do: Repo.get!(Document, id)

  def list_observations(%Document{id: document_id}) do
    Repo.all(
      from(observation in Observation,
        where: observation.document_id == ^document_id,
        order_by: [desc: observation.observed_at]
      )
    )
  end

  def observe_document(source_or_id, attrs, options \\ [])

  def observe_document(%Source{id: source_id}, attrs, options) do
    observe_document(source_id, attrs, options)
  end

  def observe_document(source_id, attrs, options) when is_binary(source_id) and is_map(attrs) do
    observed_at = Keyword.get(options, :observed_at, DateTime.utc_now())
    fetch_metadata = Keyword.get(options, :fetch_metadata, %{})

    Repo.transaction(fn ->
      entry = Identity.normalize_entry(source_id, attrs)
      document = upsert_document(entry)

      observation =
        %Observation{}
        |> Observation.changeset(%{
          source_id: source_id,
          document_id: document.id,
          observed_at: observed_at,
          content_hash: entry.content_hash,
          fetch_metadata: fetch_metadata
        })
        |> insert_or_rollback()

      %{document: document, observation: observation}
    end)
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
end
