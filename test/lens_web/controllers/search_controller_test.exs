defmodule LensWeb.SearchControllerTest do
  use Lens.DataCase

  import Phoenix.ConnTest
  import OpenApiSpex.TestAssertions

  alias Lens.Content
  alias LensWeb.ApiSpec

  @endpoint LensWeb.Endpoint

  test "returns ranked search results with a plain-text excerpt" do
    source = source_fixture()

    document =
      document_fixture(source, %{
        title: "Search result",
        content: "First searchable line.\n\nSecond searchable line."
      })

    conn = build_conn() |> get("/api/search", %{q: "searchable"})

    response = json_response(conn, 200)

    assert %{
             "results" => [
               %{
                 "id" => document_id,
                 "title" => "Search result",
                 "canonical_url" => canonical_url,
                 "excerpt" => "First searchable line. Second searchable line."
               }
             ]
           } = response

    assert document_id == document.id
    assert canonical_url == document.canonical_url
    assert_response_schema(response, "SearchResponse", ApiSpec.spec())
  end

  test "returns canonical document content" do
    source = source_fixture()

    second_source =
      source_fixture(%{endpoint_url: "https://feeds.example.com/second-source.xml"})

    document =
      document_fixture(source, %{
        canonical_url: "https://example.com/documents/canonical",
        title: "Canonical document",
        content: "Canonical content"
      })

    assert {:ok, %{document: ^document}} =
             Content.observe_document(
               second_source,
               %{
                 canonical_url: document.canonical_url,
                 title: document.title,
                 content: document.content
               },
               observed_at: ~U[2026-09-08 00:00:00Z]
             )

    conn = build_conn() |> get("/api/documents/#{document.id}")

    response = json_response(conn, 200)

    assert %{
             "document" => %{
               "id" => document_id,
               "title" => "Canonical document",
               "canonical_url" => "https://example.com/documents/canonical",
               "content" => "Canonical content",
               "sources" => sources
             }
           } = response

    assert document_id == document.id

    assert [
             %{
               "id" => source_id,
               "source_type" => "rss",
               "endpoint_url" => source_url,
               "observed_at" => first_observed_at
             },
             %{
               "id" => second_source_id,
               "source_type" => "rss",
               "endpoint_url" => second_source_url,
               "observed_at" => "2026-09-08T00:00:00.000000Z"
             }
           ] = Enum.sort_by(sources, & &1["endpoint_url"])

    assert {source_id, source_url} == {source.id, source.endpoint_url}
    assert is_binary(first_observed_at)
    assert {second_source_id, second_source_url} == {second_source.id, second_source.endpoint_url}

    assert_response_schema(response, "DocumentResponse", ApiSpec.spec())
  end

  test "returns the documented JSON 404 for missing or malformed document IDs" do
    for id <- ["not-a-uuid", missing_id()] do
      response = build_conn() |> get("/api/documents/#{id}") |> json_response(404)

      assert response == %{"error" => "not_found"}
      assert_response_schema(response, "ErrorResponse", ApiSpec.spec())
    end
  end

  test "rejects missing, empty, and invalid search parameters" do
    missing_query_response = build_conn() |> get("/api/search") |> json_response(422)
    assert %{"error" => "q is required"} = missing_query_response
    assert_response_schema(missing_query_response, "ErrorResponse", ApiSpec.spec())

    empty_query_response = build_conn() |> get("/api/search", %{q: "  "}) |> json_response(422)
    assert %{"error" => "invalid_query"} = empty_query_response
    assert_response_schema(empty_query_response, "ErrorResponse", ApiSpec.spec())

    invalid_pagination_response =
      build_conn() |> get("/api/search", %{q: "term", limit: "many"}) |> json_response(422)

    assert %{"error" => "invalid_pagination"} = invalid_pagination_response
    assert_response_schema(invalid_pagination_response, "ErrorResponse", ApiSpec.spec())
  end

  defp source_fixture(attrs \\ %{}) do
    {:ok, source} =
      Content.create_source(
        %{
          source_type: "rss",
          endpoint_url: "https://feeds.example.com/#{System.unique_integer([:positive])}.xml",
          poll_interval_seconds: 300
        }
        |> Map.merge(attrs)
      )

    source
  end

  defp document_fixture(source, attrs) do
    defaults = %{
      canonical_url: "https://example.com/documents/#{System.unique_integer([:positive])}",
      title: "Document",
      content: "Content"
    }

    {:ok, %{document: document}} = Content.observe_document(source, Map.merge(defaults, attrs))
    document
  end

  defp missing_id, do: "00000000-0000-0000-0000-000000000000"
end
