defmodule Lens.Earnings.HTTPTest do
  use ExUnit.Case, async: true
  alias Lens.Earnings.HTTP

  test "retains exact PDF bytes and conditional request headers" do
    owner = self()

    url =
      server(fn socket, request ->
        send(owner, {:request, request})
        respond(socket, 200, "%PDF-1.7\noriginal", [{"ETag", "v1"}])
      end)

    result = HTTP.fetch(url, allowed_url?: allow(url), headers: [{"if-none-match", "v0"}])
    assert result.outcome == :success
    assert result.bytes == "%PDF-1.7\noriginal"
    assert result.headers["etag"] == "v1"
    assert result.requests == 1
    assert_receive {:request, request}
    assert String.contains?(String.downcase(request), "if-none-match: v0")
  end

  test "enforces the actual streaming limit without Content-Length" do
    url =
      server(fn socket, _ ->
        :gen_tcp.send(socket, "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n")

        for chunk <- ["%PDF-", String.duplicate("a", 64)] do
          :gen_tcp.send(socket, [Integer.to_string(byte_size(chunk), 16), "\r\n", chunk, "\r\n"])
        end

        :gen_tcp.send(socket, "0\r\n\r\n")
      end)

    result = HTTP.fetch(url, allowed_url?: allow(url), max_bytes: 16)
    assert result.failure_reason == :too_large
    assert result.bytes == nil
  end

  test "the default 20 MiB boundary applies to actual chunked PDF bytes" do
    for size <- [20_971_520, 20_971_521] do
      body = "%PDF-" <> String.duplicate("a", size - 5)

      url =
        server(fn socket, _ ->
          :gen_tcp.send(socket, [
            "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n",
            Integer.to_string(size, 16),
            "\r\n",
            body,
            "\r\n0\r\n\r\n"
          ])
        end)

      result = HTTP.fetch(url, allowed_url?: allow(url))

      if size == 20_971_520 do
        assert result.outcome == :success
        assert result.bytes == body
      else
        assert result.failure_reason == :too_large
        assert result.bytes == nil
      end
    end
  end

  test "rejects oversized advertised length without retaining partial bytes" do
    url =
      server(fn socket, _ ->
        :gen_tcp.send(socket, "HTTP/1.1 200 OK\r\nContent-Length: 99999999\r\n\r\n%PDF-small")
      end)

    assert HTTP.fetch(url, allowed_url?: allow(url)).failure_reason == :too_large
  end

  test "rejects oversized Content-Length as soon as headers arrive" do
    owner = self()

    url =
      server(fn socket, _ ->
        :gen_tcp.send(socket, "HTTP/1.1 200 OK\r\nContent-Length: 1000\r\n\r\n")
        send(owner, :oversized_headers_sent)
        Process.sleep(300)
      end)

    started = System.monotonic_time(:millisecond)
    result = HTTP.fetch(url, allowed_url?: allow(url), max_bytes: 16, timeout_ms: 1_000)

    assert_receive :oversized_headers_sent
    assert result.failure_reason == :too_large
    assert System.monotonic_time(:millisecond) - started < 250
  end

  test "distinguishes 304, HTTP failures, non-PDF and interrupted downloads" do
    for {status, body, expected} <- [
          {304, "", :not_modified},
          {503, "unavailable", :http_error},
          {200, "<html>login</html>", :non_pdf}
        ] do
      url = server(fn socket, _ -> respond(socket, status, body) end)
      result = HTTP.fetch(url, allowed_url?: allow(url))

      if expected == :not_modified,
        do: assert(result.outcome == expected),
        else: assert(result.failure_reason == expected)

      assert result.bytes == nil
      assert result.http_status == status
      assert result.requests == 1
    end

    url =
      server(fn socket, _ ->
        :gen_tcp.send(socket, "HTTP/1.1 200 OK\r\nContent-Length: 1000\r\n\r\n%PDF-partial")
      end)

    result = HTTP.fetch(url, allowed_url?: allow(url))
    assert result.failure_reason == :interrupted
    assert result.bytes == nil
  end

  test "connection failure is distinct from an interrupted response body" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)
    :gen_tcp.close(listener)
    url = "http://127.0.0.1:#{port}/"
    result = HTTP.fetch(url, allowed_url?: allow(url))
    assert result.failure_reason == :transport_error
    assert result.requests == 1
    assert result.retryable
  end

  test "validates every redirect destination before sending another request" do
    owner = self()

    target =
      server(fn socket, _ ->
        send(owner, :unexpected_fetch)
        respond(socket, 200, "%PDF-no")
      end)

    origin = server(fn socket, _ -> respond(socket, 302, "", [{"Location", target}]) end)
    result = HTTP.fetch(origin, allowed_url?: &(&1 == origin))
    assert result.failure_reason == :url_not_allowed
    assert result.requests == 1
    refute_receive :unexpected_fetch
  end

  test "missing and malformed redirect locations are explicit failures" do
    for headers <- [[], [{"Location", "https://example.test:bad/file.pdf"}]] do
      url = server(fn socket, _ -> respond(socket, 302, "", headers) end)
      result = HTTP.fetch(url, allowed_url?: allow(url))
      assert result.failure_reason == :invalid_redirect
      assert result.requests == 1
      refute result.retryable
    end
  end

  test "non HTTP redirect targets are reported as disallowed with the evaluated URL" do
    url =
      server(fn socket, _ ->
        respond(socket, 302, "", [{"Location", "mailto:test@example.com"}])
      end)

    result = HTTP.fetch(url, allowed_url?: allow(url))

    assert result.failure_reason == :url_not_allowed
    assert result.final_url == "mailto:test@example.com"
    assert result.requests == 1
  end

  test "non UTF-8 redirect locations are reported as invalid redirects" do
    url = server(fn socket, _ -> respond(socket, 302, "", [{"Location", "/bad-" <> <<255>>}]) end)

    result = HTTP.fetch(url, allowed_url?: allow(url))

    assert result.failure_reason == :invalid_redirect
    assert result.final_url == url
    assert result.requests == 1
    refute result.retryable
  end

  test "a redirect policy process failure is contained in the monitored worker" do
    url = server(fn socket, _ -> respond(socket, 302, "", [{"Location", "/next"}]) end)

    policy = fn candidate ->
      if URI.parse(candidate).path == "/next", do: exit(:policy_unavailable), else: true
    end

    result = HTTP.fetch(url, allowed_url?: policy)
    assert result.failure_reason == :transport_error
    assert result.requests == 1
    assert result.final_url == url <> "next"
    assert result.bytes == nil
  end

  test "encoded empty responses are rejected without relying on data callbacks" do
    url = server(fn socket, _ -> respond(socket, 200, "", [{"Content-Encoding", "gzip"}]) end)
    assert HTTP.fetch(url, allowed_url?: allow(url)).failure_reason == :unsupported_encoding
  end

  test "invalid URLs and raised policy errors are rejected before requesting" do
    for url <- [
          nil,
          "file:///tmp/file.pdf",
          "https://user:secret@example.test/file.pdf",
          "http://"
        ] do
      result = HTTP.fetch(url, allowed_url?: fn _ -> true end)
      assert result.failure_reason == :url_not_allowed
      assert result.requests == 0
    end

    result =
      HTTP.fetch("https://example.test/file.pdf",
        allowed_url?: fn _ -> raise "policy unavailable" end
      )

    assert result.failure_reason == :url_not_allowed
    assert result.requests == 0
  end

  test "follows bounded relative redirects and retains the final URL" do
    url =
      server(
        fn socket, request ->
          if String.starts_with?(request, "GET /next "),
            do: respond(socket, 200, "%PDF-final"),
            else: respond(socket, 302, "", [{"Location", "/next"}])
        end,
        2
      )

    result = HTTP.fetch(url, allowed_url?: allow(url))
    assert result.outcome == :success
    assert result.final_url == url <> "next"
    assert result.requests == 2
  end

  test "redirect loops have a finite request count and no automatic retries" do
    url = server(fn socket, _ -> respond(socket, 302, "", [{"Location", "/"}]) end, 2)
    result = HTTP.fetch(url, allowed_url?: allow(url), max_redirects: 1)
    assert result.failure_reason == :redirect_limit
    assert result.requests == 2
  end

  test "the total deadline includes a slow response and leaves no retained bytes" do
    url =
      server(fn socket, _ ->
        :gen_tcp.send(
          socket,
          "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\n%PDF-\r\n"
        )

        Process.sleep(300)
        :gen_tcp.send(socket, "0\r\n\r\n")
      end)

    started = System.monotonic_time(:millisecond)
    result = HTTP.fetch(url, allowed_url?: allow(url), timeout_ms: 50)
    assert result.failure_reason == :timeout
    assert System.monotonic_time(:millisecond) - started < 500
    assert result.bytes == nil
  end

  test "a response completed after the absolute deadline remains a timeout" do
    url =
      server(fn socket, _ ->
        Process.sleep(150)
        respond(socket, 200, "%PDF-late")
      end)

    result = HTTP.fetch(url, allowed_url?: allow(url), timeout_ms: 75)

    assert result.failure_reason == :timeout
    assert result.final_url == url
    assert result.requests == 1
    assert result.bytes == nil
  end

  test "worker exits are classified against the absolute deadline" do
    now = System.monotonic_time(:millisecond)
    assert Lens.Earnings.HTTPNotifications.worker_exit_reason(now - 1, now) == :transport_error
    assert Lens.Earnings.HTTPNotifications.worker_exit_reason(now + 1, now) == :timeout
  end

  test "timeout cleanup retains queued request-start accounting" do
    ref = make_ref()
    unrelated = make_ref()
    original = "https://example.test/request.pdf"
    redirected = "https://example.test/redirect.pdf"
    evaluated = "https://example.test/rejected.pdf"

    send(self(), {ref, :started, redirected, 2})
    send(self(), {ref, :evaluating, evaluated, 2})
    send(self(), {ref, :result, 0, %{final_url: evaluated, requests: 1}})
    send(self(), {unrelated, :started, original, 9})

    assert Lens.Earnings.HTTPNotifications.drain(ref, original, 0) ==
             {:result, 0, %{final_url: evaluated, requests: 1}, 2}

    assert_receive {^unrelated, :started, ^original, 9}
    refute_receive {^ref, _, _, _}, 0
  end

  test "timeout cleanup rechecks terminal notifications after the worker stops" do
    ref = make_ref()
    url = "https://example.test/file.pdf"

    assert Lens.Earnings.HTTPNotifications.drain(ref, url, 0) == {:none, url, 0}
    send(self(), {ref, :worker_exit, 123})

    assert Lens.Earnings.HTTPNotifications.drain(ref, url, 0) ==
             {:worker_exit, 123, url, 0}
  end

  test "timeout cleanup retains queued result completion timestamps" do
    ref = make_ref()
    url = "https://example.test/file.pdf"
    result = %{final_url: url, requests: 1}

    send(self(), {ref, :result, 123, result})

    assert Lens.Earnings.HTTPNotifications.drain(ref, url, 0) == {:result, 123, result, 1}
  end

  test "caller termination cancels an in-flight download and closes its socket" do
    owner = self()

    url =
      server(fn socket, _ ->
        :gen_tcp.send(
          socket,
          "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\n%PDF-\r\n"
        )

        send(owner, :stream_open)
        send(owner, {:stream_closed, :gen_tcp.recv(socket, 0, 1000)})
      end)

    caller = spawn(fn -> HTTP.fetch(url, allowed_url?: allow(url), timeout_ms: 2000) end)
    assert_receive :stream_open, 1000
    Process.exit(caller, :kill)
    assert_receive {:stream_closed, {:error, :closed}}, 1000
  end

  test "caller termination during URL policy evaluation prevents the request" do
    owner = self()

    url =
      server(fn socket, _ ->
        send(owner, :unexpected_fetch)
        respond(socket, 200, "%PDF-fake")
      end)

    caller =
      spawn(fn ->
        HTTP.fetch(url,
          allowed_url?: fn _ ->
            send(owner, {:policy_started, self()})

            receive do
              :continue -> true
            end
          end,
          timeout_ms: 2_000
        )
      end)

    assert_receive {:policy_started, policy_worker}, 1_000
    Process.exit(caller, :kill)
    send(policy_worker, :continue)

    refute_receive :unexpected_fetch, 100
  end

  test "rejects nonidentity content encoding to preserve exact original bytes" do
    url =
      server(fn socket, _ ->
        respond(socket, 200, "%PDF-fake", [{"Content-Encoding", "gzip"}])
      end)

    assert HTTP.fetch(url, allowed_url?: allow(url)).failure_reason == :unsupported_encoding
  end

  test "listing responses use the same bounded path without PDF classification" do
    url = server(fn socket, _ -> respond(socket, 200, "<a href='file.pdf'>資料</a>") end)
    result = HTTP.fetch(url, allowed_url?: allow(url), kind: :listing)
    assert result.outcome == :success
    assert String.starts_with?(result.bytes, "<a")
  end

  test "invalid bounds and missing policy send no requests" do
    assert HTTP.fetch("https://example.test/file.pdf").failure_reason == :url_not_allowed

    for opts <- [[max_bytes: 20_971_521], [timeout_ms: 0], [max_redirects: 4], [kind: :unknown]] do
      assert HTTP.fetch("https://example.test/file.pdf", opts).failure_reason == :invalid_options
    end
  end

  test "initial slow policy evaluation is contained within the total deadline" do
    started = System.monotonic_time(:millisecond)

    result =
      HTTP.fetch("https://example.test/file.pdf",
        timeout_ms: 20,
        allowed_url?: fn _ ->
          Process.sleep(200)
          false
        end
      )

    assert result.failure_reason == :timeout
    assert result.requests == 0
    assert System.monotonic_time(:millisecond) - started < 150
  end

  test "initial policy process exits are contained like redirect policy exits" do
    result =
      HTTP.fetch("https://example.test/file.pdf", allowed_url?: fn _ -> exit(:unavailable) end)

    assert result.failure_reason == :transport_error
    assert result.requests == 0
  end

  test "worker exits before the deadline retain their reason when the caller resumes late" do
    owner = self()

    caller =
      spawn(fn ->
        result =
          HTTP.fetch("https://example.test/file.pdf",
            timeout_ms: 5_000,
            allowed_url?: fn _ ->
              send(owner, {:policy_waiting, self()})

              receive do
                :continue ->
                  exit(:unavailable)
              end
            end
          )

        send(owner, {:fetch_result, result})
      end)

    assert_receive {:policy_waiting, policy_worker}, 1_000
    :erlang.suspend_process(caller)
    send(policy_worker, :continue)
    Process.sleep(5_100)
    :erlang.resume_process(caller)

    assert_receive {:fetch_result, result}, 1_000
    assert result.failure_reason == :transport_error
    assert result.requests == 0
  end

  test "an absolute expired deadline starts no request" do
    result =
      HTTP.fetch("https://example.test/file.pdf",
        deadline: System.monotonic_time(:millisecond) - 1,
        allowed_url?: fn _ -> true end
      )

    assert result.failure_reason == :timeout
    assert result.requests == 0
  end

  test "identity encoding is accepted independent of token casing and whitespace" do
    for encoding <- ["Identity", "IDENTITY", " identity "] do
      url =
        server(fn socket, _ ->
          respond(socket, 200, "%PDF-exact", [{"Content-Encoding", encoding}])
        end)

      assert HTTP.fetch(url, allowed_url?: allow(url)).bytes == "%PDF-exact"
    end
  end

  test "all repeated content-coding fields are validated before retaining listing bytes" do
    for encodings <- [["identity", "gzip"], ["gzip", "identity"], ["identity, gzip"]] do
      url =
        server(fn socket, _ ->
          respond(
            socket,
            200,
            :zlib.gzip("<html>listing</html>"),
            Enum.map(encodings, &{"Content-Encoding", &1})
          )
        end)

      result = HTTP.fetch(url, kind: :listing, allowed_url?: allow(url))
      assert result.failure_reason == :unsupported_encoding
      assert result.bytes == nil
    end

    url =
      server(fn socket, _ ->
        respond(socket, 200, "<html>listing</html>", [
          {"Content-Encoding", "identity"},
          {"Content-Encoding", "Identity"}
        ])
      end)

    assert HTTP.fetch(url, kind: :listing, allowed_url?: allow(url)).bytes ==
             "<html>listing</html>"
  end

  test "cross-origin redirects discard origin-scoped and custom credentials" do
    owner = self()

    target =
      server(fn socket, request ->
        send(owner, {:target, request})
        respond(socket, 200, "%PDF-exact")
      end)

    origin = server(fn socket, _ -> respond(socket, 302, "", [{"Location", target}]) end)

    result =
      HTTP.fetch(origin,
        allowed_url?: fn url -> url in [origin, target] end,
        headers: [
          {"Authorization", "test-secret"},
          {"Cookie", "test-cookie"},
          {"X-Api-Key", "test-key"},
          {"If-None-Match", "origin-etag"},
          {"Accept", "application/pdf"}
        ]
      )

    assert result.outcome == :success
    assert_receive {:target, request}
    request = String.downcase(request)

    for name <- ["authorization", "cookie", "x-api-key", "if-none-match"],
        do: refute(String.contains?(request, name <> ":"))

    assert String.contains?(request, "accept: application/pdf")
  end

  test "caller headers cannot override the URL authority" do
    owner = self()

    url =
      server(fn socket, request ->
        send(owner, {:request, request})
        respond(socket, 200, "%PDF-exact")
      end)

    result =
      HTTP.fetch(url,
        allowed_url?: allow(url),
        headers: [{"Host", "attacker.example"}]
      )

    assert result.outcome == :success
    assert_receive {:request, request}
    request = String.downcase(request)
    authority = URI.parse(url).host <> ":" <> to_string(URI.parse(url).port)
    assert String.contains?(request, "host: " <> authority)
    refute String.contains?(request, "attacker.example")
  end

  test "caller headers cannot set the HTTP authority pseudo-header" do
    url = server(fn socket, _ -> respond(socket, 200, "%PDF-exact") end)

    result =
      HTTP.fetch(url,
        allowed_url?: allow(url),
        headers: [{":authority", "attacker.example"}]
      )

    assert result.outcome == :success
  end

  test "changing deadlines reuse one stable Finch connection configuration" do
    before = DynamicSupervisor.count_children(Req.FinchSupervisor).active

    for timeout <- [1701, 1702, 1703] do
      url = server(fn socket, _ -> respond(socket, 200, "%PDF-exact") end)
      assert HTTP.fetch(url, allowed_url?: allow(url), timeout_ms: timeout).outcome == :success
    end

    assert DynamicSupervisor.count_children(Req.FinchSupervisor).active <= before + 1
  end

  test "a slow redirect policy reports the target without counting another request" do
    url = server(fn socket, _ -> respond(socket, 302, "", [{"Location", "/next"}]) end)

    policy = fn candidate ->
      if URI.parse(candidate).path == "/next", do: Process.sleep(300)
      true
    end

    result = HTTP.fetch(url, allowed_url?: policy, timeout_ms: 100)
    assert result.failure_reason == :timeout
    assert result.requests == 1
    assert result.final_url == url <> "next"
  end

  defp allow(url) do
    base = URI.parse(url)

    fn candidate ->
      uri = URI.parse(candidate)
      {uri.scheme, uri.host, uri.port} == {base.scheme, base.host, base.port}
    end
  end

  defp respond(socket, status, body, headers \\ []) do
    headers = [{"Content-Length", to_string(byte_size(body))}, {"Connection", "close"} | headers]

    :gen_tcp.send(socket, [
      "HTTP/1.1 #{status} OK\r\n",
      Enum.map(headers, fn {k, v} -> "#{k}: #{v}\r\n" end),
      "\r\n",
      body
    ])
  end

  defp server(handler, count \\ 1) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)

    pid =
      spawn(fn ->
        for _ <- 1..count do
          case :gen_tcp.accept(listener, 1000) do
            {:ok, socket} ->
              case :gen_tcp.recv(socket, 0, 1000) do
                {:ok, request} -> handler.(socket, request)
                _ -> :ok
              end

              :gen_tcp.close(socket)

            _ ->
              :ok
          end
        end
      end)

    on_exit(fn ->
      :gen_tcp.close(listener)
      Process.exit(pid, :kill)
    end)

    "http://127.0.0.1:#{port}/"
  end
end
