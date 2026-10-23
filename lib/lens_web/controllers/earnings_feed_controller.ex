defmodule LensWeb.EarningsFeedController do
  use LensWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Lens.{Analysis, Earnings.Feed}
  alias LensWeb.ApiSchemas.ErrorResponse
  alias OpenApiSpex.Schema

  tags(["Earnings"])

  operation :show,
    summary: "Read retained earnings as an RSS 2.0 feed",
    parameters: [
      target_id: [in: :path, required: true, schema: %Schema{type: :string, format: :uuid}]
    ],
    responses: [
      ok: {"RSS feed", "application/rss+xml", %Schema{type: :string}},
      not_found: {"Target not found", "application/json", ErrorResponse}
    ]

  def show(conn, %{"target_id" => id}) do
    case Analysis.fetch_target(id) do
      {:ok, target} ->
        xml = target.security_code |> Feed.entries() |> Feed.render(LensWeb.Endpoint.url())

        conn
        |> put_resp_content_type("application/rss+xml")
        |> put_resp_header("cache-control", "no-store")
        |> send_resp(:ok, xml)

      :error ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})
    end
  end
end
