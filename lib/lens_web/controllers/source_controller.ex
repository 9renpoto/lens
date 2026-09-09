defmodule LensWeb.SourceController do
  use LensWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Lens.Content
  alias OpenApiSpex.Schema

  alias LensWeb.ApiSchemas.{
    CreateSourceRequest,
    SourceResponse,
    SourcesResponse,
    UpdateSourceRequest,
    ValidationErrorsResponse
  }

  tags(["Sources"])

  operation :index,
    summary: "List configured sources",
    responses: [ok: {"Configured sources", "application/json", SourcesResponse}]

  operation :show,
    summary: "Get a source",
    parameters: [id: [in: :path, schema: %Schema{type: :string, format: :uuid}]],
    responses: [ok: {"Configured source", "application/json", SourceResponse}]

  operation :create,
    summary: "Create a source",
    request_body: {"Source configuration", "application/json", CreateSourceRequest},
    responses: [
      created: {"Created source", "application/json", SourceResponse},
      unprocessable_entity: {"Validation errors", "application/json", ValidationErrorsResponse}
    ]

  operation :update,
    summary: "Update a source",
    parameters: [id: [in: :path, schema: %Schema{type: :string, format: :uuid}]],
    request_body: {"Source changes", "application/json", UpdateSourceRequest},
    responses: [
      ok: {"Updated source", "application/json", SourceResponse},
      unprocessable_entity: {"Validation errors", "application/json", ValidationErrorsResponse}
    ]

  operation :replace,
    summary: "Replace a source configuration",
    parameters: [id: [in: :path, schema: %Schema{type: :string, format: :uuid}]],
    request_body: {"Source configuration", "application/json", UpdateSourceRequest},
    responses: [
      ok: {"Updated source", "application/json", SourceResponse},
      unprocessable_entity: {"Validation errors", "application/json", ValidationErrorsResponse}
    ]

  def index(conn, _params),
    do: json(conn, %{sources: Enum.map(Content.list_sources(), &source_json/1)})

  def show(conn, %{"id" => id}), do: json(conn, %{source: source_json(Content.get_source!(id))})

  def create(conn, %{"source" => attrs}) do
    case Content.create_source(attrs) do
      {:ok, source} -> conn |> put_status(:created) |> json(%{source: source_json(source)})
      {:error, changeset} -> validation_error(conn, changeset)
    end
  end

  def update(conn, %{"id" => id, "source" => attrs}) do
    case Content.update_source(Content.get_source!(id), attrs) do
      {:ok, source} -> json(conn, %{source: source_json(source)})
      {:error, changeset} -> validation_error(conn, changeset)
    end
  end

  def replace(conn, params), do: update(conn, params)

  defp validation_error(conn, changeset) do
    conn |> put_status(:unprocessable_entity) |> json(%{errors: errors(changeset)})
  end

  defp source_json(source) do
    Map.take(source, [
      :id,
      :source_type,
      :endpoint_url,
      :title,
      :enabled,
      :poll_interval_seconds,
      :next_fetch_at,
      :last_attempt_at,
      :last_success_at,
      :last_error,
      :failure_count
    ])
  end

  defp errors(changeset),
    do: Ecto.Changeset.traverse_errors(changeset, fn {message, _} -> message end)
end
