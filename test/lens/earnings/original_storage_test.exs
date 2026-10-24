defmodule Lens.Earnings.OriginalStorageTest do
  use Lens.DataCase
  alias Lens.Earnings
  alias Lens.Earnings.{Acquisition, Original, RustFS}

  @at ~U[2026-10-24 01:00:00.000000Z]

  test "a successful acquisition requires a complete verified RustFS reference" do
    attrs = attrs("missing", "%PDF-retained")

    for reference <- [
          nil,
          %{},
          Map.delete(attrs.storage_reference, :endpoint),
          Map.delete(attrs.storage_reference, :bucket)
        ] do
      assert {:error, :invalid_reference} =
               Earnings.record_success(Map.put(attrs, :storage_reference, reference))

      assert Repo.aggregate(Original, :count) == 0
      assert Repo.aggregate(Acquisition, :count) == 0
    end
  end

  test "stores the immutable reference directly and deduplicates repeated bytes" do
    first = attrs("first", "%PDF-retained")
    assert {:ok, one} = Earnings.record_success(first)
    assert {:ok, two} = Earnings.record_success(%{first | acquisition_id: "second"})
    assert one.original.id == two.original.id
    original = Repo.get!(Original, one.original.id)

    assert Map.take(original, [:endpoint, :bucket, :key, :sha256, :byte_size]) ==
             first.storage_reference

    assert original.verified_at != nil
    refute Map.has_key?(original, :bytes)

    assert {:ok, changed} = Earnings.record_success(attrs("changed", "%PDF-changed"))
    refute changed.original.id == original.id
  end

  test "repeat observations cannot change an original's destination" do
    first = attrs("first", "%PDF-retained")
    assert {:ok, _} = Earnings.record_success(first)
    conflicting = put_in(first, [:storage_reference, :bucket], "different-bucket")
    assert {:error, :reference_conflict} = Earnings.record_success(conflicting)

    assert {:error, :reference_conflict} =
             Earnings.record_success(%{conflicting | acquisition_id: "different"})

    assert Repo.aggregate(Acquisition, :count) == 1
  end

  test "rejects a mismatched hash, key or byte size without persisting success" do
    first = attrs("first", "%PDF-retained")

    for {key, value} <- [sha256: String.duplicate("a", 64), key: "wrong.pdf", byte_size: 1] do
      assert {:error, :integrity_error} =
               Earnings.record_success(put_in(first, [:storage_reference, key], value))
    end

    assert Repo.aggregate(Original, :count) == 0
  end

  test "exact original reads verify bytes and reject a changed destination" do
    first = attrs("read", "%PDF-retained")
    assert {:ok, result} = Earnings.record_success(first)

    {:ok, base} =
      RustFS.new(
        endpoint: "http://storage.test",
        bucket: "test-originals",
        access_key_id: "fixture",
        secret_access_key: "fixture"
      )

    client = %{
      base
      | request: Req.new(plug: fn conn -> Plug.Conn.send_resp(conn, 200, first.bytes) end)
    }

    assert {:ok, bytes} = Earnings.original_bytes(result.original.id, rustfs: client)
    assert bytes == first.bytes

    assert {:error, :destination_mismatch} =
             Earnings.original_bytes(result.original.id,
               rustfs: %{client | bucket: "other-bucket"}
             )

    corrupt = %{
      base
      | request: Req.new(plug: fn conn -> Plug.Conn.send_resp(conn, 200, "corrupt") end)
    }

    assert {:error, :integrity_error} =
             Earnings.original_bytes(result.original.id, rustfs: corrupt)
  end

  test "the supported schema contains no PDF bytes or storage-selection tables" do
    assert Repo.query!(
             "SELECT to_regclass('earnings_original_storage_locations'), to_regclass('earnings_original_read_locations')"
           ).rows == [[nil, nil]]

    assert Repo.query!(
             "SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'earnings_originals' AND column_name = 'bytes'"
           ).rows == [[0]]
  end

  test "stored original references cannot be changed" do
    assert {:ok, result} = Earnings.record_success(attrs("immutable", "%PDF-immutable"))

    assert_raise Postgrex.Error, ~r/immutable/, fn ->
      Repo.transaction(
        fn ->
          Repo.query!(
            "UPDATE earnings_originals SET bucket = 'different-bucket' WHERE id = $1",
            [Ecto.UUID.dump!(result.original.id)]
          )
        end,
        mode: :savepoint
      )
    end
  end

  defp attrs(id, bytes) do
    digest = Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

    %{
      acquisition_id: id,
      issuer_code: "issuer-alpha",
      url: "https://publisher.example.test/report.pdf",
      acquired_at: @at,
      bytes: bytes,
      storage_reference: %{
        endpoint: "http://storage.test",
        bucket: "test-originals",
        key: "earnings/originals/sha256/#{digest}.pdf",
        sha256: digest,
        byte_size: byte_size(bytes)
      }
    }
  end
end
