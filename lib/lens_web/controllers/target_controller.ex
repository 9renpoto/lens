defmodule LensWeb.TargetController do
  use LensWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Lens.Analysis
  alias OpenApiSpex.Schema

  alias LensWeb.ApiSchemas.{
    CreateTargetRequest,
    ErrorResponse,
    TargetResponse,
    TargetsResponse,
    UpdateTargetRequest,
    ValidationErrorsResponse
  }

  tags(["Targets"])

  operation :index,
    summary: "List analysis targets",
    responses: [ok: {"Analysis targets", "application/json", TargetsResponse}]

  operation :show,
    summary: "Get an analysis target",
    parameters: [id: [in: :path, schema: %Schema{type: :string, format: :uuid}]],
    responses: [
      ok: {"Analysis target", "application/json", TargetResponse},
      not_found: {"Target not found", "application/json", ErrorResponse}
    ]

  operation :create,
    summary: "Create an analysis target",
    request_body: {"Target attributes", "application/json", CreateTargetRequest},
    responses: [
      created: {"Created target", "application/json", TargetResponse},
      unprocessable_entity: {"Validation errors", "application/json", ValidationErrorsResponse}
    ]

  operation :update,
    summary: "Update an analysis target",
    parameters: [id: [in: :path, schema: %Schema{type: :string, format: :uuid}]],
    request_body: {"Target changes", "application/json", UpdateTargetRequest},
    responses: [
      ok: {"Updated target", "application/json", TargetResponse},
      not_found: {"Target not found", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation errors", "application/json", ValidationErrorsResponse}
    ]

  operation :deactivate,
    summary: "Deactivate an analysis target",
    parameters: [id: [in: :path, schema: %Schema{type: :string, format: :uuid}]],
    responses: [
      ok: {"Deactivated target", "application/json", TargetResponse},
      not_found: {"Target not found", "application/json", ErrorResponse}
    ]

  def index(conn, _params) do
    targets = Analysis.list_targets()
    json(conn, %{targets: Enum.map(targets, &target_json/1)})
  end

  def show(conn, %{"id" => id}) do
    case Analysis.fetch_target(id) do
      {:ok, target} -> json(conn, %{target: target_json(target)})
      :error -> not_found(conn)
    end
  end

  def create(conn, %{"target" => attrs}) when is_map(attrs) do
    case Analysis.create_target(attrs) do
      {:ok, target} -> conn |> put_status(:created) |> json(%{target: target_json(target)})
      {:error, changeset} -> validation_error(conn, changeset)
    end
  end

  def create(conn, _params), do: invalid_attributes(conn, :target)

  def update(conn, %{"id" => id, "target" => attrs}) when is_map(attrs) do
    case Analysis.fetch_target(id) do
      {:ok, target} ->
        case Analysis.update_target(target, attrs) do
          {:ok, target} -> json(conn, %{target: target_json(target)})
          {:error, changeset} -> validation_error(conn, changeset)
        end

      :error ->
        not_found(conn)
    end
  end

  def update(conn, _params), do: invalid_attributes(conn, :target)

  def deactivate(conn, %{"id" => id}) do
    case Analysis.fetch_target(id) do
      {:ok, target} ->
        case Analysis.deactivate_target(target) do
          {:ok, target} -> json(conn, %{target: target_json(target)})
          {:error, changeset} -> validation_error(conn, changeset)
        end

      :error ->
        not_found(conn)
    end
  end

  defp validation_error(conn, changeset) do
    conn |> put_status(:unprocessable_entity) |> json(%{errors: errors(changeset)})
  end

  defp invalid_attributes(conn, field) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: %{field => ["must be an object"]}})
  end

  defp not_found(conn), do: conn |> put_status(:not_found) |> json(%{error: "not_found"})

  defp target_json(target) do
    Map.take(target, [
      :id,
      :security_code,
      :market,
      :display_name,
      :sector,
      :tags,
      :active,
      :source_reference,
      :verified_at
    ])
  end

  defp errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, options} ->
      Enum.reduce(options, message, fn {key, value}, message ->
        value_string =
          if is_binary(value) or is_atom(value) or is_number(value),
            do: to_string(value),
            else: inspect(value)

        String.replace(message, "%{#{key}}", value_string)
      end)
    end)
  end
end
