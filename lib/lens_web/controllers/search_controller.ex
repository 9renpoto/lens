defmodule LensWeb.SearchController do
  use LensWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Lens.{Content, Search}
  alias LensWeb.ApiSchemas.{DocumentResponse, ErrorResponse, SearchResponse}
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
        })

      :error ->
        not_found(conn)
    end
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
