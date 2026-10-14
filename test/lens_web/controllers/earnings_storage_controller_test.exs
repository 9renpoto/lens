defmodule LensWeb.EarningsStorageControllerTest do
  use Lens.DataCase
  import Phoenix.ConnTest
  import Plug.Conn
  import OpenApiSpex.TestAssertions
  alias Lens.Earnings
  alias Lens.Earnings.{Acquisition, Extraction, Original, RustFS, StorageWork}
  @endpoint LensWeb.Endpoint

  setup do
    previous = Application.get_env(:lens, RustFS)
    Application.delete_env(:lens, RustFS)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:lens, RustFS, previous),
        else: Application.delete_env(:lens, RustFS)
    end)

    {:ok, client} =
      RustFS.new(
        endpoint: "http://storage.test",
        bucket: "lens-test",
        access_key_id: "test",
        secret_access_key: "test"
      )

    %{client: client}
  end

  test "unfinished work views project only four fields and never mutate or contact storage", c do
    first = work(c.client, "first")
    second = work(c.client, "second")
    completed = work(c.client, "completed")
    {:ok, claim} = StorageWork.claim(completed.id)
    {:ok, _} = StorageWork.finish(claim, {:ok, "%PDF-completed"})
    conn = get(build_conn(), "/api/earnings/storage-work")
    response = json_response(conn, 200)
    assert response["limit"] == 50
    assert response["offset"] == 0
    assert Enum.map(response["work"], & &1["id"]) == [first.id, second.id]
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert_response_schema(response, "EarningsStorageWorkListResponse", LensWeb.ApiSpec.spec())

    for item <- response["work"] do
      assert Enum.sort(Map.keys(item)) == ~w(acquisition_id id status updated_at)
    end

    detail = get(build_conn(), "/api/earnings/storage-work/#{first.id}") |> json_response(200)
    assert detail["work"] == hd(response["work"])
    assert_response_schema(detail, "EarningsStorageWorkResponse", LensWeb.ApiSpec.spec())

    page =
      get(build_conn(), "/api/earnings/storage-work", %{limit: "1", offset: "1"})
      |> json_response(200)

    assert Enum.map(page["work"], & &1["id"]) == [second.id]

    assert get(build_conn(), "/api/earnings/originals/#{first.id}") |> json_response(404) == %{
             "error" => "not_found"
           }

    refute Repo.get_by(Acquisition, acquisition_id: first.acquisition_id)
    assert Repo.get!(StorageWork, first.id) == first
    assert Repo.get!(StorageWork, second.id) == second

    for id <- ["invalid", Ecto.UUID.generate(), completed.id] do
      conn = get(build_conn(), "/api/earnings/storage-work/#{id}")
      assert json_response(conn, 404) == %{"error" => "not_found"}
      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end
  end

  test "work pagination rejects malformed and out-of-bound values" do
    for params <- [
          %{limit: "0"},
          %{limit: "101"},
          %{limit: "1.0"},
          %{limit: "x"},
          %{limit: ["1"]},
          %{offset: "-1"},
          %{offset: "2147483648"},
          %{offset: "1x"}
        ] do
      conn = get(build_conn(), "/api/earnings/storage-work", params)
      assert json_response(conn, 422) == %{"error" => "invalid_pagination"}
      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end

    assert get(build_conn(), "/api/earnings/storage-work", %{limit: "100", offset: "2147483647"})
           |> json_response(200) ==
             %{"work" => [], "limit" => 100, "offset" => 2_147_483_647}
  end

  test "all unfinished states remain visible and list is capped at 100", c do
    pending = work(c.client, "pending")
    running = work(c.client, "running")
    {:ok, _} = StorageWork.claim(running.id)
    attention = work(c.client, "attention")
    {:ok, claim} = StorageWork.claim(attention.id)
    {:ok, _} = StorageWork.finish(claim, {:error, :unauthorized})
    exhausted = work(c.client, "exhausted")

    Enum.reduce([60, 300, 1800, 0], DateTime.utc_now(), fn seconds, now ->
      {:ok, claim} = StorageWork.claim(exhausted.id, now)
      {:ok, _} = StorageWork.finish(claim, {:error, :unavailable}, now)
      DateTime.add(now, seconds, :second)
    end)

    response = get(build_conn(), "/api/earnings/storage-work") |> json_response(200)
    assert Enum.map(response["work"], & &1["status"]) == ~w(pending running attention exhausted)
    assert hd(response["work"])["acquisition_id"] == pending.acquisition_id
    refute Repo.get_by(Acquisition, acquisition_id: pending.acquisition_id)
    for index <- 1..100, do: work(c.client, "extra-#{index}")

    response =
      get(build_conn(), "/api/earnings/storage-work", %{limit: "100"}) |> json_response(200)

    assert length(response["work"]) == 100
  end

  test "original endpoint retrieves exact older bytes and negotiates PDF without affecting JSON routes" do
    older = retained("older")
    retained("newer")

    for accept <- ["application/pdf", "application/json", "*/*"] do
      conn =
        build_conn()
        |> put_req_header("accept", accept)
        |> get("/api/earnings/originals/#{older.original.id}")

      assert response(conn, 200) == "%PDF-older"
      assert get_resp_header(conn, "content-type") == ["application/pdf"]
      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end

    for id <- ["invalid", Ecto.UUID.generate()] do
      conn =
        build_conn()
        |> put_req_header("accept", "application/pdf")
        |> get("/api/earnings/originals/#{id}")

      assert json_response(conn, 404) == %{"error" => "not_found"}
      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end

    assert_raise Phoenix.NotAcceptableError, fn ->
      build_conn()
      |> put_req_header("accept", "application/pdf")
      |> get("/api/search", %{q: "test"})
    end

    assert Repo.aggregate(Extraction, :count) == 0
  end

  test "known originals return safe storage errors without fallback or mutation", c do
    original = retained("storage").original

    reference = %{
      key: "earnings/originals/sha256/#{original.sha256}.pdf",
      sha256: original.sha256,
      byte_size: original.byte_size,
      endpoint: c.client.endpoint,
      bucket: c.client.bucket
    }

    assert {:ok, _} = Lens.Earnings.OriginalStorage.select_rustfs(original, reference)
    original = Repo.get!(Original, original.id)
    conn = get(build_conn(), "/api/earnings/originals/#{original.id}")

    assert json_response(conn, 503) == %{
             "error" => "original_unavailable",
             "original_id" => original.id,
             "reason" => "not_configured"
           }

    assert_response_schema(
      json_response(conn, 503),
      "EarningsOriginalUnavailableResponse",
      LensWeb.ApiSpec.spec()
    )

    for {options, reason} <- [
          {[
             endpoint: "http://different.test",
             bucket: c.client.bucket,
             access_key_id: "test",
             secret_access_key: "secret"
           ], "destination_mismatch"},
          {[
             endpoint: c.client.endpoint,
             bucket: c.client.bucket,
             access_key_id: "",
             secret_access_key: "secret"
           ], "invalid_configuration"}
        ] do
      Application.put_env(:lens, RustFS, options)

      assert get(build_conn(), "/api/earnings/originals/#{original.id}") |> json_response(503) ==
               %{
                 "error" => "original_unavailable",
                 "original_id" => original.id,
                 "reason" => reason
               }
    end

    for {status, body, reason} <- [
          {404, "secret storage body", "not_found"},
          {200, "%PDF-corrupt", "integrity_error"},
          {503, "secret", "unavailable"},
          {403, "credential", "unauthorized"},
          {418, "secret", "storage_error"},
          {200, "%PDF-storage", nil}
        ] do
      test_bytes = "%PDF-storage-#{status}-#{Ecto.UUID.generate()}"
      endpoint = storage_server(status, if(reason, do: body, else: test_bytes))
      # Use a fresh original because persisted destination facts are immutable.
      next = retained("storage-#{status}-#{Ecto.UUID.generate()}", test_bytes).original

      next_reference = %{
        reference
        | key: "earnings/originals/sha256/#{next.sha256}.pdf",
          sha256: next.sha256,
          byte_size: next.byte_size,
          endpoint: endpoint
      }

      {:ok, _} = Lens.Earnings.OriginalStorage.select_rustfs(next, next_reference)

      Application.put_env(:lens, RustFS,
        endpoint: endpoint,
        bucket: c.client.bucket,
        access_key_id: "test",
        secret_access_key: "secret"
      )

      conn = get(build_conn(), "/api/earnings/originals/#{next.id}")

      if reason do
        assert json_response(conn, 503) == %{
                 "error" => "original_unavailable",
                 "original_id" => next.id,
                 "reason" => reason
               }
      else
        assert response(conn, 200) == test_bytes
      end

      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end

    assert Repo.get!(Original, original.id) == original
    assert Repo.aggregate(Extraction, :count) == 0
    assert Repo.aggregate(StorageWork, :count) == 0
  end

  defp work(client, id) do
    {:ok, work} =
      StorageWork.prepare(
        %{
          bytes: "%PDF-" <> id,
          acquisition_id: id,
          issuer_code: "7203",
          url: "https://publisher.test/#{id}.pdf",
          acquired_at: DateTime.utc_now()
        },
        client
      )

    work
  end

  defp retained(id, bytes \\ nil) do
    {:ok, result} =
      Earnings.record_success(%{
        bytes: bytes || "%PDF-" <> id,
        acquisition_id: id,
        issuer_code: "7203",
        url: "https://publisher.test/#{id}.pdf",
        acquired_at: DateTime.utc_now()
      })

    result
  end

  defp storage_server(status, body) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)
    pid = spawn(fn -> serve(listener, status, body) end)

    on_exit(fn ->
      :gen_tcp.close(listener)
      Process.exit(pid, :kill)
    end)

    "http://127.0.0.1:#{port}"
  end

  defp serve(listener, status, body) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        :gen_tcp.recv(socket, 0, 2000)

        :gen_tcp.send(
          socket,
          "HTTP/1.1 #{status} Response\r\nContent-Length: #{byte_size(body)}\r\nConnection: close\r\n\r\n#{body}"
        )

        :gen_tcp.close(socket)
        serve(listener, status, body)

      _ ->
        :ok
    end
  end
end
