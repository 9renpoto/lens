defmodule Lens.System.VerticalSliceTest do
  use Lens.DataCase

  import Phoenix.ConnTest

  alias Lens.{Content, Ingestion}
  alias Lens.Content.Document

  @endpoint LensWeb.Endpoint

  test "collects, preserves, updates, and searches local feed fixtures" do
    rss_source = create_source("rss", "https://feeds.example.com/rss.xml")

    assert %{outcome: :success} =
             Ingestion.ingest(Content.get_source!(rss_source),
               transport: transport(200, rss_fixture())
             )

    assert %{"results" => [%{"title" => "Initial entry"}]} =
             build_conn() |> get("/api/search", %{q: "initial"}) |> json_response(200)

    assert %{outcome: :success} =
             Ingestion.ingest(Content.get_source!(rss_source),
               transport: transport(200, rss_fixture("Updated entry", "updated content"))
             )

    assert %{"results" => []} =
             build_conn() |> get("/api/search", %{q: "initial"}) |> json_response(200)

    assert %{"results" => [%{"title" => "Updated entry"}]} =
             build_conn() |> get("/api/search", %{q: "updated"}) |> json_response(200)

    assert 1 == Repo.aggregate(Document, :count)

    rsshub_source = create_source("rsshub", "http://rsshub.local/example")

    assert %{outcome: :success} =
             Ingestion.ingest(Content.get_source!(rsshub_source),
               transport: transport(200, atom_fixture())
             )

    assert %{"results" => [%{"title" => "Atom fixture"}]} =
             build_conn() |> get("/api/search", %{q: "atom"}) |> json_response(200)

    failed_source = create_source("atom", "https://feeds.example.com/unavailable.xml")

    assert %{outcome: :failure, error: "unexpected HTTP status 503"} =
             Ingestion.ingest(Content.get_source!(failed_source),
               transport: transport(503, "unavailable")
             )

    assert %{"sources" => sources} = build_conn() |> get("/api/sources") |> json_response(200)
    assert Enum.any?(sources, &(&1["id"] == failed_source and &1["failure_count"] == 1))
  end

  defp create_source(source_type, endpoint_url) do
    conn =
      build_conn()
      |> post("/api/sources", %{
        source: %{
          source_type: source_type,
          endpoint_url: endpoint_url,
          poll_interval_seconds: 300
        }
      })

    %{"source" => %{"id" => id}} = json_response(conn, 201)
    id
  end

  defp transport(status, body),
    do: fn _request -> {:ok, %{status: status, headers: %{}, body: body}} end

  defp rss_fixture(title \\ "Initial entry", content \\ "initial content") do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
      <channel>
        <title>Local RSS fixture</title>
        <link>https://example.com/</link>
        <item>
          <guid>fixture-entry</guid>
          <title>#{title}</title>
          <link>https://example.com/articles/fixture</link>
          <content:encoded><![CDATA[<p>#{content}</p>]]></content:encoded>
          <pubDate>Sun, 07 Sep 2026 12:00:00 GMT</pubDate>
        </item>
      </channel>
    </rss>
    """
  end

  defp atom_fixture do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>Local RSSHub-style fixture</title>
      <link href="https://example.com/" rel="alternate" />
      <entry>
        <id>atom-fixture</id>
        <title>Atom fixture</title>
        <link href="https://example.com/posts/atom" rel="alternate" />
        <summary><![CDATA[<p>Atom fixture content</p>]]></summary>
        <published>2026-09-07T12:00:00+00:00</published>
      </entry>
    </feed>
    """
  end
end
