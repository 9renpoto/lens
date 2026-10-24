defmodule Lens.Earnings.CollectionStorageTest do
  use Lens.DataCase
  alias Lens.Earnings.{Acquisition, HTTPCheck, HTTPHistory, RustFS, Sources}

  setup do
    {:ok, target} =
      Lens.Analysis.create_target(%{
        security_code: "issuer-example-a",
        market: "TSE",
        display_name: "Example",
        sector: "Test"
      })

    {:ok, source} = Sources.create(target, %{listing_url: "https://publisher.test/results"})

    {:ok, client} =
      RustFS.new(
        endpoint: "http://storage.test",
        bucket: "lens-test",
        access_key_id: "test",
        secret_access_key: "test"
      )

    attrs = %{
      check_id: Ecto.UUID.generate(),
      issuer_code: "issuer-example-a",
      kind: :pdf,
      url: "https://publisher.test/request.pdf",
      checked_at: DateTime.utc_now(),
      metadata: %{source_id: source.id, anchor_text: "Results"},
      result: %{
        outcome: :success,
        final_url: "https://publisher.test/actual.pdf",
        bytes: "%PDF-retained",
        http_status: 200,
        requests: 1,
        retryable: false,
        headers: %{"content-type" => ["application/pdf"]}
      }
    }

    %{source: source, client: client, attrs: attrs}
  end

  test "synchronous save verifies bytes before atomically recording the original and HTTP facts",
       c do
    client = %{
      c.client
      | request:
          Req.new(
            retry: false,
            plug: fn conn ->
              assert Repo.aggregate(Acquisition, :count) == 0
              assert Repo.aggregate(HTTPCheck, :count) == 0

              case conn.method do
                "PUT" ->
                  assert Plug.Conn.get_req_header(conn, "if-none-match") == ["*"]
                  Plug.Conn.send_resp(conn, 200, "")

                "GET" ->
                  Plug.Conn.send_resp(conn, 200, c.attrs.result.bytes)
              end
            end
          )
    }

    assert {:ok, check} = HTTPHistory.store(c.attrs, client)
    assert check.metadata["source_id"] == c.source.id
    assert check.metadata["anchor_text"] == "Results"
    assert check.final_url == c.attrs.result.final_url
    assert check.checked_at == c.attrs.checked_at
    acquisition = Repo.get!(Acquisition, check.acquisition_id)
    assert acquisition.status == "success"
    assert Repo.get!(Lens.Earnings.Original, acquisition.original_id).endpoint == client.endpoint

    read_client = %{
      client
      | request:
          Req.new(plug: fn conn -> Plug.Conn.send_resp(conn, 200, c.attrs.result.bytes) end)
    }

    assert Lens.Earnings.original_bytes(acquisition.original_id, rustfs: read_client) ==
             {:ok, c.attrs.result.bytes}
  end

  test "failed save records a failed acquisition without a PDF success or original", c do
    client = %{
      c.client
      | request:
          Req.new(
            retry: false,
            plug: fn conn ->
              assert conn.method == "PUT"
              Plug.Conn.send_resp(conn, 503, "private-provider-body")
            end
          )
    }

    assert {:storage_failed, "unavailable"} = HTTPHistory.store(c.attrs, client)
    assert [acquisition] = Repo.all(Acquisition)
    assert acquisition.status == "failed"
    assert acquisition.failure_reason == "storage_unavailable"
    assert acquisition.acquisition_id == "http:" <> c.attrs.check_id
    assert acquisition.url == c.attrs.result.final_url
    assert acquisition.acquired_at == c.attrs.checked_at
    assert Repo.aggregate(HTTPCheck, :count) == 0
    assert Repo.aggregate(Lens.Earnings.Original, :count) == 0
  end

  test "invalid HTTP provenance is rejected before object I/O", c do
    attrs = put_in(c.attrs, [:metadata, :anchor_text], String.duplicate("x", 33_000))
    client = %{c.client | request: Req.new(plug: fn _ -> flunk("unexpected object I/O") end)}
    assert {:error, %Ecto.Changeset{}} = HTTPHistory.store(attrs, client)
    assert Repo.aggregate(Acquisition, :count) == 0
  end

  test "failed verification never records successful storage", c do
    client = %{
      c.client
      | request:
          Req.new(
            retry: false,
            plug: fn conn ->
              Plug.Conn.send_resp(
                conn,
                200,
                if(conn.method == "GET", do: "%PDF-corrupt", else: "")
              )
            end
          )
    }

    assert {:storage_failed, "integrity_error"} = HTTPHistory.store(c.attrs, client)

    assert [%{status: "failed", failure_reason: "storage_integrity_error"}] =
             Repo.all(Acquisition)

    assert Repo.aggregate(HTTPCheck, :count) == 0
    assert Repo.aggregate(Lens.Earnings.Original, :count) == 0
  end

  test "object I/O is refused inside a caller transaction", c do
    assert {:ok, {:error, :uncommitted_transaction}} =
             Repo.transaction(fn -> HTTPHistory.store(c.attrs, c.client) end)
  end

  test "deadline before saving leaves an explicit failed acquisition", c do
    assert {:storage_failed, "run_deadline_exceeded"} =
             HTTPHistory.fail_storage(c.attrs, :run_deadline_exceeded)

    assert [%{status: "failed", failure_reason: "storage_run_deadline_exceeded"}] =
             Repo.all(Acquisition)

    assert Repo.aggregate(HTTPCheck, :count) == 0
    assert Repo.aggregate(Lens.Earnings.Original, :count) == 0
  end

  test "failure-history conflict is returned without claiming the save failure was persisted",
       c do
    assert {:ok, existing} =
             Lens.Earnings.record_failure(%{
               acquisition_id: "http:" <> c.attrs.check_id,
               issuer_code: c.attrs.issuer_code,
               url: c.attrs.result.final_url,
               acquired_at: c.attrs.checked_at,
               reason: "existing_failure"
             })

    client = %{
      c.client
      | request:
          Req.new(
            retry: false,
            plug: fn conn ->
              Plug.Conn.send_resp(conn, 503, "private-provider-body")
            end
          )
    }

    assert {:error, :acquisition_conflict} = HTTPHistory.store(c.attrs, client)
    assert Repo.all(Acquisition) == [existing]
    assert Repo.aggregate(HTTPCheck, :count) == 0
    assert Repo.aggregate(Lens.Earnings.Original, :count) == 0
  end

  test "invalid release identity is rejected before any object I/O", c do
    owner = self()

    client = %{
      c.client
      | request:
          Req.new(
            plug: fn conn ->
              send(owner, :identity_storage_request)

              Plug.Conn.send_resp(
                conn,
                200,
                if(conn.method == "GET", do: c.attrs.result.bytes, else: "")
              )
            end
          )
    }

    for release <- [
          %{fiscal_year_end: "invalid", period: "q1", category: "earnings_release"},
          %{fiscal_year_end: ~D[2026-03-31], period: "unknown", category: "earnings_release"},
          "invalid"
        ] do
      attrs = Map.put(c.attrs, :release, release)
      assert {:error, _} = HTTPHistory.store(attrs, client)
      refute_received :identity_storage_request
      assert Repo.aggregate(Acquisition, :count) == 0
      assert Repo.aggregate(Lens.Earnings.Original, :count) == 0
      assert Repo.aggregate(HTTPCheck, :count) == 0
    end
  end
end
