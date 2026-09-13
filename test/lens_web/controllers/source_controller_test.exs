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

  test "creates and returns independent provenance classification fields" do
    conn =
      build_conn()
      |> post("/api/sources", %{
        source: %{
          feed_format: "rss_1_0",
          acquisition_kind: "conversion_service",
          publisher_authority: "third_party",
          original_feed_url: "https://publisher.example.test/feed.rdf",
          acquisition_metadata: %{"converter" => "fixture"},
          endpoint_url: "https://converter.example.test/feed.rdf",
          poll_interval_seconds: 300
        }
      })

    assert %{
             "source" => %{
               "feed_format" => "rss_1_0",
               "acquisition_kind" => "conversion_service",
               "publisher_authority" => "third_party",
               "original_feed_url" => "https://publisher.example.test/feed.rdf",
               "acquisition_metadata" => %{"converter" => "fixture"}
             }
           } = json_response(conn, 201)
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

  test "returns the documented JSON 404 for missing or malformed source IDs" do
    for method <- [:get, :patch, :put], id <- ["not-a-uuid", missing_id()] do
      conn =
        case method do
          :get -> build_conn() |> get("/api/sources/#{id}")
          :patch -> build_conn() |> patch("/api/sources/#{id}", %{source: %{enabled: false}})
          :put -> build_conn() |> put("/api/sources/#{id}", %{source: %{enabled: false}})
        end

      response = json_response(conn, 404)
      assert response == %{"error" => "not_found"}
      assert_response_schema(response, "ErrorResponse", ApiSpec.spec())
    end
  end

  defp missing_id, do: "00000000-0000-0000-0000-000000000000"
end
