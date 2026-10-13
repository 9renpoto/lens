defmodule Lens.Earnings.CollectionStorageTest do
  use Lens.DataCase
  alias Lens.Earnings.{Acquisition, HTTPCheck, HTTPHistory, RustFS, Sources, StorageWork}

  setup do
    {:ok, target} =
      Lens.Analysis.create_target(%{
        security_code: "7203",
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
      issuer_code: "7203",
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

  test "preparation retains HTTP provenance without success and completion inserts immutable history once",
       c do
    assert {:ok, work} = HTTPHistory.prepare_storage(c.attrs, c.client)
    assert work.source_id == c.source.id
    assert work.http_check["metadata"]["anchor_text"] == "Results"
    assert work.bytes == c.attrs.result.bytes
    assert Repo.aggregate(HTTPCheck, :count) == 0
    assert Repo.aggregate(Acquisition, :count) == 0
    assert StorageWork.unfinished_for_source?(c.source.id)
    assert {:ok, same} = HTTPHistory.prepare_storage(c.attrs, c.client)
    assert same.id == work.id

    client = %{
      c.client
      | request:
          Req.new(
            plug: fn conn ->
              assert conn.method == "GET"
              Plug.Conn.send_resp(conn, 200, c.attrs.result.bytes)
            end
          )
    }

    assert {:ok, completed} = StorageWork.recover(work.id, client)
    assert completed.status == "completed"
    refute StorageWork.unfinished_for_source?(c.source.id)
    assert [check] = Repo.all(HTTPCheck)
    assert check.metadata["source_id"] == c.source.id
    assert check.final_url == c.attrs.result.final_url
    assert check.checked_at == c.attrs.checked_at
    assert check.acquisition_id == completed.acquisition_record_id
    assert Repo.aggregate(Acquisition, :count) == 1
    assert {:error, :not_eligible} = StorageWork.recover(work.id, client)
    assert Repo.aggregate(HTTPCheck, :count) == 1
  end

  test "invalid HTTP provenance rejects preparation before durable work or object I/O", c do
    attrs = put_in(c.attrs, [:metadata, :anchor_text], String.duplicate("x", 33_000))
    assert {:error, %Ecto.Changeset{}} = HTTPHistory.prepare_storage(attrs, c.client)
    assert Repo.aggregate(StorageWork, :count) == 0
    assert Repo.aggregate(Acquisition, :count) == 0
  end

  test "an unfinished source rejects a new collection acquisition without resetting its budget",
       c do
    {:ok, work} = HTTPHistory.prepare_storage(c.attrs, c.client)
    {:ok, claim} = StorageWork.claim(work.id)
    {:ok, _} = StorageWork.finish(claim, {:error, :unavailable})

    assert {:error, :source_busy} =
             HTTPHistory.prepare_storage(%{c.attrs | check_id: Ecto.UUID.generate()}, c.client)

    assert Repo.aggregate(StorageWork, :count) == 1
    assert Repo.get!(StorageWork, work.id).attempts == 1
    assert {:ok, same} = HTTPHistory.prepare_storage(c.attrs, c.client)
    assert same.id == work.id
  end

  test "all unfinished states keep a source excluded until every work completes", c do
    {:ok, first} = HTTPHistory.prepare_storage(c.attrs, c.client)
    other = %{c.attrs | check_id: Ecto.UUID.generate()}
    # Existing/imported work can contain multiple unfinished records for one source.
    {:ok, second} =
      StorageWork.prepare(
        %{
          acquisition_id: "http:" <> other.check_id,
          issuer_code: other.issuer_code,
          url: other.result.final_url,
          acquired_at: other.checked_at,
          bytes: other.result.bytes
        },
        c.client
      )

    second = Repo.update!(Ecto.Changeset.change(second, source_id: c.source.id))
    {:ok, claim} = StorageWork.claim(first.id)
    {:ok, _} = StorageWork.finish(claim, {:error, :unauthorized})
    assert StorageWork.unfinished_for_source?(c.source.id)
    {:ok, claim} = StorageWork.claim(second.id)
    {:ok, _} = StorageWork.finish(claim, {:ok, c.attrs.result.bytes})
    assert StorageWork.unfinished_for_source?(c.source.id)
    assert {:ok, _} = StorageWork.manual_retry(first.id, "operator")
    {:ok, claim} = StorageWork.claim(first.id)
    {:ok, _} = StorageWork.finish(claim, {:ok, c.attrs.result.bytes})
    refute StorageWork.unfinished_for_source?(c.source.id)
  end
end
