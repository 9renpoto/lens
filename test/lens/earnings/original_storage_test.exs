defmodule Lens.Earnings.OriginalStorageTest do
  use Lens.DataCase

  alias Lens.Earnings

  alias Lens.Earnings.{
    Original,
    OriginalReadLocation,
    OriginalStorage,
    OriginalStorageLocation
  }

  @at ~U[2026-09-26 01:00:00.000000Z]

  test "the database rejects same-size corrupted restoration and accepts the original bytes" do
    bytes = "%PDF-original"
    digest = Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

    original =
      %Original{}
      |> Original.rustfs_changeset(%{sha256: digest, byte_size: byte_size(bytes)})
      |> Repo.insert!()

    id = Ecto.UUID.dump!(original.id)

    assert_raise Postgrex.Error, ~r/immutable/, fn ->
      Repo.transaction(
        fn ->
          Repo.query!("UPDATE earnings_originals SET bytes = $1 WHERE id = $2", [
            "%PDF-corrupt!",
            id
          ])
        end,
        mode: :savepoint
      )
    end

    assert Repo.get!(Original, original.id).bytes == nil
    Repo.query!("UPDATE earnings_originals SET bytes = $1 WHERE id = $2", [bytes, id])
    assert Earnings.original_bytes(original.id) == {:ok, bytes}
  end

  test "selects a verified RustFS location while retaining the PostgreSQL copy" do
    bytes = "%PDF-storage-location"
    original = record_original("storage-location-select-rustfs", bytes)
    reference = reference(original)
    original_with_bytes = Repo.get!(Original, original.id)

    assert {:ok, rustfs_location} = OriginalStorage.select_rustfs(original_with_bytes, reference)
    assert rustfs_location.backend == "rustfs"
    assert rustfs_location.key == reference.key

    assert Repo.get_by!(OriginalStorageLocation,
             original_id: original.id,
             backend: "postgresql"
           ).sha256 == original.sha256

    assert {:ok, selected} = OriginalStorage.read_location(original.id)
    assert selected.id == rustfs_location.id
    assert Repo.get!(Lens.Earnings.Original, original.id).bytes == bytes

    assert {:error, :location_conflict} =
             OriginalStorage.select_rustfs(original_with_bytes, %{
               reference
               | bucket: "other-bucket"
             })
  end

  test "rejects invalid RustFS references and PostgreSQL bytes without selecting a location" do
    bytes = "%PDF-storage-location-integrity"
    original = record_original("storage-location-invalid-reference", bytes)
    reference = reference(original)

    assert {:error, :invalid_reference} = OriginalStorage.select_rustfs(original, %{})

    assert {:error, :integrity_error} =
             OriginalStorage.select_rustfs(original, %{reference | key: "wrong-key.pdf"})

    assert {:error, :integrity_error} =
             OriginalStorage.select_rustfs(%{original | bytes: "corrupt"}, reference)

    assert {:ok, nil} = OriginalStorage.read_location(original.id)
  end

  test "reports conflicts when a persisted backend location disagrees with the reference" do
    bytes = "%PDF-storage-location-conflict"
    original = record_original("storage-location-conflict", bytes)
    reference = reference(original)

    assert {:ok, _location} =
             %OriginalStorageLocation{}
             |> OriginalStorageLocation.changeset(%{
               original_id: original.id,
               backend: "rustfs",
               key: "earnings/originals/sha256/wrong.pdf",
               endpoint: "http://storage.test",
               bucket: "lens-originals",
               sha256: original.sha256,
               byte_size: original.byte_size,
               verified_at: @at
             })
             |> Repo.insert()

    assert {:error, :location_conflict} = OriginalStorage.select_rustfs(original, reference)
    assert {:ok, nil} = OriginalStorage.read_location(original.id)
  end

  test "partial references return an error without changing the selected backend" do
    original = record_original("storage-partial-reference", "%PDF-partial")
    reference = reference(original)

    for key <- [:key, :sha256, :byte_size] do
      assert {:error, :invalid_reference} =
               OriginalStorage.select_rustfs(original, Map.delete(reference, key))

      assert {:ok, nil} = OriginalStorage.read_location(original.id)
    end
  end

  test "returns a changeset error when the original does not exist" do
    sha256 = String.duplicate("a", 64)

    original = %Original{
      id: Ecto.UUID.generate(),
      bytes: nil,
      sha256: sha256,
      byte_size: 1
    }

    assert {:error, %Ecto.Changeset{}} =
             OriginalStorage.select_rustfs(original, %{
               key: "earnings/originals/sha256/#{sha256}.pdf",
               endpoint: "http://storage.test",
               bucket: "lens-originals",
               sha256: sha256,
               byte_size: 1
             })
  end

  test "a read selection cannot point at another original's storage location" do
    first = record_original("storage-location-first", "%PDF-first")
    second = record_original("storage-location-second", "%PDF-second")

    {:ok, location} =
      %OriginalStorageLocation{}
      |> OriginalStorageLocation.changeset(%{
        original_id: first.id,
        backend: "postgresql",
        key: nil,
        sha256: first.sha256,
        byte_size: first.byte_size,
        verified_at: @at
      })
      |> Repo.insert()

    assert {:error, changeset} =
             %OriginalReadLocation{}
             |> OriginalReadLocation.changeset(%{
               original_id: second.id,
               location_id: location.id
             })
             |> Repo.insert()

    assert %{location_id: [_]} = errors_on(changeset)
  end

  defp record_original(acquisition_id, bytes) do
    assert {:ok, %{original: original}} =
             Earnings.record_success(%{
               acquisition_id: acquisition_id,
               issuer_code: "6857",
               url: "https://example.test/#{acquisition_id}.pdf",
               acquired_at: @at,
               bytes: bytes
             })

    original
  end

  defp reference(original) do
    %{
      key: "earnings/originals/sha256/#{original.sha256}.pdf",
      endpoint: "http://storage.test",
      bucket: "lens-originals",
      sha256: original.sha256,
      byte_size: original.byte_size
    }
  end
end
