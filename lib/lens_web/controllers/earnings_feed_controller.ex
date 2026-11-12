defmodule LensWeb.EarningsFeedController do
  use LensWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Lens.Earnings.Feed
  alias OpenApiSpex.Schema

  tags(["Earnings"])

  operation :show,
    summary: "Read acquired earnings information as a service RSS 2.0 feed",
    responses: [
      ok: {"RSS feed", "application/rss+xml", %Schema{type: :string}}
    ]

  def show(conn, _params) do
    base_url = LensWeb.Endpoint.url()
    xml = base_url |> Feed.entries() |> Feed.render(base_url)

    conn
    |> put_resp_content_type("application/rss+xml")
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(:ok, xml)
  end
end
