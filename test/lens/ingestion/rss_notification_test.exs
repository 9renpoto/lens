defmodule Lens.Ingestion.RSSNotificationTest do
  use Lens.DataCase, async: false

  alias Lens.Content
  alias Lens.Earnings.RustFS
  alias Lens.Ingestion.{Parser, Scheduler}

  @evidence "Synthetic operating result"

  test "a scheduled input update reaches the RSS notification destination once" do
    owner = self()
    phase = start_supervised!({Agent, fn -> :baseline end})

    fixture_url =
      serve(:fixture, fn conn, _options ->
        case {conn.method, conn.request_path} do
          {"GET", "/input.xml"} ->
            base_url = "http://" <> hd(Plug.Conn.get_req_header(conn, "host"))
            rss = input_feed(base_url, Agent.get(phase, & &1))
            respond(conn, "application/rss+xml", rss)

          {"GET", "/valid"} ->
            send(owner, :valid_material_requested)
            respond(conn, "text/html", "<article>#{@evidence}</article>")

          {"GET", "/invalid"} ->
            send(owner, :invalid_material_requested)
            respond(conn, "text/html", "<aside>Unrelated material</aside>")

          {"POST", "/notifications"} ->
            {:ok, body, conn} = Plug.Conn.read_body(conn)
            send(owner, {:notification, Jason.decode!(body)})
            Plug.Conn.send_resp(conn, 204, "")
        end
      end)

    lens_url = serve(:lens, LensWeb.Endpoint)
    feed_url = lens_url <> "/feeds/earnings.rss"

    {:ok, source} =
      Content.create_source(%{
        endpoint_url: fixture_url <> "/input.xml",
        ingestion_mode: "earnings_updates",
        poll_interval_seconds: 1,
        acquisition_metadata: %{"material_origins" => [fixture_url], "html_selector" => "article"}
      })

    with_scheduler(fn ->
      baseline = await_poll(source.id)
      assert baseline.feed_baselined_at

      {seen, []} = poll_consumer(feed_url, fixture_url, MapSet.new())
      refute_received {:notification, _}

      Agent.update(phase, fn _ -> :valid end)
      assert_receive :valid_material_requested, 5_000
      valid = await_poll(source.id, baseline.last_success_at)
      {seen, [guid]} = poll_consumer(feed_url, fixture_url, seen)

      assert_receive {:notification, %{"guid" => ^guid, "url" => url, "text" => @evidence}}
      assert url == fixture_url <> "/valid"
      assert "lens:feed-update:" <> material_id = guid

      assert %Req.Response{
               status: 200,
               body: %{"material" => %{"text" => @evidence, "final_url" => ^url}}
             } = Req.get!(lens_url <> "/api/feed-materials/" <> material_id, retry: false)

      Agent.update(phase, fn _ -> :invalid end)
      assert_receive :invalid_material_requested, 5_000
      await_poll(source.id, valid.last_success_at)
      assert {^seen, []} = poll_consumer(feed_url, fixture_url, seen)
      assert [%{source_entry_id: ^guid}] = read_feed(feed_url)
      refute_received {:notification, _}
    end)
  end

  @tag skip: not match?({:unix, :linux}, :os.type())
  test "a new source publishes the first feed item's PDFs to the RSS subscriber" do
    report = File.read!("test/fixtures/first-poll-report.pdf")
    supplement = File.read!("test/fixtures/first-poll-supplement.pdf")
    phase = start_supervised!({Agent, fn -> :initial end})
    owner = self()

    fixture_url =
      serve(:fixture, fn conn, _options ->
        base_url = "http://" <> hd(Plug.Conn.get_req_header(conn, "host"))

        case conn.request_path do
          "/input.xml" ->
            rss = pdf_input_feed(base_url, Agent.get(phase, & &1))
            respond(conn, "application/rss+xml", rss)

          path ->
            send(owner, {:material_requested, path})
            bytes = if path == "/report.pdf", do: report, else: supplement
            respond(conn, "application/pdf", bytes)
        end
      end)

    configure_pdf_storage()
    lens_url = serve(:lens, LensWeb.Endpoint)
    configure_output_origin(lens_url)
    feed_url = lens_url <> "/feeds/earnings.rss"
    assert read_feed(feed_url) == []

    assert %{status: 201, body: %{"target" => %{"id" => issuer_id}}} =
             Req.post!(lens_url <> "/api/targets",
               json: %{
                 target: %{
                   security_code: "fixture-issuer",
                   display_name: "Example Issuer",
                   market: "Example Market",
                   sector: "Example Sector"
                 }
               },
               retry: false
             )

    assert %{status: 201, body: %{"source" => %{"id" => source_id}}} =
             Req.post!(lens_url <> "/api/sources",
               json: %{
                 source: %{
                   endpoint_url: fixture_url <> "/input.xml",
                   earnings_issuer_id: issuer_id,
                   ingestion_mode: "earnings_updates",
                   poll_interval_seconds: 1,
                   acquisition_metadata: %{"material_origins" => [fixture_url]}
                 }
               },
               retry: false
             )

    with_scheduler(fn ->
      initial = await_poll(source_id)
      assert initial.feed_baselined_at
      assert_receive {:material_requested, "/report.pdf"}
      assert_receive {:material_requested, "/supplement.pdf"}
      refute_received {:material_requested, "/baseline.pdf"}

      entries = read_feed(feed_url)
      assert length(entries) == 2
      initial_guids = MapSet.new(entries, & &1.source_entry_id)
      assert MapSet.size(initial_guids) == 2

      originals =
        Map.new(entries, fn entry ->
          assert entry.title == "first"
          assert "lens:pdf-update:" <> _ = entry.source_entry_id
          assert String.starts_with?(entry.entry_url, lens_url <> "/api/earnings/originals/")
          label = if entry.content =~ "決算補足資料", do: :supplement, else: :report
          assert %{status: 200, body: bytes} = Req.get!(entry.entry_url, retry: false)
          {label, bytes}
        end)

      assert originals == %{report: report, supplement: supplement}

      unchanged = await_poll(source_id, initial.last_success_at)
      assert read_feed(feed_url) == entries
      refute_received {:material_requested, _}

      Agent.update(phase, fn _ -> :later end)
      assert_receive {:material_requested, "/later.pdf"}, 5_000
      await_poll(source_id, unchanged.last_success_at)

      updated_entries = read_feed(feed_url)
      assert length(updated_entries) == 3
      assert Enum.all?(entries, &(&1 in updated_entries))

      assert [%{title: "later", entry_url: original_url}] =
               Enum.reject(updated_entries, &MapSet.member?(initial_guids, &1.source_entry_id))

      assert %{status: 200, body: ^supplement} = Req.get!(original_url, retry: false)
      refute_received {:material_requested, _}
    end)
  end

  defp with_scheduler(run) do
    :ok = :sys.resume(Scheduler)

    try do
      send(Scheduler, :poll)
      run.()
    after
      :ok = Supervisor.terminate_child(Lens.Supervisor, Scheduler)
      {:ok, pid} = Supervisor.restart_child(Lens.Supervisor, Scheduler)
      :ok = :sys.suspend(pid)
    end
  end

  defp pdf_input_feed(url, phase) do
    first =
      """
      <item><guid>first</guid><title>first</title><link>#{url}/report.pdf</link>
      <enclosure url="#{url}/supplement.pdf" type="application/pdf"/></item>
      """

    baseline =
      "<item><guid>baseline</guid><title>baseline</title><link>#{url}/baseline.pdf</link></item>"

    later = "<item><guid>later</guid><title>later</title><link>#{url}/later.pdf</link></item>"
    items = if phase == :later, do: [later, first, baseline], else: [first, baseline]
    "<rss version=\"2.0\"><channel>#{items}</channel></rss>"
  end

  defp configure_pdf_storage do
    objects = start_supervised!({Agent, fn -> %{} end}, id: :pdf_objects)

    endpoint =
      serve(:pdf_storage, fn conn, _options ->
        key = conn.request_path

        case conn.method do
          "PUT" ->
            assert Plug.Conn.get_req_header(conn, "if-none-match") == ["*"]
            {:ok, bytes, conn} = Plug.Conn.read_body(conn)

            status =
              Agent.get_and_update(objects, fn stored ->
                status = if Map.has_key?(stored, key), do: 412, else: 200
                {status, Map.put_new(stored, key, bytes)}
              end)

            Plug.Conn.send_resp(conn, status, "")

          "GET" ->
            case Agent.get(objects, &Map.fetch(&1, key)) do
              {:ok, bytes} -> respond(conn, "application/pdf", bytes)
              :error -> Plug.Conn.send_resp(conn, 404, "")
            end
        end
      end)

    previous = Application.fetch_env!(:lens, RustFS)
    Application.put_env(:lens, RustFS, Keyword.put(previous, :endpoint, endpoint))
    on_exit(fn -> Application.put_env(:lens, RustFS, previous) end)
  end

  defp configure_output_origin(url) do
    endpoint = LensWeb.Endpoint
    previous = Application.fetch_env!(:lens, endpoint)
    origin = url |> URI.parse() |> Map.take([:scheme, :host, :port]) |> Map.to_list()
    :ok = endpoint.config_change([{endpoint, Keyword.put(previous, :url, origin)}], [])
    on_exit(fn -> endpoint.config_change([{endpoint, previous}], []) end)
  end

  defp serve(id, plug) do
    spec = Supervisor.child_spec({Bandit, plug: plug, ip: {127, 0, 0, 1}, port: 0}, id: id)
    pid = start_supervised!(spec)
    {:ok, {{127, 0, 0, 1}, port}} = ThousandIsland.listener_info(pid)
    "http://127.0.0.1:#{port}"
  end

  defp respond(conn, content_type, body) do
    conn
    |> Plug.Conn.put_resp_content_type(content_type)
    |> Plug.Conn.send_resp(200, body)
  end

  defp input_feed(base_url, phase) do
    paths =
      case phase do
        :baseline -> []
        :valid -> ["valid"]
        :invalid -> ["valid", "invalid"]
      end

    items =
      Enum.map_join(paths, fn path ->
        "<item><guid>#{path}</guid><title>#{path}</title><link>#{base_url}/#{path}</link></item>"
      end)

    "<rss version=\"2.0\"><channel>#{items}</channel></rss>"
  end

  defp await_poll(source_id, previous \\ nil, attempts \\ 200)

  defp await_poll(_source_id, _previous, 0), do: flunk("scheduled source poll did not complete")

  defp await_poll(source_id, previous, attempts) do
    source = Content.get_source!(source_id)

    if source.last_success_at && source.last_success_at != previous &&
         :sys.get_state(Scheduler).running == 0 do
      source
    else
      Process.sleep(25)
      await_poll(source_id, previous, attempts - 1)
    end
  end

  defp poll_consumer(feed_url, fixture_url, seen) do
    new_guids =
      for entry <- read_feed(feed_url), not MapSet.member?(seen, entry.source_entry_id) do
        payload = %{
          guid: entry.source_entry_id,
          url: entry.entry_url,
          text: entry.raw_content |> Floki.parse_fragment!() |> Floki.text()
        }

        assert %{status: 204} =
                 Req.post!(fixture_url <> "/notifications", json: payload, retry: false)

        entry.source_entry_id
      end

    {MapSet.union(seen, MapSet.new(new_guids)), new_guids}
  end

  defp read_feed(url) do
    assert %{status: 200, body: body} = Req.get!(url, decode_body: false, retry: false)
    assert {:ok, entries} = Parser.parse(body, url)
    entries
  end
end
