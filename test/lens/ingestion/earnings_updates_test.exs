defmodule Lens.Ingestion.EarningsUpdatesTest do
  use Lens.DataCase

  alias Lens.Content
  alias Lens.Content.Document
  alias Lens.Ingestion
  alias Lens.Ingestion.Parser

  defmodule ErrorTransport do
    @behaviour Sentry.HTTPClient
    @impl true
    def post(_, _, body) do
      send(self(), {:sentry_envelope, IO.iodata_to_binary(body)})
      {:ok, 200, [], "{}"}
    end
  end

  setup do
    Sentry.Test.Config.put(dsn: nil)

    {:ok, source} =
      Content.create_source(%{
        endpoint_url: "https://feeds.example.test/earnings.xml",
        poll_interval_seconds: 300,
        ingestion_mode: "earnings_updates"
      })

    Phoenix.PubSub.subscribe(Lens.PubSub, "earnings_feed_updates")
    %{source: source}
  end

  test "first successful read establishes a durable baseline without documents or signals", %{
    source: source
  } do
    result = ingest(source, [item("old")])
    assert Repo.aggregate(Document, :count) == 0
    assert result.update_signals == []
    assert Content.get_source!(source.id).feed_baselined_at
    refute_receive {:earnings_feed_update, _}
    assert ingest(Content.get_source!(source.id), [item("old")]).update_signals == []
  end

  test "new items emit one signal and unchanged rereads after source reload do not", %{
    source: source
  } do
    ingest(source, [item("old")])
    result = ingest(Content.get_source!(source.id), [item("old"), item("new")])

    assert [%{change: :new, source_id: id, entry: %{source_entry_id: "new"}} = signal] =
             result.update_signals

    assert id == source.id
    assert_receive {:earnings_feed_update, ^signal}
    assert ingest(Content.get_source!(source.id), [item("new")]).update_signals == []
    assert ingest(Content.get_source!(source.id), [item("old"), item("new")]).update_signals == []
    refute_receive {:earnings_feed_update, _}
    assert Repo.aggregate(Document, :count) == 0
  end

  test "visible updates retain GUID identity even when the URL or only attachment changes", %{
    source: source
  } do
    ingest(source, [item("one")])
    [signal] = ingest(source, [item("one", "/files/revised.pdf")]).update_signals
    assert signal.change == :changed

    assert signal.entry.attachments == [
             %{url: "https://example.test/files/revised.pdf", type: "application/pdf"}
           ]

    assert_receive {:earnings_feed_update, ^signal}
    assert ingest(source, [item("one", "/files/revised.pdf")]).update_signals == []

    changed =
      String.replace(item("one", "/files/revised.pdf"), "/release/one", "/release/corrected")

    assert [%{change: :changed}] = ingest(source, [changed]).update_signals
  end

  test "failed first fetch does not establish a baseline, and a later success still skips old items",
       %{source: source} do
    result = Ingestion.ingest(source, transport: fn _ -> {:error, "synthetic-private-error"} end)
    assert result.outcome == :failure
    refute Content.get_source!(source.id).feed_baselined_at
    assert Content.get_source!(source.id).last_error == nil
    assert ingest(source, [item("old")]).update_signals == []
    assert Repo.aggregate(Document, :count) == 0
  end

  test "empty successful feeds establish a baseline and malformed feeds do not advance it", %{
    source: source
  } do
    assert ingest(source, []).update_signals == []
    baseline = Content.get_source!(source.id).feed_baselined_at
    bad = Ingestion.ingest(source, transport: transport("<broken"))
    assert bad.outcome == :failure
    assert Content.get_source!(source.id).feed_baselined_at == baseline
    assert [%{change: :new}] = ingest(source, [item("new")]).update_signals
  end

  test "304 before baseline cannot consume the initial feed", %{source: source} do
    result =
      Ingestion.ingest(source,
        transport: fn request ->
          refute List.keymember?(request.headers, "if-none-match", 0)
          {:ok, %{status: 304, headers: %{}}}
        end
      )

    assert result.outcome == :failure
    refute Content.get_source!(source.id).feed_baselined_at
  end

  test "endpoint changes reset the baseline while ordinary edits retain it", %{source: source} do
    ingest(source, [item("old")])
    source = Content.get_source!(source.id)
    {:ok, source} = Content.update_source(source, %{title: "Updated subscription"})
    assert source.feed_baselined_at

    {:ok, source} =
      Content.update_source(source, %{endpoint_url: "https://feeds.example.test/other.xml"})

    refute source.feed_baselined_at
    assert ingest(source, [item("new endpoint history")]).update_signals == []
  end

  test "an exception in one subscription is reported and a different source still progresses", %{
    source: source
  } do
    result = Ingestion.ingest(source, transport: fn _ -> raise "synthetic-private-error" end)
    assert result.outcome == :failure
    assert Content.get_source!(source.id).failure_count == 1

    {:ok, healthy} =
      Content.create_source(%{
        endpoint_url: "https://feeds.example.test/healthy.xml",
        poll_interval_seconds: 300,
        ingestion_mode: "earnings_updates"
      })

    ingest(healthy, [])
    assert [%{change: :new}] = ingest(healthy, [item("new")]).update_signals
  end

  test "RSS body links and Atom enclosures survive normalization without fetching material" do
    xml = """
    <feed xmlns="http://www.w3.org/2005/Atom" xml:base="https://example.test/root/">
      <entry><id>one</id><title>Release</title><updated>2026-01-02T03:04:05Z</updated>
      <link rel="alternate" href="release"/><link rel="enclosure" href="report.pdf" type="application/pdf"/>
      <content type="html">&lt;a href="details.pdf"&gt;Details&lt;/a&gt;</content></entry>
    </feed>
    """

    assert {:ok, [entry]} = Parser.parse(xml, "https://example.test/feed.xml")
    assert entry.canonical_url == "https://example.test/root/release"

    assert entry.attachments == [
             %{url: "https://example.test/root/report.pdf", type: "application/pdf"}
           ]

    assert entry.body_links == ["https://example.test/root/details.pdf"]
    assert entry.content == "Details"
    assert entry.updated_at == ~U[2026-01-02 03:04:05Z]
  end

  test "a conflicting duplicate identity is isolated without emitting two revisions", %{
    source: source
  } do
    ingest(source, [])

    result =
      ingest(source, [item("duplicate"), item("duplicate", "/different.pdf"), item("valid")])

    assert [%{entry: %{source_entry_id: "valid"}}] = result.update_signals
    assert [%{error: "conflicting duplicate item identity"}] = result.invalid_entries
  end

  test "entries without stable identity do not block a valid new item", %{source: source} do
    ingest(source, [])
    result = ingest(source, ["<item><title>Unidentifiable</title></item>", item("valid")])
    assert [%{entry: %{source_entry_id: "valid"}}] = result.update_signals
    assert [%{error: "missing stable item identity"}] = result.invalid_entries
  end

  test "source mode changes are honored even when an older source struct is supplied", %{
    source: source
  } do
    {:ok, document_source} = Content.update_source(source, %{ingestion_mode: "document"})
    {:ok, _} = Content.update_source(document_source, %{ingestion_mode: "earnings_updates"})

    result =
      Ingestion.ingest(document_source, transport: fn _ -> raise "synthetic-private-error" end)

    assert result.outcome == :failure
    assert Content.get_source!(source.id).failure_count == 1
  end

  test "changing source mode through string API attributes resets a prior baseline", %{
    source: source
  } do
    ingest(source, [item("old")])
    {:ok, source} = Content.update_source(source, %{"ingestion_mode" => "document"})
    assert source.ingestion_mode == "document"
    refute source.feed_baselined_at
    {:ok, source} = Content.update_source(source, %{"ingestion_mode" => "earnings_updates"})
    assert ingest(source, [item("new mode history")]).update_signals == []
  end

  test "discovery failures reach Sentry without private error content", %{source: source} do
    Sentry.Test.Config.put(
      dsn: "https://public@example.test/1",
      send_result: :sync,
      dedup_events: false,
      client: ErrorTransport
    )

    result = Ingestion.ingest(source, transport: fn _ -> {:error, "synthetic-private-error"} end)
    assert result.outcome == :failure
    assert_receive {:sentry_envelope, body}
    assert body =~ "discovery"
    refute body =~ "synthetic-private-error"
    refute body =~ source.id
    refute body =~ source.endpoint_url
    assert Content.get_source!(source.id).last_error == nil
  end

  defp ingest(source, items),
    do:
      Ingestion.ingest(source,
        transport:
          transport(
            "<rss><channel><link>https://example.test</link>#{Enum.join(items)}</channel></rss>"
          )
      )

  defp transport(body), do: fn _ -> {:ok, %{status: 200, headers: %{}, body: body}} end

  defp item(id, pdf \\ "/files/original.pdf"),
    do: """
    <item><guid>#{id}</guid><link>https://example.test/release/#{URI.encode(id)}</link><title>Release</title>
    <description><![CDATA[<a href="/details/#{URI.encode(id)}.pdf">Material</a>]]></description>
    <enclosure url="#{pdf}" type="application/pdf"/></item>
    """
end
