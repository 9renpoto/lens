defmodule Lens.IngestionTest do
  use Lens.DataCase

  import ExUnit.CaptureLog

  alias Lens.Content
  alias Lens.Content.Document
  alias Lens.Ingestion
  alias Lens.Ingestion.{Fetcher, Normalizer, Parser}

  describe "ingest/2" do
    test "normalizes RSS content and records an observation" do
      source = source_fixture()

      result =
        Ingestion.ingest(source,
          transport: transport(200, rss_fixture(), %{"etag" => ["rss-v1"]})
        )

      assert result.outcome == :success
      assert length(result.valid_entries) == 1
      assert result.invalid_entries == []

      [document] = Repo.all(Document)
      assert document.canonical_url == "https://example.com/articles/one"
      assert document.content == "First paragraph\n\nSecond & final paragraph"
      assert document.published_at == ~U[2026-09-07 12:00:00.000000Z]

      source = Content.get_source!(source.id)
      assert source.etag == "rss-v1"
      assert source.failure_count == 0
      assert source.last_attempt_at
      assert source.last_success_at
      assert source.last_error == nil
    end

    test "handles Atom and RSSHub output through the same path" do
      source =
        source_fixture(source_type: "rsshub", endpoint_url: "http://127.0.0.1:1200/example")

      result = Ingestion.ingest(source, transport: transport(200, atom_fixture()))

      assert result.outcome == :success
      [document] = Repo.all(Document)
      assert document.canonical_url == "https://example.com/posts/atom"
      assert document.author == "Ada"
      assert document.content == "Atom summary"
    end

    test "uses conditional headers and preserves data on not modified" do
      source = source_fixture(etag: "feed-v1", last_modified: "Sun, 07 Sep 2026 12:00:00 GMT")
      {:ok, %{document: document}} = Content.observe_document(source, entry_fixture())

      result =
        Ingestion.ingest(source,
          transport: fn request ->
            assert {"if-none-match", "feed-v1"} in request.headers
            assert {"if-modified-since", "Sun, 07 Sep 2026 12:00:00 GMT"} in request.headers
            {:ok, %{status: 304, headers: %{"etag" => "feed-v1"}}}
          end
        )

      assert result.outcome == :not_modified
      assert Content.get_document!(document.id).content == "Existing content"
      assert Content.get_source!(source.id).last_success_at
    end

    test "retains valid entries and reports invalid entries separately" do
      source = source_fixture()

      result =
        Ingestion.ingest(source,
          transport: transport(200, rss_fixture_with_invalid_entry())
        )

      assert result.outcome == :success
      assert length(result.valid_entries) == 1
      assert result.invalid_entries == [%{index: 1, error: "entry has no title or content"}]
      assert Repo.aggregate(Document, :count) == 1
    end

    test "keeps prior validators and documents when parsing fails" do
      source = source_fixture(etag: "feed-v1")
      {:ok, %{document: document}} = Content.observe_document(source, entry_fixture())

      result = Ingestion.ingest(source, transport: transport(200, "<rss><channel>"))

      assert result.outcome == :failure
      assert Content.get_document!(document.id).content == "Existing content"

      source = Content.get_source!(source.id)
      assert source.etag == "feed-v1"
      assert source.failure_count == 1
      assert source.last_error
    end

    test "reports size limits, HTTP errors, and timeouts as failures" do
      source = source_fixture(etag: "feed-v1")

      oversized =
        Ingestion.ingest(source, max_bytes: 10, transport: transport(200, rss_fixture()))

      assert oversized.outcome == :failure
      assert oversized.error == "response exceeds byte limit"

      http_error = Ingestion.ingest(source, transport: transport(503, "unavailable"))
      assert http_error.outcome == :failure
      assert http_error.error == "unexpected HTTP status 503"

      timeout = Ingestion.ingest(source, transport: fn _request -> {:error, "timeout"} end)
      assert timeout.outcome == :failure
      assert timeout.error == "timeout"

      source = Content.get_source!(source.id)
      assert source.etag == "feed-v1"
      assert source.failure_count == 3
    end

    test "captures a bounded retry-after delay from failed HTTP responses" do
      source = source_fixture()

      result =
        Ingestion.ingest(source,
          transport: transport(503, "unavailable", %{"retry-after" => "7200"})
        )

      assert result.outcome == :failure
      assert result.retry_after_seconds == 3_600
    end

    test "bounds request timeouts and redirects" do
      source = source_fixture()

      assert {:error, "unexpected HTTP status 302", %{}} =
               Fetcher.fetch(source,
                 timeout: 1_234,
                 max_redirects: 2,
                 transport: fn request ->
                   assert request.timeout == 1_234
                   assert request.max_redirects == 2
                   {:ok, %{status: 302, headers: %{}, body: ""}}
                 end
               )
    end

    test "normalizes list-valued HTTP headers" do
      source = source_fixture()

      assert {:ok, %{headers: headers}} =
               Fetcher.fetch(source,
                 transport:
                   transport(200, rss_fixture(), %{
                     "etag" => ["rss-v1"],
                     "last-modified" => ["Sun, 07 Sep 2026 12:00:00 GMT"]
                   })
               )

      assert headers["etag"] == "rss-v1"
      assert headers["last-modified"] == "Sun, 07 Sep 2026 12:00:00 GMT"
    end

    test "rejects declared and actual response byte limits" do
      source = source_fixture()

      assert {:error, "response exceeds byte limit", _headers} =
               Fetcher.fetch(source,
                 max_bytes: 3,
                 transport: transport(200, "abcd", %{"content-length" => "4"})
               )

      assert {:error, "response exceeds byte limit", _headers} =
               Fetcher.fetch(source, max_bytes: 3, transport: transport(200, "abcd"))
    end

    test "rejects feeds that exceed the entry limit without changing validators" do
      source = source_fixture(etag: "feed-v1")

      result =
        Ingestion.ingest(source,
          max_entries: 1,
          transport: transport(200, rss_fixture_with_invalid_entry(), %{"etag" => "feed-v2"})
        )

      assert result.outcome == :failure
      assert result.error == "feed exceeds entry limit"
      assert Content.get_source!(source.id).etag == "feed-v1"
      assert Repo.aggregate(Document, :count) == 0
    end

    test "repeated feeds preserve document identity and add observations" do
      source = source_fixture()

      assert :success ==
               Ingestion.ingest(source, transport: transport(200, rss_fixture())).outcome

      assert :success ==
               Ingestion.ingest(source, transport: transport(200, rss_fixture())).outcome

      [document] = Repo.all(Document)
      assert length(Content.list_observations(document)) == 2
    end

    test "logs source outcome metadata without feed content" do
      source = source_fixture()

      log =
        capture_log(fn ->
          Ingestion.ingest(source, transport: transport(200, rss_fixture()))
        end)

      assert log =~ "source_id=#{source.id}"
      assert log =~ "outcome=success"
      assert log =~ "valid_entries=1"
      refute log =~ "First paragraph"
    end
  end

  describe "normalization boundaries" do
    test "normalizes relative links, entities, dates, and unsupported XML" do
      assert Normalizer.resolve_url("/article#section", "https://example.com/feed") ==
               "https://example.com/article"

      assert Normalizer.text("<style>body {}</style><p>A &#x26; B</p>") == "A & B"

      assert DateTime.compare(
               Normalizer.date("2026-09-07T12:00:00+00:00"),
               ~U[2026-09-07 12:00:00Z]
             ) ==
               :eq

      assert Normalizer.date("not a date") == nil

      assert {:error, "unsupported feed format"} =
               Parser.parse("<catalog />", "https://example.com/feed")
    end
  end

  defp source_fixture(attrs \\ %{}) do
    defaults = %{
      source_type: "rss",
      endpoint_url: "https://feeds.example.com/feed.xml",
      poll_interval_seconds: 300
    }

    {:ok, source} = Content.create_source(Map.merge(defaults, Map.new(attrs)))
    source
  end

  defp entry_fixture do
    %{
      canonical_url: "https://example.com/existing",
      title: "Existing",
      content: "Existing content"
    }
  end

  defp transport(status, body, headers \\ %{}) do
    fn _request -> {:ok, %{status: status, headers: headers, body: body}} end
  end

  defp rss_fixture do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
      <channel>
        <title>Example feed</title>
        <link>https://example.com/</link>
        <item>
          <guid>rss-1</guid>
          <title>Example &amp; entry</title>
          <link>/articles/one</link>
          <content:encoded><![CDATA[<p>First paragraph</p><script>alert('x')</script><p>Second &amp; final paragraph</p>]]></content:encoded>
          <pubDate>Sun, 07 Sep 2026 12:00:00 GMT</pubDate>
        </item>
      </channel>
    </rss>
    """
  end

  defp rss_fixture_with_invalid_entry do
    rss_fixture()
    |> String.replace("</channel>", "<item><guid>missing</guid></item></channel>")
  end

  defp atom_fixture do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>RSSHub-like feed</title>
      <link href="https://example.com/" rel="alternate" />
      <entry>
        <id>atom-1</id>
        <title>Atom entry</title>
        <link href="/posts/atom" rel="alternate" />
        <summary><![CDATA[<p>Atom summary</p>]]></summary>
        <author><name>Ada</name></author>
        <published>2026-09-07T12:00:00+00:00</published>
      </entry>
    </feed>
    """
  end
end
