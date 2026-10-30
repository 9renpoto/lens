defmodule Lens.Ingestion.MaterialsTest do
  use Lens.DataCase

  import Phoenix.ConnTest
  @endpoint LensWeb.Endpoint

  alias Lens.Content
  alias Lens.Earnings.{Acquisition, Original, Release, RustFS}
  alias Lens.Ingestion.{Material, Materials}

  @pdf "%PDF-1.7\nsynthetic report"

  defmodule ErrorTransport do
    @behaviour Sentry.HTTPClient
    @impl true
    def post(_, _, body) do
      send(self(), {:sentry_envelope, IO.iodata_to_binary(body)})
      {:ok, 200, [], "{}"}
    end
  end

  defmodule TextExtractor do
    def extract(_, _), do: {:ok, %{text: "架空の PDF 利益", version: "fixture"}}
  end

  defmodule EmptyExtractor do
    def extract(_, _), do: {:ok, %{text: "  ", version: "fixture"}}
  end

  setup do
    Sentry.Test.Config.put(dsn: nil)
    :ok
  end

  test "retains derived HTML text and navigable references without original markup" do
    url =
      server(fn _ ->
        html(
          "<article data-note='unretained-marker'><h1>Results</h1><p>Revenue increased.</p><h2 id='detail'>Details</h2><a href='/source#table'>Source table</a><script src='/asset.js'>private-script</script></article>"
        )
      end)

    source = source(url)
    result = Materials.acquire(signal(source, url <> "/release"))
    assert result.errors == []
    assert [%{kind: "html", text: text} = material] = result.materials
    assert text =~ "Revenue increased."
    refute text =~ "private-script"
    refute inspect(material) =~ "unretained-marker"
    refute inspect(material) =~ "<article"
    assert material.content_hash == digest(text)
    assert material.requested_url == url <> "/release"
    assert material.final_url == material.requested_url
    assert material.acquired_at

    assert [%{"url" => link, "anchor_text" => "Source table", "fragment" => "table"}] =
             material.provenance["links"]

    assert link == url <> "/source#table"
    assert material.provenance["headings"] == ["Results", "Details"]

    assert [%{"fragment" => "detail", "url" => anchor_url, "quote" => "Details"}] =
             material.provenance["anchors"]

    assert anchor_url == url <> "/release#detail"
    assert Repo.get!(Material, material.id).text == text
    assert Repo.aggregate(Original, :count) == 0
    refute_receive {:request, "/asset.js"}
  end

  test "keeps only a fragment-selected release from a multi-release listing" do
    url =
      server(fn _ ->
        html(
          "<section id='current'><h1>Results</h1><p>Current result.</p></section><section id='old'>Historical release.</section>"
        )
      end)

    result = Materials.acquire(signal(source(url), url <> "/listing#current"))
    assert [%{text: text, provenance: provenance}] = result.materials
    assert result.errors == []
    assert text =~ "Current result."
    refute text =~ "Historical release"
    assert provenance["fragment"] == "current"
  end

  test "ambiguous listings do not crawl historical PDFs" do
    url =
      server(fn _ ->
        html(
          "<article><h1>Archive</h1><a href='/old.pdf'>Old</a><a href='/other.pdf'>Other</a></article>"
        )
      end)

    result = Materials.acquire(signal(source(url), url <> "/listing"))
    assert result.materials == []
    assert [%{stage: :association, reason: :ambiguous_material}] = result.errors
    assert_receive {:request, "/listing"}
    refute_receive {:request, "/old.pdf"}
    refute_receive {:request, "/other.pdf"}
  end

  test "explicit attachments and scoped page PDF links retain verified originals without invented identities" do
    url =
      server(fn
        "/release" ->
          html(
            "<article><h1>Results</h1><p>New result.</p><a href='/report.pdf#page=2'>Report</a></article>"
          )

        "/report.pdf" ->
          pdf()
      end)

    result = Materials.acquire(signal(source(url), url <> "/release"), rustfs: storage())
    assert result.errors == []
    assert [%{kind: "html"}, %{kind: "pdf", original_id: id} = material] = result.materials
    assert Repo.get!(Original, id).sha256 == digest(@pdf)
    assert material.text == nil
    assert material.requested_url == url <> "/report.pdf#page=2"
    assert material.content_hash == digest(@pdf)
    assert Repo.aggregate(Acquisition, :count) == 0
    assert Repo.aggregate(Release, :count) == 0
    assert_receive {:request, "/report.pdf"}
    refute_receive {:request, "/report.pdf"}
  end

  test "a direct PDF with a non-PDF URL is retained by response type and bytes" do
    url = server(fn _ -> pdf() end)
    result = Materials.acquire(signal(source(url), url <> "/download?id=one"), rustfs: storage())
    assert result.errors == []
    assert [%{kind: "pdf", original_id: id}] = result.materials
    assert Repo.get!(Original, id).byte_size == byte_size(@pdf)
  end

  test "explicit feed attachments are processed even when a listing cannot be associated" do
    url =
      server(fn
        "/listing" -> html("<h1>Archive</h1><a href='/old.pdf'>Old</a>")
        "/current.pdf" -> pdf()
      end)

    input = signal(source(url), url <> "/listing")

    input =
      put_in(input.entry.attachments, [%{url: url <> "/current.pdf", type: "application/pdf"}])

    result = Materials.acquire(input, rustfs: storage())
    assert [%{kind: "pdf"}] = result.materials
    assert [%{stage: :association}] = result.errors
    refute_receive {:request, "/old.pdf"}
  end

  test "denies unconfigured origins and redirects outside the reviewed policy" do
    url = server(fn _ -> {302, [{"Location", "https://blocked.example.test/report.pdf"}], ""} end)
    source = source(url)
    {:ok, unconfigured} = Content.update_source(source, %{acquisition_metadata: %{}})

    assert [%{reason: :material_policy_required}] =
             Materials.acquire(signal(unconfigured, url)).errors

    refute_receive {:request, _}

    {:ok, configured} =
      Content.update_source(unconfigured, %{acquisition_metadata: %{"material_origins" => [url]}})

    assert [%{reason: :url_not_allowed}] = Materials.acquire(signal(configured, url)).errors
    assert_receive {:request, "/"}
  end

  test "storage verification failures cannot create successful material or original records" do
    url = server(fn _ -> pdf() end)

    result =
      Materials.acquire(signal(source(url), url <> "/report.pdf"), rustfs: storage("wrong bytes"))

    assert result.materials == []
    assert [%{stage: :acquisition, reason: :integrity_error}] = result.errors
    assert Repo.aggregate(Original, :count) == 0
  end

  test "unsupported types are errors and independent acquisitions still succeed" do
    url =
      server(fn
        "/sheet.xlsx" ->
          {200,
           [
             {"Content-Type", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"}
           ], "synthetic binary"}

        _ ->
          html("<article><h1>Results</h1><p>Healthy.</p></article>")
      end)

    source = source(url)

    assert [%{reason: :unsupported_format}] =
             Materials.acquire(signal(source, url <> "/sheet.xlsx")).errors

    assert [%{kind: "html"}] = Materials.acquire(signal(source, url <> "/healthy")).materials
  end

  test "indexes acquired HTML text with its material provenance" do
    url = server(fn _ -> html("<article><h1>Results</h1><p>検索対象の架空売上高</p></article>") end)
    source = source(url)

    feed = fn items ->
      fn _ ->
        {:ok, %{status: 200, headers: %{}, body: "<rss><channel>#{items}</channel></rss>"}}
      end
    end

    Lens.Ingestion.ingest(source, transport: feed.(""))
    item = "<item><guid>new</guid><title>Results</title><link>#{url}/release</link></item>"
    assert %{materials: [material]} = Lens.Ingestion.ingest(source, transport: feed.(item))
    assert {:ok, results} = Lens.Search.search("架空売上高")
    assert Enum.any?(results, &(&1.id == material.id and &1.canonical_url == material.final_url))
  end

  test "indexing failure reaches Sentry and does not block another material" do
    Sentry.Test.Config.put(
      dsn: "https://public@example.test/1",
      send_result: :sync,
      dedup_events: false,
      client: ErrorTransport
    )

    url = server(fn _ -> html("<article><h1>Results</h1><p>安全な資料本文</p></article>") end)
    source = source(url)
    [first] = Materials.acquire(signal(source, url <> "/first")).materials
    [second] = Materials.acquire(signal(source, url <> "/second")).materials
    assert [] == Lens.Ingestion.MaterialIndex.index_many([first])

    assert [%{stage: :indexing, reason: :persistence_failed}] =
             Lens.Ingestion.MaterialIndex.index_many([first, second])

    assert_receive {:sentry_envelope, body}
    assert body =~ "indexing"
    refute body =~ url
    refute body =~ "安全な資料本文"
    assert {:ok, results} = Lens.Search.search("安全な資料本文")
    assert length(results) == 2
    assert :ok = Lens.Search.rebuild(batch_size: 1)
    assert {:ok, results} = Lens.Search.search("安全な資料本文")
    assert length(results) == 2
  end

  test "material provenance is available from its search result" do
    url = server(fn _ -> html("<article><h1>Results</h1><p>出典対応の本文</p></article>") end)
    [material] = Materials.acquire(signal(source(url), url <> "/release")).materials
    assert [] == Lens.Ingestion.MaterialIndex.index_many([material])
    assert {:ok, [result]} = Lens.Search.search("出典対応の本文")
    response = build_conn() |> get(result.provenance_url) |> json_response(200)
    assert response["material"]["id"] == material.id
    assert response["material"]["final_url"] == material.final_url
    assert response["material"]["content_hash"] == material.content_hash
    assert response["material"]["text"] =~ "出典対応の本文"
  end

  test "indexes retained PDF text without inventing a release" do
    url = server(fn _ -> pdf() end)
    source = source(url)

    feed = fn items ->
      fn _ ->
        {:ok, %{status: 200, headers: %{}, body: "<rss><channel>#{items}</channel></rss>"}}
      end
    end

    Lens.Ingestion.ingest(source, transport: feed.(""))
    item = "<item><guid>pdf</guid><title>Results</title><link>#{url}/report.pdf</link></item>"

    assert %{materials: [material], material_errors: []} =
             Lens.Ingestion.ingest(source,
               transport: feed.(item),
               materials: [rustfs: storage(), extractor: TextExtractor]
             )

    assert {:ok, [result]} = Lens.Search.search("PDF 利益")
    assert result.id == material.id
    assert result.original_id == material.original_id
    assert Repo.aggregate(Release, :count) == 0
  end

  test "empty PDF extraction reports an error and does not prevent independent HTML indexing" do
    Sentry.Test.Config.put(
      dsn: "https://public@example.test/1",
      send_result: :sync,
      dedup_events: false,
      client: ErrorTransport
    )

    url =
      server(fn
        "/report.pdf" -> pdf()
        _ -> html("<article><h1>Results</h1><p>独立した検索可能本文</p></article>")
      end)

    source = source(url)

    feed = fn items ->
      fn _ ->
        {:ok, %{status: 200, headers: %{}, body: "<rss><channel>#{items}</channel></rss>"}}
      end
    end

    Lens.Ingestion.ingest(source, transport: feed.(""))

    items =
      "<item><guid>pdf</guid><link>#{url}/report.pdf</link></item><item><guid>html</guid><title>Results</title><link>#{url}/html</link></item>"

    result =
      Lens.Ingestion.ingest(source,
        transport: feed.(items),
        materials: [rustfs: storage(), extractor: EmptyExtractor]
      )

    assert [%{stage: :extraction, reason: :invalid_text}] = result.material_errors
    assert_receive {:sentry_envelope, body}
    assert body =~ "extraction"
    refute body =~ url
    refute body =~ "独立した検索可能本文"
    assert {:ok, [_]} = Lens.Search.search("独立した検索可能本文")
  end

  test "scheduled ingestion acquires only later items and preserves RSS fragments" do
    url =
      server(fn _ ->
        html(
          "<section id='current'><h1>Results</h1><p>Current result.</p></section><p>Historical.</p>"
        )
      end)

    source = source(url)

    feed = fn items ->
      fn _ ->
        {:ok, %{status: 200, headers: %{}, body: "<rss><channel>#{items}</channel></rss>"}}
      end
    end

    first = Lens.Ingestion.ingest(source, transport: feed.(""))
    assert first.materials == []

    item =
      "<item><guid>new</guid><title>Results</title><link>#{url}/listing#current</link></item>"

    result = Lens.Ingestion.ingest(source, transport: feed.(item))
    assert result.material_errors == []
    assert [%{kind: "html", requested_url: requested, text: text}] = result.materials
    assert requested == url <> "/listing#current"
    refute text =~ "Historical"
    assert_receive {:request, "/listing"}
    assert Lens.Ingestion.ingest(source, transport: feed.(item)).materials == []
    refute_receive {:request, _}
    assert Repo.aggregate(Lens.Content.Document, :count) == 0
  end

  test "a configured HTML scope must match exactly one element" do
    url =
      server(fn _ ->
        html(
          "<div id='current'><h2>Result</h2><p>Selected.</p></div><div id='old'>Historical.</div>"
        )
      end)

    source = source(url)

    {:ok, source} =
      Content.update_source(source, %{
        acquisition_metadata: %{"material_origins" => [url], "html_selector" => "#current"}
      })

    assert [%{text: text}] = Materials.acquire(signal(source, url)).materials
    assert text =~ "Selected."
    refute text =~ "Historical"

    {:ok, source} =
      Content.update_source(source, %{
        acquisition_metadata: %{"material_origins" => [url], "html_selector" => "div"}
      })

    assert [%{reason: :ambiguous_material}] = Materials.acquire(signal(source, url)).errors
  end

  test "identical PDFs share an original while keeping separate source observations" do
    one = server(fn _ -> pdf() end)
    two = server(fn _ -> pdf() end)
    [a] = Materials.acquire(signal(source(one), one), rustfs: storage()).materials
    [b] = Materials.acquire(signal(source(two), two), rustfs: storage()).materials
    assert a.original_id == b.original_id
    refute a.id == b.id
    refute a.source_id == b.source_id
    assert Repo.aggregate(Original, :count) == 1
  end

  test "known HTML responses obey the 2 MiB limit and request limits are enforced" do
    url = server(fn _ -> html(String.duplicate("x", 2_097_153)) end)
    result = Materials.acquire(signal(source(url), url))
    assert result.materials == []
    assert [%{reason: :too_large}] = result.errors

    url =
      server(fn
        "/release" -> html("<article><h1>Results</h1><a href='/report.pdf'>Report</a></article>")
        "/report.pdf" -> pdf()
      end)

    result = Materials.acquire(signal(source(url), url <> "/release"), max_materials: 1)
    assert [%{kind: "html"}] = result.materials
    assert [%{reason: :too_many_materials}] = result.errors
    refute_receive {:request, "/report.pdf"}
  end

  test "a large direct PDF with no suffix is not constrained by the HTML limit" do
    bytes = "%PDF-" <> String.duplicate("x", 2_097_152)
    url = server(fn _ -> {200, [{"Content-Type", "application/pdf"}], bytes} end)
    result = Materials.acquire(signal(source(url), url <> "/download"), rustfs: storage(bytes))
    assert result.errors == []
    assert [%{kind: "pdf", byte_size: size}] = result.materials
    assert size == byte_size(bytes)
  end

  test "unsupported attachment errors do not block an independently identifiable HTML body" do
    url = server(fn _ -> html("<article><h1>Results</h1><p>Valid body.</p></article>") end)
    input = signal(source(url), url)

    input =
      put_in(input.entry.attachments, [
        %{url: url <> "/sheet.xlsx", type: "application/vnd.ms-excel"}
      ])

    result = Materials.acquire(input)
    assert [%{kind: "html"}] = result.materials
    assert [%{reason: :unsupported_format}] = result.errors
    refute_receive {:request, "/sheet.xlsx"}
  end

  test "a matching generic title cannot authorize crawling multiple historical PDFs" do
    url =
      server(fn _ ->
        html(
          "<article><h1>Results</h1><a href='/old.pdf'>Old</a><a href='/other.pdf'>Other</a></article>"
        )
      end)

    result = Materials.acquire(signal(source(url), url <> "/listing"))
    assert result.materials == []
    assert [%{reason: :ambiguous_material}] = result.errors
    refute_receive {:request, "/old.pdf"}
    refute_receive {:request, "/other.pdf"}
  end

  test "redirected pages resolve associated links against the final response URL" do
    url =
      server(fn
        "/start" ->
          {302, [{"Location", "/pages/current"}], ""}

        "/pages/current" ->
          html("<article><h1>Results</h1><a href='report.pdf#page=2'>Report</a></article>")

        "/pages/report.pdf" ->
          pdf()
      end)

    result = Materials.acquire(signal(source(url), url <> "/start"), rustfs: storage())
    assert result.errors == []

    assert [
             %{kind: "html", final_url: final, requests: 2},
             %{kind: "pdf", requested_url: pdf_url}
           ] = result.materials

    assert final == url <> "/pages/current"
    assert pdf_url == url <> "/pages/report.pdf#page=2"
  end

  test "timeout does not prevent a later independent acquisition" do
    url =
      server(fn
        "/slow" ->
          Process.sleep(100)
          html("late")

        "/healthy" ->
          html("<article><h1>Results</h1><p>Healthy.</p></article>")
      end)

    source = source(url)

    assert [%{reason: :timeout}] =
             Materials.acquire(signal(source, url <> "/slow"), timeout_ms: 10).errors

    assert [%{kind: "html"}] = Materials.acquire(signal(source, url <> "/healthy")).materials
  end

  test "acquisition errors reach Sentry without source identifiers or provider content" do
    Sentry.Test.Config.put(
      dsn: "https://public@example.test/1",
      send_result: :sync,
      dedup_events: false,
      client: ErrorTransport
    )

    url = server(fn _ -> {503, [{"Content-Type", "text/html"}], "synthetic-provider-detail"} end)
    source = source(url)
    result = Materials.acquire(signal(source, url))
    assert result.materials == []
    assert [%{reason: :http_error}] = result.errors
    assert_receive {:sentry_envelope, body}
    assert body =~ "acquisition"
    refute body =~ url
    refute body =~ source.id
    refute body =~ "synthetic-provider-detail"
    assert Repo.aggregate(Material, :count) == 0
  end

  test "feed attachment and body reference fragments remain navigable" do
    xml =
      "<rss><channel><item><guid>one</guid><link>https://example.test/release</link><description>&lt;a href='report.pdf#table'&gt;Table&lt;/a&gt;</description><enclosure url='report.pdf#page=2' type='application/pdf'/></item></channel></rss>"

    assert {:ok, [entry]} = Lens.Ingestion.Parser.parse(xml, "https://example.test/feed")
    assert [%{url: "https://example.test/report.pdf#page=2"}] = entry.attachments
    assert entry.body_links == ["https://example.test/report.pdf#table"]
  end

  test "a fragment introduced by a redirect identifies the body scope" do
    url =
      server(fn
        "/start" -> {302, [{"Location", "/listing#current"}], ""}
        "/listing" -> html("<section id='current'><p>Current.</p></section><p>Historical.</p>")
      end)

    result = Materials.acquire(signal(source(url), url <> "/start"))
    assert result.errors == []
    assert [%{text: "Current.", provenance: %{"fragment" => "current"}}] = result.materials
  end

  test "an explicit redirect fragment overrides the original entry fragment" do
    url =
      server(fn
        "/start" ->
          {302, [{"Location", "/listing#current"}], ""}

        "/listing" ->
          html(
            "<section id='old'><p>Historical.</p></section><section id='current'><p>Current.</p></section>"
          )
      end)

    result = Materials.acquire(signal(source(url), url <> "/start#old"))
    assert result.errors == []
    assert [%{text: "Current.", provenance: %{"fragment" => "current"}}] = result.materials
  end

  test "the entry fragment remains the fallback when a redirect has none" do
    url =
      server(fn
        "/start" ->
          {302, [{"Location", "/listing"}], ""}

        "/listing" ->
          html("<section id='current'><p>Current.</p></section><p>Historical.</p>")
      end)

    result = Materials.acquire(signal(source(url), url <> "/start#current"))
    assert result.errors == []
    assert [%{text: "Current.", provenance: %{"fragment" => "current"}}] = result.materials
  end

  test "table cells keep financial figures separate in retained text and source quotes" do
    url =
      server(fn _ ->
        html(
          "<article><h1>Results</h1><table id='figures'><tr><th>Revenue</th><th>Profit</th></tr><tr><td>100</td><td>200</td></tr><tr><td>売上<span>高</span></td><td>300</td></tr></table></article>"
        )
      end)

    result = Materials.acquire(signal(source(url), url))
    assert result.errors == []
    assert [%{text: text, provenance: %{"anchors" => [anchor]}} = material] = result.materials
    assert text =~ ~r/Revenue\s+Profit/
    assert text =~ ~r/100\s+200/
    assert text =~ ~r/売上高\s+300/
    refute text =~ "100200"
    assert anchor["quote"] =~ "100 200"
    assert Repo.get!(Material, material.id).text == text
  end

  test "inline elements preserve Japanese words and source link labels" do
    url =
      server(fn _ ->
        html(
          "<article><h1>Results</h1><p>売上<span>高</span>は増加しました。</p><a href='/detail'>出典<span>詳細</span></a></article>"
        )
      end)

    result = Materials.acquire(signal(source(url), url))
    assert result.errors == []
    assert [%{text: text, provenance: %{"links" => [link]}}] = result.materials
    assert text =~ "売上高は増加しました。"
    assert link["anchor_text"] == "出典詳細"
  end

  test "inline heading elements still match the feed title" do
    url = server(fn _ -> html("<article><h1>Res<span>ults</span></h1><p>Body.</p></article>") end)
    assert [%{text: text}] = Materials.acquire(signal(source(url), url)).materials
    assert text =~ "Results"
  end

  defp source(url) do
    {:ok, source} =
      Content.create_source(%{
        endpoint_url: url <> "/feed",
        ingestion_mode: "earnings_updates",
        poll_interval_seconds: 300,
        acquisition_metadata: %{"material_origins" => [url]}
      })

    source
  end

  defp signal(source, url),
    do: %{
      source_id: source.id,
      item_key: digest(url),
      change: :new,
      entry: %{
        source_entry_id: "synthetic-item",
        canonical_url: String.split(url, "#") |> hd(),
        entry_url: url,
        title: "Results",
        attachments: [],
        body_links: [],
        raw_content: nil,
        feed_fingerprint: digest("feed")
      }
    }

  defp storage(read_bytes \\ @pdf) do
    {:ok, client} =
      RustFS.new(
        endpoint: "https://storage.example.test",
        bucket: "synthetic",
        access_key_id: "test",
        secret_access_key: "test"
      )

    %{
      client
      | request:
          Req.new(
            retry: false,
            plug: fn conn ->
              case conn.method do
                "PUT" ->
                  assert Plug.Conn.get_req_header(conn, "if-none-match") == ["*"]
                  Plug.Conn.send_resp(conn, 200, "")

                "GET" ->
                  Plug.Conn.send_resp(conn, 200, read_bytes)
              end
            end
          )
    }
  end

  defp html(body), do: {200, [{"Content-Type", "text/html; charset=utf-8"}], body}
  defp pdf, do: {200, [{"Content-Type", "application/pdf"}], @pdf}
  defp digest(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)

  defp server(handler) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}, reuseaddr: true])

    {:ok, {_, port}} = :inet.sockname(listener)
    owner = self()
    spawn(fn -> serve(listener, handler, owner) end)
    on_exit(fn -> :gen_tcp.close(listener) end)
    "http://127.0.0.1:#{port}"
  end

  defp serve(listener, handler, owner) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        {:ok, request} = :gen_tcp.recv(socket, 0, 2000)
        [_, path | _] = String.split(request, " ")
        send(owner, {:request, path})
        {status, headers, body} = handler.(path)
        headers = Enum.map(headers, fn {k, v} -> "#{k}: #{v}\r\n" end)

        :gen_tcp.send(socket, [
          "HTTP/1.1 #{status} Response\r\n",
          headers,
          "Content-Length: #{byte_size(body)}\r\nConnection: close\r\n\r\n",
          body
        ])

        :gen_tcp.close(socket)
        serve(listener, handler, owner)

      _ ->
        :ok
    end
  end
end
