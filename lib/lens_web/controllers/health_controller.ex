defmodule LensWeb.HealthController do
  use LensWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Lens.Repo
  alias LensWeb.ApiSchemas.{HealthResponse, ReadyResponse, UnavailableResponse}

  tags(["Health"])

  operation :show,
    summary: "Report process health",
    responses: [ok: {"Lens is running", "application/json", HealthResponse}]

  operation :ready,
    summary: "Report database readiness",
    responses: [
      ok: {"PostgreSQL is reachable", "application/json", ReadyResponse},
      service_unavailable: {"PostgreSQL is unavailable", "application/json", UnavailableResponse}
    ]

  def show(conn, _params) do
    json(conn, %{status: "ok"})
  end

  def ready(conn, _params) do
    case Repo.query("SELECT 1") do
      {:ok, _result} ->
        json(conn, %{status: "ready"})

      {:error, _reason} ->
        conn |> put_status(:service_unavailable) |> json(%{status: "unavailable"})
    end
  end
end
