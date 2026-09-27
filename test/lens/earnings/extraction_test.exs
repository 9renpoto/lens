defmodule Lens.Earnings.ExtractionTest do
  use Lens.DataCase

  alias Lens.Earnings
  alias Lens.Earnings.Extractions

  test "equal acquisition times use original UUID and unrelated releases stay separate" do
    a = retain("tie-a", 0)
    b = retain("tie-b", 0)
    c = retain("other-release", 600, %{identity() | period: "q2"})

    for retained <- [a, b, c] do
      assert {:ok, attempt} = Extractions.begin(retained.original.id, "fixture", "1")
      assert {:ok, _} = Extractions.succeed(attempt.id, retained.original.sha256)
    end

    expected_id = max(a.original.id, b.original.id)
    assert {:ok, result} = Extractions.release_text(a.release.id)
    assert result.latest_original_id == expected_id
    assert result.extraction.original_id == expected_id
    refute result.stale
    assert {:ok, other} = Extractions.release_text(c.release.id)
    assert other.extraction.original_id == c.original.id
  end

  test "release without eligible originals has no extracted text" do
    release =
      %Lens.Earnings.Release{}
      |> Lens.Earnings.Release.changeset(Map.put(identity(), :issuer_code, "6857"))
      |> Repo.insert!()

    assert {:ok, %{extraction: nil, latest_original_id: nil, latest_attempt: nil, stale: false}} =
             Extractions.release_text(release.id)
  end

  test "empty and invalid UTF-8 text cannot finish an attempt" do
    retained = retain("validation", 0)
    assert {:ok, attempt} = Extractions.begin(retained.original.id, "fixture", "1")
    assert {:error, :invalid_text} = Extractions.succeed(attempt.id, " \n\t")
    assert {:error, :invalid_text} = Extractions.succeed(attempt.id, <<255>>)
    assert {:error, :invalid_text} = Extractions.succeed(attempt.id, nil)
    assert {:error, :invalid_text} = Extractions.succeed(attempt.id, "Text\0suffix")
    assert {:error, :invalid_reason} = Extractions.fail(attempt.id, " ")
    assert {:error, :invalid_reason} = Extractions.fail(attempt.id, nil)
    assert {:error, :invalid_reason} = Extractions.fail(attempt.id, "failure\0suffix")
    assert Repo.get!(Lens.Earnings.Extraction, attempt.id).status == "pending"
    assert {:ok, _} = Extractions.fail(attempt.id, "empty_output")
    assert {:error, :not_pending} = Extractions.succeed(attempt.id, "Late text")
    assert {:error, changeset} = Extractions.begin(Ecto.UUID.generate(), "fixture", "1")
    assert errors_on(changeset).original_id == ["does not exist"]
  end

  test "release selection keeps earlier text stale until the newer original succeeds" do
    old = retain("old", 0)
    new = retain("new", 60)
    assert old.release.id == new.release.id
    assert {:ok, %{extraction: nil, stale: false}} = Extractions.release_text(old.release.id)
    assert {:ok, first} = Extractions.begin(old.original.id, "fixture", "1")
    assert {:ok, _} = Extractions.succeed(first.id, "Earlier text")
    assert {:ok, failed} = Extractions.begin(new.original.id, "fixture", "1")
    assert {:ok, _} = Extractions.fail(failed.id, "unreadable")
    assert {:ok, result} = Extractions.release_text(old.release.id)
    assert result.extraction.id == first.id
    assert result.stale
    assert result.latest_original_id == new.original.id
    assert result.latest_attempt.status == "failed"

    # Reacquiring the old bytes must not promote that original.
    retain("old", 120)
    assert {:ok, %{stale: true}} = Extractions.release_text(old.release.id)
    assert {:ok, newer} = Extractions.begin(new.original.id, "fixture", "2")
    assert {:ok, _} = Extractions.succeed(newer.id, "Current text")
    assert {:ok, delayed} = Extractions.begin(old.original.id, "fixture", "2")
    assert {:ok, _} = Extractions.succeed(delayed.id, "Late old text")
    assert {:ok, result} = Extractions.release_text(old.release.id)
    assert result.extraction.id == newer.id
    refute result.stale
  end

  test "unconfirmed acquisitions do not make extracted text eligible" do
    known = retain("known", 0)
    unknown = retain("unknown", 60, nil)
    assert {:ok, attempt} = Extractions.begin(unknown.original.id, "fixture", "1")
    assert {:ok, _} = Extractions.succeed(attempt.id, "Pending identity")

    assert {:ok, %{extraction: nil, latest_original_id: id}} =
             Extractions.release_text(known.release.id)

    assert id == known.original.id
    assert {:ok, _} = Earnings.confirm_identity(unknown.acquisition.acquisition_id, identity())
    assert {:ok, result} = Extractions.release_text(known.release.id)
    assert result.extraction.id == attempt.id
    refute result.stale
    assert {:error, :not_found} = Extractions.release_text(Ecto.UUID.generate())
  end

  defp identity do
    %{fiscal_year_end: ~D[2027-03-31], period: "q1", category: "earnings_release"}
  end

  defp retain(bytes, seconds, release \\ identity()) do
    assert {:ok, retained} =
             Earnings.record_success(%{
               acquisition_id: "#{bytes}-#{seconds}",
               issuer_code: "6857",
               url: "https://example.test/#{bytes}.pdf",
               acquired_at: DateTime.add(~U[2026-09-26 01:00:00.000000Z], seconds),
               bytes: "%PDF-#{bytes}",
               release: release
             })

    retained
  end

  test "failed regeneration preserves successful text and immutable originals" do
    bytes = "%PDF-retained"

    assert {:ok, %{original: original}} =
             Earnings.record_success(%{
               acquisition_id: "extraction-fixture",
               issuer_code: "6857",
               url: "https://example.test/earnings.pdf",
               acquired_at: ~U[2026-09-26 01:00:00.000000Z],
               bytes: bytes
             })

    assert {:ok, first} = Extractions.begin(original.id, "fixture", "1")
    assert first.status == "pending"
    assert {:ok, success} = Extractions.succeed(first.id, "売上高\n\n営業利益")
    assert success.status == "succeeded"

    assert {:ok, retry} = Extractions.begin(original.id, "fixture", "2")
    assert {:ok, failure} = Extractions.fail(retry.id, "timeout")
    assert failure.status == "failed"
    assert Extractions.latest_success(original.id).id == first.id
    assert Earnings.original_bytes(original.id) == {:ok, bytes}
    assert Repo.aggregate(Lens.Earnings.Acquisition, :count) == 1
  end

  test "completion order cannot replace a newer successful attempt" do
    assert {:ok, %{original: original}} =
             Earnings.record_success(%{
               acquisition_id: "ordering-fixture",
               issuer_code: "6857",
               url: "https://example.test/ordering.pdf",
               acquired_at: ~U[2026-09-26 01:00:00.000000Z],
               bytes: "%PDF-ordering"
             })

    assert {:ok, older} = Extractions.begin(original.id, "fixture", "1")
    assert {:ok, newer} = Extractions.begin(original.id, "fixture", "2")
    assert {:ok, _} = Extractions.succeed(newer.id, "New text")
    assert {:ok, _} = Extractions.succeed(older.id, "Old text")
    assert Extractions.latest_success(original.id).id == newer.id
    assert {:error, :not_pending} = Extractions.fail(newer.id, "timeout")
  end
end
