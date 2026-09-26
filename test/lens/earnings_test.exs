defmodule Lens.EarningsTest do
  use Lens.DataCase

  alias Lens.Earnings
  alias Lens.Earnings.{Acquisition, Original, Release}

  @at ~U[2026-09-26 01:00:00.000000Z]
  @release %{fiscal_year_end: ~D[2027-03-31], period: "q1", category: "earnings_release"}

  test "one release can retain distinct bytes from one or several URLs" do
    first = success("first", "%PDF-first", "https://example.test/a.pdf")
    second = success("second", "%PDF-second", "https://example.test/a.pdf")
    third = success("third", "%PDF-first", "https://example.test/b.pdf")

    assert {:ok, %{release: release, original: original}} = Earnings.record_success(first)
    assert {:ok, %{release: ^release, original: changed}} = Earnings.record_success(second)
    assert {:ok, %{release: ^release, original: ^original}} = Earnings.record_success(third)
    assert changed.id != original.id
    assert Repo.aggregate(Release, :count) == 1
    assert Repo.aggregate(Original, :count) == 2
    assert Repo.aggregate(Acquisition, :count) == 3
    assert Earnings.original_bytes(original.id) == {:ok, "%PDF-first"}
  end

  test "a persistence retry does not invent another acquisition" do
    attrs = success("same-event", "%PDF-bytes", "https://example.test/a.pdf")
    assert {:ok, first} = Earnings.record_success(attrs)
    assert {:ok, second} = Earnings.record_success(attrs)
    assert first.acquisition.id == second.acquisition.id
    assert Repo.aggregate(Acquisition, :count) == 1

    assert {:error, :acquisition_conflict} =
             Earnings.record_success(%{attrs | bytes: "%PDF-other"})

    assert {:error, :acquisition_conflict} =
             Earnings.record_success(%{attrs | release: %{@release | period: "q2"}})

    assert Repo.aggregate(Release, :count) == 1
  end

  test "ambiguous identity remains pending until explicitly confirmed" do
    attrs = success("pending", "%PDF-pending", "https://example.test/pending.pdf")

    assert {:ok, %{acquisition: pending, release: nil}} =
             Earnings.record_success(Map.delete(attrs, :release))

    assert pending.release_id == nil
    assert pending.issuer_code == "6857"
    assert Repo.aggregate(Release, :count) == 0

    assert {:ok, confirmed} = Earnings.confirm_identity(pending.id, @release)
    assert confirmed.release_id
    assert Repo.aggregate(Release, :count) == 1
  end

  test "issuer and period are part of release identity" do
    assert {:ok, _} =
             Earnings.record_success(success("one", "%PDF-one", "https://example.test/1.pdf"))

    assert {:ok, _} =
             Earnings.record_success(
               success("two", "%PDF-two", "https://example.test/2.pdf")
               |> Map.put(:issuer_code, "8035")
             )

    assert {:ok, _} =
             Earnings.record_success(
               success("three", "%PDF-three", "https://example.test/3.pdf")
               |> Map.put(:release, %{@release | period: "q2"})
             )

    assert Repo.aggregate(Release, :count) == 3
  end

  test "20 MiB is accepted and an oversized attempt is a failure without an original" do
    at_limit = :binary.copy("x", 20_971_520)

    assert {:ok, %{original: original}} =
             Earnings.record_success(success("limit", at_limit, "https://example.test/limit.pdf"))

    assert original.byte_size == 20_971_520

    assert {:error, :too_large, failure} =
             Earnings.record_success(
               success("too-large", at_limit <> "x", "https://example.test/large.pdf")
             )

    assert failure.status == "failed"
    assert failure.failure_reason == "too_large"
    assert failure.original_id == nil
    assert Repo.aggregate(Original, :count) == 1
    assert Repo.aggregate(Acquisition, :count) == 2
  end

  test "download failures are retryable and do not affect retained originals" do
    assert {:ok, %{original: original}} =
             Earnings.record_success(success("good", "%PDF-good", "https://example.test/a.pdf"))

    assert {:ok, failure} =
             Earnings.record_failure(%{
               acquisition_id: "failed",
               issuer_code: "6857",
               url: "https://example.test/a.pdf",
               acquired_at: @at,
               reason: "timeout"
             })

    assert failure.status == "failed"
    assert failure.original_id == nil

    assert {:ok, _} =
             Earnings.record_success(success("retry", "%PDF-good", "https://example.test/a.pdf"))

    assert Repo.aggregate(Original, :count) == 1
    assert Earnings.original_bytes(original.id) == {:ok, "%PDF-good"}
  end

  test "concurrent downloads keep one original and two acquisitions" do
    results =
      ["concurrent-a", "concurrent-b"]
      |> Task.async_stream(
        fn id ->
          Earnings.record_success(success(id, "%PDF-shared", "https://example.test/a.pdf"))
        end,
        max_concurrency: 2
      )
      |> Enum.to_list()

    assert Enum.all?(results, &match?({:ok, {:ok, _}}, &1))
    assert Repo.aggregate(Original, :count) == 1
    assert Repo.aggregate(Acquisition, :count) == 2
  end

  test "a stored original cannot be changed or deleted" do
    assert {:ok, %{original: original}} =
             Earnings.record_success(
               success("immutable", "%PDF-original", "https://example.test/a.pdf")
             )

    assert_raise Postgrex.Error, ~r/immutable/, fn ->
      Repo.query!("UPDATE earnings_originals SET bytes = $1 WHERE id = $2", [
        "%PDF-changed",
        Ecto.UUID.dump!(original.id)
      ])
    end

    assert Earnings.original_bytes(original.id) == {:ok, "%PDF-original"}
  end

  test "acquisition provenance and release identity cannot be rewritten" do
    assert {:ok, %{acquisition: acquisition, release: release}} =
             Earnings.record_success(
               success("history", "%PDF-history", "https://example.test/a.pdf")
             )

    assert_raise Postgrex.Error, ~r/immutable/, fn ->
      Repo.query!("UPDATE earnings_acquisitions SET url = $1 WHERE id = $2", [
        "https://example.test/changed.pdf",
        Ecto.UUID.dump!(acquisition.id)
      ])
    end

    assert_raise Postgrex.Error, ~r/immutable/, fn ->
      Repo.query!("UPDATE earnings_releases SET period = $1 WHERE id = $2", [
        "q2",
        Ecto.UUID.dump!(release.id)
      ])
    end
  end

  test "invalid provenance rolls back all successful storage" do
    attrs = success("bad-url", "%PDF-new", "https://user:secret@example.test/a.pdf")
    assert {:error, %Ecto.Changeset{}} = Earnings.record_success(attrs)
    assert Repo.aggregate(Release, :count) == 0
    assert Repo.aggregate(Original, :count) == 0
    assert Repo.aggregate(Acquisition, :count) == 0
  end

  defp success(id, bytes, url) do
    %{
      acquisition_id: id,
      issuer_code: "6857",
      url: url,
      acquired_at: @at,
      bytes: bytes,
      release: @release
    }
  end
end
