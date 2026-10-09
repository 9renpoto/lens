defmodule Lens.Earnings.StorageMigrationTest do
  use Lens.DataCase

  alias Lens.Earnings

  alias Lens.Earnings.{
    Original,
    OriginalStorage,
    RustFS,
    StorageFence,
    StorageMigration,
    StorageRollbackCLI,
    StorageWork
  }

  import Plug.Conn

  @at ~U[2026-09-26 01:00:00.000000Z]

  test "migration rejects originals without PostgreSQL bytes" do
    sha256 = String.duplicate("a", 64)

    original = %Original{
      id: Ecto.UUID.generate(),
      bytes: nil,
      sha256: sha256,
      byte_size: 1
    }

    reference = %{
      key: "earnings/originals/sha256/#{sha256}.pdf",
      sha256: sha256,
      byte_size: 1
    }

    assert {:error, :original_unavailable} = OriginalStorage.switch_to_rustfs(original, reference)
  end

  test "a verified RustFS copy becomes the original read source" do
    bytes = <<"%PDF-1.7\n", 0, 255, 13, 10, "migration-original">>

    assert {:ok, %{original: original}} =
             Earnings.record_success(%{
               acquisition_id: "storage-migration-1",
               issuer_code: "6857",
               url: "https://example.test/original.pdf",
               acquired_at: @at,
               bytes: bytes
             })

    client = rustfs_client(bytes)

    assert {:ok, %{migrated: 1, failures: [], next_after: next_after}} =
             StorageMigration.migrate_batch(client, limit: 10)

    assert next_after == original.id
    assert Repo.get!(Lens.Earnings.Original, original.id).bytes == bytes

    assert Earnings.original_bytes(original.id, rustfs: client) == {:ok, bytes}

    assert Earnings.original_bytes(original.id, rustfs: rustfs_client("corrupt")) ==
             {:error, :integrity_error}

    assert Repo.get_by!(Lens.Earnings.Acquisition, acquisition_id: "storage-migration-1").original_id ==
             original.id
  end

  test "a failed verification leaves the original on PostgreSQL and reports the failure" do
    bytes = "%PDF-1.7\noriginal"

    assert {:ok, %{original: original}} =
             Earnings.record_success(%{
               acquisition_id: "storage-migration-failed-1",
               issuer_code: "6857",
               url: "https://example.test/original.pdf",
               acquired_at: @at,
               bytes: bytes
             })

    client = rustfs_client("corrupt-object")

    assert {:ok, %{migrated: 0, failures: [%{original_id: failed_id}], next_after: nil}} =
             StorageMigration.migrate_batch(client, limit: 10)

    assert failed_id == original.id
    assert Earnings.original_bytes(original.id, rustfs: client) == {:ok, bytes}
  end

  test "rollback restores RustFS-only originals and keeps the write fence until complete" do
    bytes = <<"%PDF-1.7\n", "rustfs-only">>
    client = rustfs_client(bytes)
    assert {:ok, reference} = RustFS.put(client, bytes)

    assert {:ok, %{original: original}} =
             Earnings.record_success(%{
               acquisition_id: "storage-rollback-rustfs-only",
               issuer_code: "6857",
               url: "https://example.test/rustfs-only.pdf",
               acquired_at: @at,
               bytes: bytes,
               storage_reference: reference
             })

    assert original.bytes == nil

    corrupt_client = rustfs_client("different-object")

    original_id = original.id

    assert {:error, {:rollback_incomplete, json}} =
             StorageRollbackCLI.run([], corrupt_client)

    assert %{
             "complete?" => false,
             "failures" => [%{"original_id" => ^original_id, "reason" => "integrity_error"}],
             "remaining" => 1,
             "next_after" => nil
           } = Jason.decode!(json)

    assert StorageFence.rollback_active?()

    assert {:error, :rollback_in_progress} =
             Earnings.record_failure(%{
               acquisition_id: "storage-rollback-write-fenced",
               issuer_code: "6857",
               url: "https://example.test/new.pdf",
               acquired_at: @at,
               reason: "paused"
             })

    assert {:error, :rollback_in_progress} =
             StorageWork.prepare(
               %{
                 acquisition_id: "storage-rollback-preparation-fenced",
                 issuer_code: "6857",
                 url: "https://example.test/queued.pdf",
                 acquired_at: @at,
                 bytes: "%PDF-pending"
               },
               client
             )

    assert {:ok, json} = StorageRollbackCLI.run([], client)
    assert %{"complete?" => true, "failures" => [], "remaining" => 0} = Jason.decode!(json)

    refute StorageFence.rollback_active?()
    assert Repo.get!(Lens.Earnings.Original, original.id).bytes == bytes
    assert Earnings.original_bytes(original.id) == {:ok, bytes}
  end

  defp rustfs_client(response_bytes) do
    {:ok, client} =
      RustFS.new(
        endpoint: "http://storage.test",
        bucket: "lens-originals",
        access_key_id: "test-access",
        secret_access_key: "test-secret"
      )

    %{
      client
      | request:
          Req.merge(client.request, plug: fn conn -> rustfs_response(conn, response_bytes) end)
    }
  end

  defp rustfs_response(%{method: "PUT"} = conn, _response_bytes), do: send_resp(conn, 200, "")

  defp rustfs_response(%{method: "GET"} = conn, response_bytes) do
    conn
    |> put_resp_header("content-type", "application/pdf")
    |> send_resp(200, response_bytes)
  end
end
