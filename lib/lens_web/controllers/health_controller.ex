defmodule LensWeb.HealthController do
  use LensWeb, :controller

  alias Lens.Repo

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
