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
    description: """
    Return all registered sources for an existing analysis target, including disabled sources.
    Each target may have multiple listing sources. Source enablement is independent of the
    target's active flag and index memberships. An unknown or malformed target ID returns 404.
    """,
    parameters: [
      target_id: [in: :path, required: true, schema: %Schema{type: :string, format: :uuid}]
    ],
    responses: [
      ok: {"Sources", "application/json", EarningsSourcesResponse},
      not_found: {"Target not found", "application/json", ErrorResponse}
    ]

  operation :show,
    summary: "Inspect an earnings source",
    description: """
    Return a source belonging to the target in the path. An unknown or malformed target/source
    ID, or a source belonging to a different target, returns 404 with {"error":"not_found"}.
    """,
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
    description: """
    First register or select an existing analysis target through /api/targets; index membership
    is optional. Send a JSON source object with listing_url and optional enabled. The target ID
    comes from the path and cannot be supplied in the body. Omitted enabled defaults to true;
    explicit false registers a disabled source. No source name, PDF, classifier or approval
    settings are required. Registering a target alone creates no source.

    Review the publisher's acquisition and preservation conditions before registering or
    enabling an active source. Lens has no approval state or automatic terms assessment.
    Registration does not contact publishers, authorize HTTP acquisition or start a crawl.
    Registered-source crawling remains work in #125.

    An exactly matching listing_url is unique within a target; different targets may use the
    same URL. URLs are not canonicalized or rewritten. Missing/invalid attributes, a missing
    or non-object source, a supplied target_id, or a duplicate URL return 422 with field errors
    in errors. An unknown or malformed target ID with a valid source object returns 404.
    Existing /api/sources endpoints continue to manage feed sources separately.
    """,
    parameters: [
      target_id: [in: :path, required: true, schema: %Schema{type: :string, format: :uuid}]
    ],
    request_body:
      {"Source attributes", "application/json", CreateEarningsSourceRequest, required: true},
    responses: [
      created: {"Registered source", "application/json", EarningsSourceResponse},
      not_found: {"Target not found", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation errors", "application/json", ValidationErrorsResponse}
    ]

  operation :update,
    summary: "Change a source URL or enablement; omitted fields are preserved",
    description: """
    Send a JSON source object containing listing_url and/or enabled. Omitted fields retain
    their values; {"source":{}} is a valid no-op. Set enabled to false to stop collection
    eligibility. Explicit null/blank URL or enablement and invalid boolean values return 422.

    The source ID and target stay fixed when the URL changes. Supplying target_id or changing
    the URL to another source's exact URL within the target returns 422. Register a new source
    for a different target. There is no deletion endpoint; disable unwanted sources instead.
    Changes do not relabel historical URLs or issuers, authorize HTTP acquisition or start a crawl.
    An unknown or malformed target/source ID, or a source belonging to a different target,
    with a valid source object returns 404 with {"error":"not_found"}.
    """,
    parameters: [
      target_id: [in: :path, required: true, schema: %Schema{type: :string, format: :uuid}],
      id: [in: :path, required: true, schema: %Schema{type: :string, format: :uuid}]
    ],
    request_body:
      {"Source changes", "application/json", UpdateEarningsSourceRequest, required: true},
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
