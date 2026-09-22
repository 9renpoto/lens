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
                 "excerpt" => "First searchable line. Second searchable line.",
                 "provenance_url" => provenance_url
               }
             ]
           } = response

    assert document_id == document.id
    assert canonical_url == document.canonical_url
    assert provenance_url == "/api/documents/#{document.id}/provenance"
    assert_response_schema(response, "SearchResponse", ApiSpec.spec())
  end

  test "searches normalized Japanese text and rejects a one-character query" do
    source = source_fixture()

    document =
      document_fixture(source, %{
        title: "第1四半期決算説明資料",
        content: "売上高は前年同期比12％増となりました。"
      })

    response = build_conn() |> get("/api/search", %{q: "前年同期比"}) |> json_response(200)
    assert %{"results" => [%{"id" => document_id}]} = response
    assert document_id == document.id

    assert %{"error" => "invalid_query"} =
             build_conn() |> get("/api/search", %{q: "株"}) |> json_response(422)
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

    assert {:ok, %{document: _second_doc}} =
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
               "sources" => sources,
               "provenance_url" => provenance_url
             }
           } = response

    assert document_id == document.id
    assert provenance_url == "/api/documents/#{document.id}/provenance"

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

      provenance_response =
        build_conn() |> get("/api/documents/#{id}/provenance") |> json_response(404)

      assert provenance_response == %{"error" => "not_found"}
      assert_response_schema(provenance_response, "ErrorResponse", ApiSpec.spec())
    end
  end

  test "returns paginated document observation provenance without endpoint URLs or credentials" do
    source =
      source_fixture(%{
        feed_format: "rss_2_0",
        acquisition_kind: "direct",
        publisher_authority: "official",
        original_feed_url: "https://publisher.example.test/feed.xml",
        endpoint_url: "https://private-ingest.internal.test/feed.xml"
      })

    second_source =
      source_fixture(%{
        feed_format: "atom",
        acquisition_kind: "conversion_service",
        publisher_authority: "unknown",
        acquisition_metadata: %{"converter" => "fixture"},
        endpoint_url: "https://private-converter.internal.test/feed.xml"
      })

    document =
      document_fixture(
        source,
        %{
          canonical_url: "https://publisher.example.test/article/1",
          title: "Article 1",
          content: "Content 1",
          published_at: ~U[2026-09-08 10:00:00Z]
        },
        observed_at: ~U[2026-09-08 10:00:00Z]
      )

    assert {:ok, %{document: second_doc}} =
             Content.observe_document(
               second_source,
               %{
                 canonical_url: "https://publisher.example.test/article/1",
                 title: "Article 1 Updated",
                 content: "Content 1 Updated",
                 published_at: ~U[2026-09-08 10:05:00Z]
               },
               observed_at: ~U[2026-09-08 11:00:00Z]
             )

    assert second_doc.id == document.id

    conn = build_conn() |> get("/api/documents/#{document.id}/provenance", %{limit: 1, offset: 0})
    response = json_response(conn, 200)

    assert %{
             "observations" => [
               %{
                 "id" => obs_id,
                 "source_id" => second_source_id,
                 "observed_at" => "2026-09-08T11:00:00.000000Z",
                 "content_hash" => content_hash,
                 "entry_url" => "https://publisher.example.test/article/1",
                 "primary_source_url" => nil,
                 "feed_format" => "atom",
                 "acquisition_kind" => "conversion_service",
                 "publisher_authority" => "unknown",
                 "acquisition_metadata_snapshot" => %{"converter" => "fixture"},
                 "reported_published_at" => "2026-09-08T10:05:00.000000Z"
               }
             ]
           } = response

    assert second_source_id == second_source.id
    assert is_binary(obs_id)
    assert is_binary(content_hash)
    refute Map.has_key?(hd(response["observations"]), "endpoint_url")
    assert_response_schema(response, "DocumentProvenanceResponse", ApiSpec.spec())

    page2_response =
      build_conn()
      |> get("/api/documents/#{document.id}/provenance", %{limit: 1, offset: 1})
      |> json_response(200)

    assert %{
             "observations" => [
               %{
                 "source_id" => first_source_id,
                 "entry_url" => "https://publisher.example.test/article/1",
                 "primary_source_url" => "https://publisher.example.test/feed.xml",
                 "feed_format" => "rss_2_0",
                 "acquisition_kind" => "direct",
                 "publisher_authority" => "official",
                 "acquisition_metadata_snapshot" => %{},
                 "reported_published_at" => "2026-09-08T10:00:00.000000Z"
               }
             ]
           } = page2_response

    assert first_source_id == source.id
    refute Map.has_key?(hd(page2_response["observations"]), "endpoint_url")
    assert_response_schema(page2_response, "DocumentProvenanceResponse", ApiSpec.spec())
  end

  test "rejects invalid pagination parameters for document provenance" do
    for params <- [
          %{"limit" => "invalid"},
          %{"limit" => "0"},
          %{"limit" => "101"},
          %{"offset" => "-1"},
          %{"offset" => "9223372036854775808"},
          %{"limit" => ["1"]},
          %{"offset" => %{"x" => "1"}}
        ] do
      source = source_fixture()
      document = document_fixture(source, %{})

      response =
        build_conn()
        |> get("/api/documents/#{document.id}/provenance", params)
        |> json_response(422)

      assert response == %{"error" => "invalid_pagination"}
      assert_response_schema(response, "ErrorResponse", ApiSpec.spec())
    end
  end

  test "redacts sensitive keys in acquisition metadata snapshot when rendering provenance" do
    source =
      source_fixture(%{
        feed_format: "atom",
        acquisition_kind: "conversion_service",
        publisher_authority: "third_party",
        acquisition_metadata: %{
          "route" => "news",
          "api_key" => "secret123",
          "tags" => ["news", "tech"],
          "nested" => %{"secret" => "supersecret"}
        }
      })

    document = document_fixture(source, %{})

    conn = build_conn() |> get("/api/documents/#{document.id}/provenance")
    response = json_response(conn, 200)

    assert %{
             "observations" => [
               %{
                 "acquisition_metadata_snapshot" => %{
                   "route" => "news",
                   "api_key" => "[REDACTED]",
                   "tags" => ["news", "tech"],
                   "nested" => %{"secret" => "[REDACTED]"}
                 }
               }
             ]
           } = response
  end

  test "redacts sensitive query parameters in entry_url and primary_source_url" do
    source =
      source_fixture(%{
        original_feed_url: "https://publisher.example.test/feed.xml?token=secret123&format=rss"
      })

    document =
      document_fixture(source, %{
        canonical_url: "https://publisher.example.test/article?sig=xyz987&author=ada"
      })

    conn = build_conn() |> get("/api/documents/#{document.id}/provenance")
    response = json_response(conn, 200)

    assert %{
             "observations" => [
               %{
                 "entry_url" => entry_url,
                 "primary_source_url" => primary_url
               }
             ]
           } = response

    assert entry_url =~ "author=ada"
    assert entry_url =~ "sig=%5BREDACTED%5D" or entry_url =~ "sig=[REDACTED]"
    refute entry_url =~ "xyz987"

    assert primary_url =~ "format=rss"
    assert primary_url =~ "token=%5BREDACTED%5D" or primary_url =~ "token=[REDACTED]"
    refute primary_url =~ "secret123"
  end

  test "preserves repeated and valueless query parameters, and redacts path and fragment credentials in provenance URLs" do
    source =
      source_fixture(%{
        original_feed_url:
          "https://publisher.example.test/private/token/secret123/feed.xml?preview&role=reader&role=writer#access_token=secret123&state=abc"
      })

    document =
      document_fixture(
        source,
        %{canonical_url: "https://publisher.example.test/section#section-1"},
        observed_at: ~U[2026-09-08 10:00:00Z]
      )

    conn = build_conn() |> get("/api/documents/#{document.id}/provenance")
    response = json_response(conn, 200)

    assert %{
             "observations" => [
               %{
                 "primary_source_url" => primary_url
               }
             ]
           } = response

    assert primary_url =~ "role=reader&role=writer"
    assert primary_url =~ "state=abc"

    assert primary_url =~ "access_token=%5BREDACTED%5D" or
             primary_url =~ "access_token=[REDACTED]"

    refute primary_url =~ "secret123"
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

  defp document_fixture(source, attrs, options \\ []) do
    defaults = %{
      canonical_url: "https://example.com/documents/#{System.unique_integer([:positive])}",
      title: "Document",
      content: "Content"
    }

    {:ok, %{document: document}} =
      Content.observe_document(source, Map.merge(defaults, attrs), options)

    document
  end

  defp missing_id, do: "00000000-0000-0000-0000-000000000000"
end
