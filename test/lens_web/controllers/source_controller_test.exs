defmodule LensWeb.SourceControllerTest do
  use Lens.DataCase

  import Phoenix.ConnTest
  import OpenApiSpex.TestAssertions

  alias LensWeb.ApiSpec
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

    create_response = json_response(create_conn, 201)

    assert %{"source" => %{"id" => id, "enabled" => true, "next_fetch_at" => next_fetch_at}} =
             create_response

    assert_response_schema(create_response, "SourceResponse", ApiSpec.spec())

    assert is_binary(next_fetch_at)

    list_response = build_conn() |> get("/api/sources") |> json_response(200)
    assert %{"sources" => [%{"id" => ^id}]} = list_response
    assert_response_schema(list_response, "SourcesResponse", ApiSpec.spec())

    update_conn = build_conn() |> patch("/api/sources/#{id}", %{source: %{enabled: false}})
    update_response = json_response(update_conn, 200)
    assert %{"source" => %{"enabled" => false}} = update_response
    assert_response_schema(update_response, "SourceResponse", ApiSpec.spec())

    replace_conn =
      build_conn() |> put("/api/sources/#{id}", %{source: %{title: "Updated source"}})

    replace_response = json_response(replace_conn, 200)
    assert %{"source" => %{"title" => "Updated source"}} = replace_response
    assert_response_schema(replace_response, "SourceResponse", ApiSpec.spec())
  end

  test "returns validation errors for an invalid source" do
    conn =
      build_conn()
      |> post("/api/sources", %{
        source: %{source_type: "rss", endpoint_url: "invalid", poll_interval_seconds: 0}
      })

    response = json_response(conn, 422)
    assert %{"errors" => %{"endpoint_url" => _, "poll_interval_seconds" => _}} = response
    assert_response_schema(response, "ValidationErrorsResponse", ApiSpec.spec())
  end
end
