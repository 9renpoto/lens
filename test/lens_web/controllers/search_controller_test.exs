defmodule LensWeb.SearchControllerTest do
  use Lens.DataCase

  import Phoenix.ConnTest

  alias Lens.Content

  @endpoint LensWeb.Endpoint

  test "returns ranked search results with a plain-text excerpt" do
    source = source_fixture()

    document =
      document_fixture(source, %{
        title: "Search result",
        content: "First searchable line.\n\nSecond searchable line."
      })

    conn = build_conn() |> get("/api/search", %{q: "searchable"})

    assert %{
             "results" => [
               %{
                 "id" => document_id,
                 "title" => "Search result",
                 "canonical_url" => canonical_url,
                 "excerpt" => "First searchable line. Second searchable line."
               }
             ]
           } = json_response(conn, 200)

    assert document_id == document.id
    assert canonical_url == document.canonical_url
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

    assert %{
             "document" => %{
               "id" => document_id,
               "title" => "Canonical document",
               "canonical_url" => "https://example.com/documents/canonical",
               "content" => "Canonical content"
             }
           } = json_response(conn, 200)

    assert document_id == document.id
  end

  test "rejects missing, empty, and invalid search parameters" do
    assert %{"error" => "q is required"} =
             build_conn() |> get("/api/search") |> json_response(422)

    assert %{"error" => "invalid_query"} =
             build_conn() |> get("/api/search", %{q: "  "}) |> json_response(422)

    assert %{"error" => "invalid_pagination"} =
             build_conn() |> get("/api/search", %{q: "term", limit: "many"}) |> json_response(422)
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
