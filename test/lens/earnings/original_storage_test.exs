defmodule Lens.Earnings.OriginalStorageTest do
  use Lens.DataCase

  alias Lens.Earnings
  alias Lens.Earnings.{OriginalReadLocation, OriginalStorageLocation}

  @at ~U[2026-09-26 01:00:00.000000Z]

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
end
