defmodule LensWeb.SearchController do
  use LensWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Lens.{Content, Search}

  alias LensWeb.ApiSchemas.{
    DocumentProvenanceResponse,
    DocumentResponse,
    ErrorResponse,
    SearchResponse
  }

  alias OpenApiSpex.Schema

  tags(["Search"])

  operation :index,
    summary: "Search canonical documents",
    parameters: [
      q: [in: :query, required: true, schema: %Schema{type: :string, maxLength: 500}],
      limit: [in: :query, schema: %Schema{type: :integer, minimum: 1, maximum: 100}],
      offset: [in: :query, schema: %Schema{type: :integer, minimum: 0}]
    ],
    responses: [
      ok: {"Search results", "application/json", SearchResponse},
      unprocessable_entity: {"Invalid search parameters", "application/json", ErrorResponse}
    ]

  operation :show_document,
    summary: "Get canonical document content",
    parameters: [id: [in: :path, schema: %Schema{type: :string, format: :uuid}]],
    responses: [
      ok: {"Canonical document", "application/json", DocumentResponse},
      not_found: {"Document not found", "application/json", ErrorResponse}
    ]

  operation :show_provenance,
    summary: "Get paginated document observation provenance",
    parameters: [
      id: [in: :path, required: true, schema: %Schema{type: :string, format: :uuid}],
      limit: [in: :query, schema: %Schema{type: :integer, minimum: 1, maximum: 100}],
      offset: [in: :query, schema: %Schema{type: :integer, minimum: 0}]
    ],
    responses: [
      ok: {"Document observation provenance", "application/json", DocumentProvenanceResponse},
      not_found: {"Document not found", "application/json", ErrorResponse},
      unprocessable_entity: {"Invalid pagination parameters", "application/json", ErrorResponse}
    ]

  def index(conn, %{"q" => query} = params) do
    with {:ok, options} <- pagination(params), {:ok, results} <- Search.search(query, options) do
      json(conn, %{results: results})
    else
      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: to_string(reason)})
    end
  end

  def index(conn, _),
    do: conn |> put_status(:unprocessable_entity) |> json(%{error: "q is required"})

  def show_document(conn, %{"id" => id}) do
    case Content.fetch_document(id) do
      {:ok, document} ->
        sources = Content.document_sources(document)

        json(conn, %{
          document:
            Map.take(document, [
              :id,
              :title,
              :canonical_url,
              :content,
              :author,
              :published_at,
              :metadata
            ])
            |> Map.put(:sources, sources)
            |> Map.put(:provenance_url, "/api/documents/#{document.id}/provenance")
        })

      :error ->
        not_found(conn)
    end
  end

  def show_provenance(conn, %{"id" => id} = params) do
    with {:ok, document} <- Content.fetch_document(id),
         {:ok, options} <- pagination(params),
         {:ok, observations} <- Content.list_document_observations(document, options) do
      json(conn, %{
        observations: Enum.map(observations, &render_observation_provenance/1)
      })
    else
      :error ->
        not_found(conn)

      {:error, :invalid_pagination} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "invalid_pagination"})
    end
  end

  defp render_observation_provenance(obs) do
    %{
      id: obs.id,
      source_id: obs.source_id,
      observed_at: obs.observed_at,
      content_hash: obs.content_hash,
      entry_url: obs.entry_url,
      primary_source_url: obs.primary_source_url,
      feed_format: obs.feed_format || "unknown",
      acquisition_kind: obs.acquisition_kind || "unknown",
      publisher_authority: obs.publisher_authority || "unknown",
      acquisition_metadata_snapshot: obs.acquisition_metadata_snapshot || %{},
      reported_published_at: obs.reported_published_at
    }
  end

  defp pagination(params) do
    with {limit, ""} <- Integer.parse(Map.get(params, "limit", "20")),
         {offset, ""} <- Integer.parse(Map.get(params, "offset", "0")) do
      {:ok, [limit: limit, offset: offset]}
    else
      _ -> {:error, :invalid_pagination}
    end
  end

  defp not_found(conn), do: conn |> put_status(:not_found) |> json(%{error: "not_found"})
end
