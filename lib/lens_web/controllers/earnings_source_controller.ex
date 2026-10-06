defmodule LensWeb.EarningsSourceController do
  use LensWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Lens.Analysis
  alias Lens.Earnings.Sources
  alias OpenApiSpex.Schema

  alias LensWeb.ApiSchemas.{
    CreateEarningsSourceRequest,
    UpdateEarningsSourceRequest,
    EarningsSourceResponse,
    EarningsSourcesResponse,
    ErrorResponse,
    ValidationErrorsResponse
  }

  tags(["Earnings sources"])

  operation :index,
    summary: "List earnings sources for a target",
    parameters: [
      target_id: [in: :path, required: true, schema: %Schema{type: :string, format: :uuid}]
    ],
    responses: [
      ok: {"Sources", "application/json", EarningsSourcesResponse},
      not_found: {"Target not found", "application/json", ErrorResponse}
    ]

  operation :show,
    summary: "Inspect an earnings source",
    parameters: [
      target_id: [in: :path, required: true, schema: %Schema{type: :string, format: :uuid}],
      id: [in: :path, required: true, schema: %Schema{type: :string, format: :uuid}]
    ],
    responses: [
      ok: {"Source", "application/json", EarningsSourceResponse},
      not_found: {"Source not found", "application/json", ErrorResponse}
    ]

  operation :create,
    summary: "Register an earnings listing source",
    parameters: [
      target_id: [in: :path, required: true, schema: %Schema{type: :string, format: :uuid}]
    ],
    request_body: {"Source attributes", "application/json", CreateEarningsSourceRequest},
    responses: [
      created: {"Registered source", "application/json", EarningsSourceResponse},
      not_found: {"Target not found", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation errors", "application/json", ValidationErrorsResponse}
    ]

  operation :update,
    summary: "Change a source URL or enablement; omitted fields are preserved",
    parameters: [
      target_id: [in: :path, required: true, schema: %Schema{type: :string, format: :uuid}],
      id: [in: :path, required: true, schema: %Schema{type: :string, format: :uuid}]
    ],
    request_body: {"Source changes", "application/json", UpdateEarningsSourceRequest},
    responses: [
      ok: {"Updated source", "application/json", EarningsSourceResponse},
      not_found: {"Source not found", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation errors", "application/json", ValidationErrorsResponse}
    ]

  def index(conn, %{"target_id" => id}) do
    case Analysis.fetch_target(id) do
      {:ok, target} -> json(conn, %{sources: Enum.map(Sources.list(target.id), &source_json/1)})
      :error -> not_found(conn)
    end
  end

  def show(conn, %{"target_id" => target_id, "id" => id}) do
    case Sources.fetch(target_id, id) do
      {:ok, source} -> json(conn, %{source: source_json(source)})
      :error -> not_found(conn)
    end
  end

  def create(conn, %{"target_id" => id, "source" => attrs}) when is_map(attrs) do
    case Analysis.fetch_target(id) do
      {:ok, target} -> result(conn, Sources.create(target, attrs), :created)
      :error -> not_found(conn)
    end
  end

  def create(conn, _), do: invalid_attributes(conn)

  def update(conn, %{"target_id" => target_id, "id" => id, "source" => attrs})
      when is_map(attrs) do
    case Sources.fetch(target_id, id) do
      {:ok, source} -> result(conn, Sources.update(source, attrs), :ok)
      :error -> not_found(conn)
    end
  end

  def update(conn, _), do: invalid_attributes(conn)

  defp result(conn, {:ok, source}, status),
    do: conn |> put_status(status) |> json(%{source: source_json(source)})

  defp result(conn, {:error, changeset}, _) do
    errors = Ecto.Changeset.traverse_errors(changeset, fn {message, _} -> message end)
    conn |> put_status(:unprocessable_entity) |> json(%{errors: errors})
  end

  defp invalid_attributes(conn),
    do:
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{errors: %{source: ["must be an object"]}})

  defp not_found(conn), do: conn |> put_status(:not_found) |> json(%{error: "not_found"})
  defp source_json(source), do: Map.take(source, [:id, :target_id, :listing_url, :enabled])
end
