defmodule LensWeb.EarningsController do
  use LensWeb, :controller
  use OpenApiSpex.ControllerSpecs
  alias Lens.Earnings
  alias Lens.Earnings.{Extractions, Release, StorageWork}
  alias Lens.Repo

  alias LensWeb.ApiSchemas.{
    EarningsReleaseResponse,
    ErrorResponse,
    EarningsStorageWorkListResponse,
    EarningsStorageWorkResponse,
    EarningsOriginalUnavailableResponse
  }

  alias OpenApiSpex.Schema

  tags(["Earnings"])

  operation :show,
    summary: "Inspect an earnings release and its selected extracted text",
    parameters: [id: [in: :path, required: true, schema: %Schema{type: :string, format: :uuid}]],
    responses: [
      ok: {"Earnings release", "application/json", EarningsReleaseResponse},
      not_found: {"Release not found", "application/json", ErrorResponse}
    ]

  operation :storage_work_index,
    summary: "List bounded unfinished storage work metadata",
    description:
      "Read-only live view behind the existing private operator boundary. Returns only id, acquisition_id, status and updated_at, ordered by insertion time and ID. Completion can remove an item between requests. No storage I/O or retry is performed.",
    parameters: [
      limit: [in: :query, schema: %Schema{type: :integer, minimum: 1, maximum: 100, default: 50}],
      offset: [
        in: :query,
        schema: %Schema{type: :integer, minimum: 0, maximum: 2_147_483_647, default: 0}
      ]
    ],
    responses: [
      ok: {"Unfinished work", "application/json", EarningsStorageWorkListResponse},
      unprocessable_entity: {"Invalid pagination", "application/json", ErrorResponse}
    ]

  operation :storage_work_show,
    summary: "Inspect restricted unfinished storage work metadata",
    description:
      "Malformed, unknown and completed work IDs return 404. No payload or additional storage facts are returned.",
    parameters: [id: [in: :path, required: true, schema: %Schema{type: :string, format: :uuid}]],
    responses: [
      ok: {"Unfinished work", "application/json", EarningsStorageWorkResponse},
      not_found: {"Unfinished work not found", "application/json", ErrorResponse}
    ]

  operation :original,
    summary: "Retrieve exact verified retained PDF bytes",
    description:
      "Reads the selected original version without publisher access or backend fallback. Unknown IDs return 404; known originals with missing, corrupt or unavailable storage return 503 with a safe reason. Success is PDF and errors are JSON. Preserves the existing private operator access boundary; responses are not cached.",
    parameters: [id: [in: :path, required: true, schema: %Schema{type: :string, format: :uuid}]],
    responses: [
      ok: {"Verified PDF bytes", "application/pdf", %Schema{type: :string, format: :binary}},
      not_found: {"Original not found", "application/json", ErrorResponse},
      service_unavailable:
        {"Original storage unavailable", "application/json", EarningsOriginalUnavailableResponse}
    ]

  def storage_work_index(conn, params) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    with {:ok, limit} <- integer_parameter(params, "limit", 50, 1, 100),
         {:ok, offset} <- integer_parameter(params, "offset", 0, 0, 2_147_483_647) do
      json(conn, %{
        work: StorageWork.operator_unfinished(limit, offset),
        limit: limit,
        offset: offset
      })
    else
      _ -> conn |> put_status(:unprocessable_entity) |> json(%{error: "invalid_pagination"})
    end
  end

  def storage_work_show(conn, %{"id" => id}) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    case StorageWork.operator_work(id) do
      {:ok, work} -> json(conn, %{work: work})
      :error -> conn |> put_status(:not_found) |> json(%{error: "not_found"})
    end
  end

  def original(conn, %{"id" => id}) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    case Earnings.original_bytes(id) do
      {:ok, bytes} ->
        conn |> put_resp_content_type("application/pdf", nil) |> send_resp(:ok, bytes)

      :error ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      {:error, reason} ->
        reason =
          if is_atom(reason) and
               Atom.to_string(reason) in EarningsOriginalUnavailableResponse.reasons(),
             do: Atom.to_string(reason),
             else: "storage_error"

        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "original_unavailable", original_id: id, reason: reason})
    end
  end

  defp integer_parameter(params, name, default, low, high) do
    case Map.fetch(params, name) do
      :error ->
        {:ok, default}

      {:ok, value} when is_binary(value) ->
        case Integer.parse(value) do
          {value, ""} when value >= low and value <= high -> {:ok, value}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         {:ok, selected} <- Extractions.release_text(id) do
      release = Repo.get!(Release, id)

      json(conn, %{
        release: Map.take(release, [:id, :issuer_code, :fiscal_year_end, :period, :category]),
        extraction: render_attempt(selected.extraction, true),
        latest_original_id: selected.latest_original_id,
        latest_attempt: render_attempt(selected.latest_attempt, false),
        stale: selected.stale
      })
    else
      _ -> conn |> put_status(:not_found) |> json(%{error: "not_found"})
    end
  end

  defp render_attempt(nil, _), do: nil

  defp render_attempt(attempt, include_text) do
    fields = [
      :id,
      :original_id,
      :status,
      :extraction_options,
      :search_mode,
      :failure_reason,
      :extractor,
      :extractor_version,
      :inserted_at,
      :finished_at
    ]

    fields = if include_text, do: [:text | fields], else: fields
    Map.take(attempt, fields)
  end
end
