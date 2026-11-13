defmodule Lens.Ingestion.RSSNotificationTest do
  use Lens.DataCase, async: false

  alias Lens.Content
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

    :ok = :sys.resume(Scheduler)

    try do
      send(Scheduler, :poll)
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
    after
      :ok = Supervisor.terminate_child(Lens.Supervisor, Scheduler)
      {:ok, pid} = Supervisor.restart_child(Lens.Supervisor, Scheduler)
      :ok = :sys.suspend(pid)
    end
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
