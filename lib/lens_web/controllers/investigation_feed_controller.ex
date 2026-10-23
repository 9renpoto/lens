defmodule LensWeb.InvestigationFeedController do
  use LensWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Lens.Investigations
  alias OpenApiSpex.Schema

  tags(["Investigation candidates"])

  operation :show,
    summary: "Read the investigation-candidate RSS 2.0 feed",
    responses: [ok: {"RSS feed", "application/rss+xml", %Schema{type: :string}}]

  def show(conn, _params) do
    xml = Investigations.list_candidates() |> Investigations.Feed.render()

    conn
    |> put_resp_content_type("application/rss+xml")
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(:ok, xml)
  end
end
