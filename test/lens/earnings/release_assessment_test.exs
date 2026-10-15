defmodule Lens.Earnings.ReleaseAssessmentTest do
  use Lens.DataCase
  alias Lens.{Analysis, Earnings}

  alias Lens.Earnings.{
    Acquisition,
    Assessments,
    Extractions,
    HTTPHistory,
    ReleaseAssessment,
    Sources
  }

  test "records supported, ambiguous and unrelated retained documents without adopting releases" do
    {:ok, target} =
      Analysis.create_target(%{
        security_code: "1234",
        market: "TSE",
        display_name: "Example",
        sector: "Test",
        active: false
      })

    {:ok, source} = Sources.create(target, %{listing_url: "https://example.test/results"})

    for {name, outcome} <- [
          {"supported", "accepted"},
          {"conflict", "pending"},
          {"unrelated", "excluded"},
          {"presentation", "excluded"},
          {"issuer_conflict", "pending"},
          {"year_conflict", "pending"},
          {"missing_issuer", "pending"},
          {"correction", "excluded"},
          {"mixed_kind", "pending"}
        ] do
      text = File.read!(Path.join("test/fixtures/earnings/assessment", name <> ".txt"))

      {:ok, check} =
        HTTPHistory.record(%{
          check_id: Ecto.UUID.generate(),
          issuer_code: target.security_code,
          url: "https://example.test/#{name}.pdf",
          kind: :pdf,
          checked_at: DateTime.utc_now(),
          metadata: %{target_id: target.id, source_id: source.id},
          result: %{
            outcome: :success,
            bytes: "%PDF-#{name}",
            final_url: "https://example.test/#{name}.pdf",
            http_status: 200,
            requests: 1,
            retryable: false
          }
        })

      acquisition = Repo.get!(Acquisition, check.acquisition_id)
      assert {:error, :extraction_unavailable} = ReleaseAssessment.record(check.id)
      {:ok, extraction} = Extractions.begin(acquisition.original_id, "fixture", "1")
      {:ok, extraction} = Extractions.succeed(extraction.id, text)
      assert {:ok, assessment} = ReleaseAssessment.record(check.id)
      assert assessment.outcome == outcome
      assert assessment.evidence["extraction_id"] == extraction.id
      assert assessment.evidence["original_id"] == acquisition.original_id

      assert assessment.evidence["text_sha256"] ==
               Base.encode16(:crypto.hash(:sha256, text), case: :lower)

      assert [^assessment] = Assessments.history(check.id)
      assert {:ok, repeated} = ReleaseAssessment.record(check.id)
      assert repeated.id != assessment.id
      assert [^repeated, ^assessment] = Assessments.history(check.id)
      assert Repo.get!(Acquisition, acquisition.id).release_id == nil
      assert Earnings.original_bytes(acquisition.original_id) == {:ok, "%PDF-#{name}"}

      if outcome == "accepted" do
        assert assessment.document_kind == "earnings_release"
        assert assessment.identity["issuer_code"] == "1234"
        assert assessment.identity["fiscal_year_end"] == "2026-12-31"
        assert assessment.identity["period"] == "q2"
        assert assessment.identity["published_on"] == nil
      end
    end
  end

  test "rejects invalid and unknown candidates" do
    assert {:error, :invalid_candidate} = ReleaseAssessment.record("invalid")
    assert {:error, :invalid_candidate} = ReleaseAssessment.record(Ecto.UUID.generate())
  end
end
