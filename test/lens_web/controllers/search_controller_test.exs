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

    document =
      document_fixture(source, %{
        canonical_url: "https://example.com/documents/canonical",
        title: "Canonical document",
        content: "Canonical content"
      })

    conn = build_conn() |> get("/api/documents/#{document.id}")

    response = json_response(conn, 200)

    assert %{
             "document" => %{
               "id" => document_id,
               "title" => "Canonical document",
               "canonical_url" => "https://example.com/documents/canonical",
               "content" => "Canonical content"
             }
           } = response

    assert document_id == document.id
    assert_response_schema(response, "DocumentResponse", ApiSpec.spec())
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

  defp source_fixture do
    {:ok, source} =
      Content.create_source(%{
        source_type: "rss",
        endpoint_url: "https://feeds.example.com/#{System.unique_integer([:positive])}.xml",
        poll_interval_seconds: 300
      })

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
end
