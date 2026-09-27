defmodule LensWeb.EarningsController do
  use LensWeb, :controller
  use OpenApiSpex.ControllerSpecs
  alias Lens.Earnings.{Extractions, Release}
  alias Lens.Repo
  alias LensWeb.ApiSchemas.{EarningsReleaseResponse, ErrorResponse}
  alias OpenApiSpex.Schema

  tags(["Earnings"])

  operation :show,
    summary: "Inspect an earnings release and its selected extracted text",
    parameters: [id: [in: :path, required: true, schema: %Schema{type: :string, format: :uuid}]],
    responses: [
      ok: {"Earnings release", "application/json", EarningsReleaseResponse},
      not_found: {"Release not found", "application/json", ErrorResponse}
    ]

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
