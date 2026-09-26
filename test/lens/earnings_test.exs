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
    assert second.original.bytes == nil
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

    assert {:ok, %{acquisition: ^pending, release: nil}} =
             Earnings.record_success(Map.delete(attrs, :release))

    assert {:error, :acquisition_conflict} = Earnings.record_success(attrs)
    assert Repo.aggregate(Release, :count) == 0

    assert {:ok, confirmed} = Earnings.confirm_identity(pending.acquisition_id, @release)
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

    assert {:error, %Ecto.Changeset{}} =
             Earnings.record_success(success("invalid-large", at_limit <> "x", "invalid URL"))

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

  test "failure details longer than 255 characters are retained" do
    reason = String.duplicate("downloader detail ", 30)

    attrs = %{
      acquisition_id: "long-error",
      issuer_code: "6857",
      url: "https://example.test/a.pdf",
      acquired_at: @at,
      reason: reason
    }

    assert {:ok, failure} = Earnings.record_failure(attrs)
    assert failure.failure_reason == reason
    assert {:ok, ^failure} = Earnings.record_failure(attrs)
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

    assert_immutable_mutation("UPDATE earnings_originals SET bytes = $1 WHERE id = $2", [
      "%PDF-changed",
      Ecto.UUID.dump!(original.id)
    ])

    assert Earnings.original_bytes(original.id) == {:ok, "%PDF-original"}
  end

  test "acquisition provenance and release identity cannot be rewritten" do
    assert {:ok, %{acquisition: acquisition, release: release}} =
             Earnings.record_success(
               success("history", "%PDF-history", "https://example.test/a.pdf")
             )

    assert_immutable_mutation("UPDATE earnings_acquisitions SET url = $1 WHERE id = $2", [
      "https://example.test/changed.pdf",
      Ecto.UUID.dump!(acquisition.id)
    ])

    assert_immutable_mutation("UPDATE earnings_releases SET period = $1 WHERE id = $2", [
      "q2",
      Ecto.UUID.dump!(release.id)
    ])
  end

  test "invalid provenance rolls back all successful storage" do
    attrs = success("bad-url", "%PDF-new", "https://user:secret@example.test/a.pdf")
    assert {:error, %Ecto.Changeset{}} = Earnings.record_success(attrs)
    assert Repo.aggregate(Release, :count) == 0
    assert Repo.aggregate(Original, :count) == 0
    assert Repo.aggregate(Acquisition, :count) == 0
  end

  test "failed persistence retries are idempotent and reject conflicting outcomes" do
    attrs = %{
      acquisition_id: "failure-event",
      issuer_code: "6857",
      url: "https://example.test/a.pdf",
      acquired_at: @at,
      reason: "timeout"
    }

    assert {:ok, failure} = Earnings.record_failure(attrs)
    assert {:ok, ^failure} = Earnings.record_failure(attrs)

    assert {:error, :acquisition_conflict} =
             Earnings.record_failure(%{attrs | reason: "not_found"})

    assert {:error, :acquisition_conflict} =
             Earnings.record_failure(%{attrs | url: "https://example.test/other.pdf"})

    assert {:error, :acquisition_conflict} =
             Earnings.record_success(success("failure-event", "%PDF-late", attrs.url))

    assert {:error, :not_successful} = Earnings.confirm_identity("failure-event", @release)
    assert Repo.aggregate(Acquisition, :count) == 1
    assert Repo.aggregate(Original, :count) == 0
  end

  test "identity confirmation is idempotent and cannot reassign a release" do
    attrs =
      success("confirm", "%PDF-confirm", "https://example.test/a.pdf") |> Map.delete(:release)

    assert {:ok, %{acquisition: pending}} = Earnings.record_success(attrs)
    assert {:error, :invalid_identity} = Earnings.confirm_identity(pending.acquisition_id, nil)

    assert {:error, %Ecto.Changeset{}} =
             Earnings.confirm_identity(pending.acquisition_id, %{@release | period: "q4"})

    assert {:ok, confirmed} = Earnings.confirm_identity(pending.acquisition_id, @release)
    assert {:ok, ^confirmed} = Earnings.confirm_identity(pending.acquisition_id, @release)

    assert {:error, :identity_conflict} =
             Earnings.confirm_identity(pending.acquisition_id, %{@release | period: "q2"})

    assert Repo.aggregate(Release, :count) == 1
    assert {:error, :not_found} = Earnings.confirm_identity("missing", @release)
  end

  test "invalid bytes and invalid acquisition metadata do not create retained data" do
    assert {:error, :invalid_bytes} = Earnings.record_success(%{bytes: nil})

    assert {:error, %Ecto.Changeset{}} =
             Earnings.record_success(success("empty", "", "https://example.test/a.pdf"))

    assert {:error, %Ecto.Changeset{}} =
             Earnings.record_failure(%{acquisition_id: "invalid", reason: "timeout"})

    assert {:error, %Ecto.Changeset{}} =
             Earnings.record_failure(%{
               acquisition_id: "missing-reason",
               issuer_code: "6857",
               url: "https://example.test/a.pdf",
               acquired_at: @at
             })

    assert {:error, :invalid_identity} =
             Earnings.record_success(%{
               success("bad-identity", "%PDF-bad", "https://example.test/a.pdf")
               | release: "unknown"
             })

    assert Earnings.original_bytes(Ecto.UUID.generate()) == :error
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

  defp assert_immutable_mutation(sql, params) do
    assert_raise Postgrex.Error, ~r/immutable/, fn ->
      Repo.transaction(fn -> Repo.query!(sql, params) end, mode: :savepoint)
    end
  end

  test "successful attempts validate required provenance on first writes and retries" do
    attrs = success("validated", "%PDF-valid", "https://example.test/a.pdf")
    assert {:ok, _} = Earnings.record_success(attrs)

    for key <- [:acquisition_id, :url, :acquired_at] do
      assert {:error, %Ecto.Changeset{}} = Earnings.record_success(Map.delete(attrs, key))
      assert {:error, %Ecto.Changeset{}} = Earnings.record_success(Map.put(attrs, key, nil))
    end

    assert Repo.aggregate(Acquisition, :count) == 1
  end

  test "cast publication attempt timestamps compare consistently across retries" do
    attrs = success("iso-time", "%PDF-time", "https://example.test/a.pdf")
    iso_attrs = %{attrs | acquired_at: DateTime.to_iso8601(@at)}
    assert {:ok, first} = Earnings.record_success(iso_attrs)
    assert {:ok, second} = Earnings.record_success(attrs)
    assert first.acquisition.id == second.acquisition.id
    failed = Map.merge(iso_attrs, %{acquisition_id: "iso-failure", reason: "timeout"})
    assert {:ok, failure} = Earnings.record_failure(failed)
    assert {:ok, ^failure} = Earnings.record_failure(%{failed | acquired_at: @at})
  end

  test "concurrent confirmations of the same identity are idempotent" do
    attrs = success("concurrent-confirm", "%PDF-confirm", "https://example.test/a.pdf")
    assert {:ok, _} = Earnings.record_success(Map.delete(attrs, :release))

    results =
      1..2
      |> Task.async_stream(fn _ -> Earnings.confirm_identity(attrs.acquisition_id, @release) end)
      |> Enum.to_list()

    assert Enum.all?(results, &match?({:ok, {:ok, _}}, &1))
    assert Repo.aggregate(Release, :count) == 1
  end
end
