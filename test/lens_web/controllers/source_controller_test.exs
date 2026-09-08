defmodule LensWeb.SourceControllerTest do
  use Lens.DataCase

  import Phoenix.ConnTest

  @endpoint LensWeb.Endpoint

  test "creates, lists, updates, and disables a source" do
    create_conn =
      build_conn()
      |> post("/api/sources", %{
        source: %{
          source_type: "rss",
          endpoint_url: "https://feeds.example.com/source.xml",
          poll_interval_seconds: 300
        }
      })

    assert %{"source" => %{"id" => id, "enabled" => true, "next_fetch_at" => next_fetch_at}} =
             json_response(create_conn, 201)

    assert is_binary(next_fetch_at)

    assert %{"sources" => [%{"id" => ^id}]} =
             build_conn() |> get("/api/sources") |> json_response(200)

    update_conn = build_conn() |> patch("/api/sources/#{id}", %{source: %{enabled: false}})
    assert %{"source" => %{"enabled" => false}} = json_response(update_conn, 200)
  end

  test "returns validation errors for an invalid source" do
    conn =
      build_conn()
      |> post("/api/sources", %{
        source: %{source_type: "rss", endpoint_url: "invalid", poll_interval_seconds: 0}
      })

    assert %{"errors" => %{"endpoint_url" => _, "poll_interval_seconds" => _}} =
             json_response(conn, 422)
  end
end
