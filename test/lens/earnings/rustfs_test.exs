defmodule Lens.Earnings.RustFSTest do
  use ExUnit.Case, async: true

  alias Lens.Earnings.RustFS
  import Plug.Conn

  @bytes <<"%PDF-1.7\n", 0, 255, 13, 10, "original">>
  @limit 20_971_520

  test "creates only at the content key and verifies the exact stored bytes" do
    owner = self()
    reference = reference(@bytes)

    client =
      client(fn conn ->
        send(owner, {:request, conn.method, conn.request_path, conn.req_headers})

        case conn.method do
          "PUT" ->
            assert Req.Test.raw_body(conn) == @bytes
            assert get_req_header(conn, "if-none-match") == ["*"]
            send_resp(conn, 200, "")

          "GET" ->
            conn |> put_resp_header("content-type", "application/pdf") |> send_resp(200, @bytes)
        end
      end)

    assert RustFS.put(client, @bytes) == {:ok, reference}
    path = "/lens-originals/" <> reference.key
    assert_receive {:request, "PUT", ^path, headers}
    assert {"content-type", "application/pdf"} in headers

    assert Enum.any?(headers, fn {key, value} ->
             key == "authorization" and String.starts_with?(value, "AWS4-HMAC-SHA256 ")
           end)

    assert_receive {:request, "GET", ^path, _}
  end

  test "reuses an existing key only after verifying its bytes" do
    client =
      client(fn conn ->
        case conn.method do
          "PUT" -> send_resp(conn, 412, "already exists")
          "GET" -> send_resp(conn, 200, @bytes)
        end
      end)

    assert RustFS.put(client, @bytes) == {:ok, reference(@bytes)}
  end

  test "changed contents receive separate stable keys" do
    client =
      client(fn conn ->
        case conn.method do
          "PUT" ->
            send_resp(conn, 200, "")

          "GET" ->
            bytes =
              if conn.request_path == "/lens-originals/" <> reference(@bytes).key,
                do: @bytes,
                else: @bytes <> "changed"

            send_resp(conn, 200, bytes)
        end
      end)

    assert {:ok, first} = RustFS.put(client, @bytes)
    assert {:ok, second} = RustFS.put(client, @bytes <> "changed")
    assert first.key != second.key
    assert first.key == "earnings/originals/sha256/" <> first.sha256 <> ".pdf"
    assert second.key == "earnings/originals/sha256/" <> second.sha256 <> ".pdf"
  end

  test "returns raw bytes without decoding or decompressing them" do
    client =
      client(fn conn ->
        conn
        |> put_resp_header("content-type", "application/json")
        |> send_resp(200, @bytes)
      end)

    assert RustFS.get(client, reference(@bytes)) == {:ok, @bytes}
  end

  test "corrupt existing objects are never overwritten" do
    owner = self()

    client =
      client(fn conn ->
        send(owner, {:method, conn.method})

        case conn.method do
          "PUT" -> send_resp(conn, 412, "")
          "GET" -> send_resp(conn, 200, :binary.copy("x", byte_size(@bytes)))
        end
      end)

    assert RustFS.put(client, @bytes) == {:error, :integrity_error}
    assert_receive {:method, "PUT"}
    assert_receive {:method, "GET"}
    refute_receive {:method, "PUT"}
  end

  test "a successful write is not complete when retrieved bytes are wrong or missing" do
    for {status, body, reason} <- [{200, "wrong", :integrity_error}, {404, "", :not_found}] do
      client =
        client(fn conn ->
          if conn.method == "PUT",
            do: send_resp(conn, 200, ""),
            else: send_resp(conn, status, body)
        end)

      assert RustFS.put(client, @bytes) == {:error, reason}
    end
  end

  test "get rejects size or hash mismatches even when ETag matches" do
    for bytes <- ["short", :binary.copy("x", byte_size(@bytes))] do
      client =
        client(fn conn ->
          conn |> put_resp_header("etag", reference(@bytes).sha256) |> send_resp(200, bytes)
        end)

      assert RustFS.get(client, reference(@bytes)) == {:error, :integrity_error}
    end
  end

  test "missing objects and authentication/service failures are explicit without retries" do
    for {status, reason} <- [
          {404, :not_found},
          {401, :unauthorized},
          {403, :unauthorized},
          {409, :conflict},
          {429, :unavailable},
          {500, :unavailable},
          {503, :unavailable}
        ] do
      owner = self()

      client =
        client(fn conn ->
          send(owner, :request)
          send_resp(conn, status, "private service error")
        end)

      assert RustFS.get(client, reference(@bytes)) == {:error, reason}
      assert_receive :request
      refute_receive :request
    end
  end

  test "redirects are not followed or trusted with credentials" do
    owner = self()

    client =
      client(fn conn ->
        send(owner, :request)
        conn |> put_resp_header("location", "https://other.test/private") |> send_resp(307, "")
      end)

    assert RustFS.get(client, reference(@bytes)) == {:error, {:http_error, 307}}
    assert_receive :request
    refute_receive :request
  end

  test "invalid references cannot select arbitrary object paths or unbounded reads" do
    client = client(fn _ -> flunk("invalid reference must not send a request") end)
    valid = reference(@bytes)

    for invalid <- [
          nil,
          %{},
          %{valid | key: "../other"},
          %{valid | sha256: "BAD"},
          %{valid | byte_size: 0},
          %{valid | byte_size: @limit + 1},
          %{valid | byte_size: "20"}
        ] do
      assert RustFS.get(client, invalid) == {:error, :invalid_reference}
    end
  end

  test "empty, invalid and oversized writes send no request" do
    client = client(fn _ -> flunk("rejected bytes must not send a request") end)
    assert RustFS.put(client, "") == {:error, :invalid_bytes}
    assert RustFS.put(client, nil) == {:error, :invalid_bytes}
    assert RustFS.put(client, :binary.copy("x", @limit + 1)) == {:error, :too_large}
  end

  test "accepts exactly 20 MiB and verifies it after writing" do
    bytes = :binary.copy("x", @limit)

    client =
      client(fn conn ->
        if conn.method == "PUT", do: send_resp(conn, 200, ""), else: send_resp(conn, 200, bytes)
      end)

    assert RustFS.put(client, bytes) == {:ok, reference(bytes)}
  end

  test "enforces retrieval size while streaming even without Content-Length" do
    client =
      client(fn conn ->
        conn = send_chunked(conn, 200)
        {:ok, conn} = chunk(conn, @bytes)
        {:ok, conn} = chunk(conn, "extra")
        conn
      end)

    assert RustFS.get(client, reference(@bytes)) == {:error, :integrity_error}
  end

  test "encoded responses are rejected rather than changing original bytes" do
    client =
      client(fn conn ->
        conn |> put_resp_header("content-encoding", "gzip") |> send_resp(200, :zlib.gzip(@bytes))
      end)

    assert RustFS.get(client, reference(@bytes)) == {:error, :integrity_error}
  end

  test "total request duration is bounded and exceptions do not leak request data" do
    client =
      client(
        fn _ ->
          Process.sleep(200)
          raise "secret response"
        end,
        timeout_ms: 25
      )

    assert RustFS.get(client, reference(@bytes)) == {:error, :timeout}

    client = client(fn _ -> raise "secret response" end)
    assert RustFS.get(client, reference(@bytes)) == {:error, :transport_error}
  end

  test "configuration validates endpoint, bucket, credentials and timeout" do
    for override <- [
          [endpoint: "ftp://storage.test"],
          [endpoint: "https://user:secret@storage.test"],
          [endpoint: "https://storage.test/path"],
          [endpoint: "https://storage.test?secret=yes"],
          [endpoint: "https://storage.test#fragment"],
          [bucket: "../bucket"],
          [endpoint: "http://storage.test:bad"],
          [endpoint: "http://[invalid"],
          [access_key_id: ""],
          [secret_access_key: nil],
          [timeout_ms: 0],
          [timeout_ms: 30_001]
        ] do
      assert RustFS.new(Keyword.merge(options(), override)) == {:error, :invalid_configuration}
    end

    assert RustFS.new([]) == {:error, :not_configured}
    assert {:ok, client} = RustFS.new(options())
    refute inspect(client) =~ "test-secret"
  end

  defp reference(bytes) do
    hash = Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

    %{
      sha256: hash,
      byte_size: byte_size(bytes),
      key: "earnings/originals/sha256/" <> hash <> ".pdf"
    }
  end

  defp options do
    [
      endpoint: "http://storage.test",
      bucket: "lens-originals",
      access_key_id: "test-access",
      secret_access_key: "test-secret"
    ]
  end

  defp client(plug, overrides \\ []) do
    {:ok, client} = RustFS.new(Keyword.merge(options(), overrides))
    %{client | request: Req.merge(client.request, plug: plug)}
  end
end
