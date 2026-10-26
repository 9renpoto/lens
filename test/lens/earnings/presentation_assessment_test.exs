defmodule Lens.Earnings.PresentationAssessmentTest do
  use Lens.DataCase
  alias Lens.{Analysis, Earnings}

  alias Lens.Earnings.{
    Acquisition,
    Assessments,
    Extractions,
    PresentationAssessment,
    ReleaseAssessment,
    Sources
  }

  @fixtures "test/fixtures/earnings/presentations.json" |> File.read!() |> Jason.decode!()

  setup do
    {:ok, target} =
      Analysis.create_target(%{
        security_code: "SYNX",
        market: "TSE",
        display_name: "Example",
        sector: "Test",
        active: false
      })

    {:ok, source} = Sources.create(target, %{listing_url: "https://example.test/results"})
    %{target: target, source: source}
  end

  test "records presentation evidence and history without changing an operator-confirmed acquisition",
       ctx do
    {check, acquisition, extraction} = candidate(ctx, @fixtures["supported"])

    {:ok, confirmed} =
      Earnings.confirm_identity(acquisition.acquisition_id, %{
        issuer_code: "SYNX",
        fiscal_year_end: ~D[2028-12-31],
        period: "q2",
        category: "earnings_presentation"
      })

    before = Repo.get!(Acquisition, acquisition.id)
    before_bytes = Earnings.original_bytes(acquisition.original_id)
    assert before.release_id == confirmed.release_id
    assert {:ok, assessment} = PresentationAssessment.record(check.id)
    assert assessment.outcome == "accepted"
    assert assessment.document_kind == "earnings_presentation"
    assert assessment.target_id == ctx.target.id
    assert assessment.source_id == ctx.source.id
    assert assessment.identity["issuer_code"] == "SYNX"
    assert assessment.identity["fiscal_year_end"] == "2028-12-31"
    assert assessment.identity["period"] == "q2"
    assert assessment.evidence["extraction_id"] == extraction.id
    assert assessment.evidence["original_id"] == acquisition.original_id

    assert assessment.evidence["text_sha256"] ==
             Base.encode16(:crypto.hash(:sha256, extraction.text), case: :lower)

    assert {:ok, repeated} = PresentationAssessment.record(check.id)
    assert [^repeated, ^assessment] = Assessments.history(check.id)
    assert Repo.get!(Acquisition, acquisition.id) == before
    assert Earnings.original_bytes(acquisition.original_id) == before_bytes
  end

  test "other document kinds are excluded and unknown presentation identity stays pending", ctx do
    for {name, outcome, kind} <- [
          {"regular", "excluded", nil},
          {"correction", "excluded", nil},
          {"unrelated", "excluded", nil},
          {"ambiguous", "pending", "earnings_presentation"}
        ] do
      {check, acquisition, _} = candidate(ctx, @fixtures[name])
      assert {:ok, assessment} = PresentationAssessment.record(check.id)
      assert assessment.outcome == outcome
      assert assessment.document_kind == kind
      assert Repo.get!(Acquisition, acquisition.id) == acquisition
    end
  end

  test "explicit title layouts support full years, quarters, normalization and CRLF", ctx do
    for {title, year_end, period} <- [
          {"2028年2月期 決算説明資料", "2028-02-29", "full_year"},
          {"２０２８年１２月期　第１四半期決算説明資料", "2028-12-31", "q1"},
          {"2028年12月期 第3四半期決算説明会資料", "2028-12-31", "q3"}
        ] do
      {check, _, _} = candidate(ctx, title <> "\r\nコード番号：ＳＹＮＸ\r\n")
      assert {:ok, assessment} = PresentationAssessment.record(check.id)
      assert assessment.outcome == "accepted"
      assert assessment.identity["fiscal_year_end"] == year_end
      assert assessment.identity["period"] == period
      assert {:ok, regular} = ReleaseAssessment.record(check.id)
      refute regular.outcome == "accepted"
    end
  end

  test "missing, contradictory or unsupported identity is never inferred from the registered URL",
       ctx do
    for text <- [
          String.replace(@fixtures["supported"], "SYNX", "SYNY"),
          String.replace(@fixtures["supported"], "コード番号 SYNX", ""),
          @fixtures["supported"] <> "\nコード番号 SYNY",
          @fixtures["supported"] <> "\n2029年12月期 第2四半期決算説明資料",
          @fixtures["supported"] <> "\n2028年12月期 第1四半期決算説明資料",
          "2028年13月期 決算説明資料\nコード番号 SYNX",
          "2028年12月期 第1四半期（中間期）決算説明資料\nコード番号 SYNX",
          "2028年12月期 第4四半期決算説明資料\nコード番号 SYNX",
          @fixtures["supported"] <> "\n" <> @fixtures["regular"],
          @fixtures["supported"] <> "\n" <> @fixtures["correction"]
        ] do
      {check, acquisition, _} = candidate(ctx, text)
      assert {:ok, assessment} = PresentationAssessment.record(check.id)
      assert assessment.outcome == "pending"
      assert Repo.get!(Acquisition, acquisition.id).release_id == nil
    end
  end

  test "a presentation reference in prose does not establish a presentation title", ctx do
    {check, _, _} = candidate(ctx, @fixtures["regular"] <> "\n詳細は2028年12月期 第2四半期決算説明資料をご参照ください。")
    assert {:ok, assessment} = PresentationAssessment.record(check.id)
    assert assessment.outcome == "excluded"
  end

  test "a line-wrapped reference does not establish a presentation title", ctx do
    {check, _, _} = candidate(ctx, @fixtures["regular"] <> "\n2028年12月期 第2四半期決算説明資料\nをご参照ください。")
    assert {:ok, assessment} = PresentationAssessment.record(check.id)
    assert assessment.outcome == "excluded"
    assert {:ok, regular} = ReleaseAssessment.record(check.id)
    assert regular.outcome == "accepted"
  end

  test "competing standalone and unsupported presentation headings cannot become regular releases",
       ctx do
    for heading <- ["決算説明資料", "2028年12月期 第4四半期決算説明会資料"] do
      {check, _, _} = candidate(ctx, @fixtures["regular"] <> "\n" <> heading)
      assert {:ok, assessment} = ReleaseAssessment.record(check.id)
      assert assessment.outcome == "pending"
      refute assessment.document_kind == "earnings_release"
    end
  end

  test "decisions use complete text while stored evidence is bounded", ctx do
    text = String.duplicate(@fixtures["supported"] <> "\n", 300) <> "コード番号 SYNY\n"
    {check, _, _} = candidate(ctx, text)
    assert {:ok, assessment} = PresentationAssessment.record(check.id)
    assert assessment.outcome == "pending"
    assert assessment.identity["issuer_code"] == nil
    assert byte_size(Jason.encode!(assessment.evidence)) < 65_536
  end

  test "uses the latest successful extraction and ignores newer incomplete attempts", ctx do
    {check, acquisition, _} = candidate(ctx, @fixtures["regular"])
    {:ok, latest} = Extractions.begin(acquisition.original_id, "fixture", "2")
    {:ok, latest} = Extractions.succeed(latest.id, @fixtures["supported"])
    {:ok, _} = Extractions.begin(acquisition.original_id, "fixture", "3")
    assert {:ok, assessment} = PresentationAssessment.record(check.id)
    assert assessment.outcome == "accepted"
    assert assessment.evidence["extraction_id"] == latest.id
  end

  test "rejects missing extraction and invalid or mismatched candidate provenance", ctx do
    assert {:error, :invalid_candidate} = PresentationAssessment.record("invalid")
    assert {:error, :invalid_candidate} = PresentationAssessment.record(Ecto.UUID.generate())
    {check, acquisition, _} = candidate(ctx, nil)
    assert {:error, :extraction_unavailable} = PresentationAssessment.record(check.id)
    {:ok, _} = Extractions.begin(acquisition.original_id, "fixture", "1")
    assert {:error, :extraction_unavailable} = PresentationAssessment.record(check.id)

    {other, _, _} =
      candidate(%{ctx | target: %{ctx.target | security_code: "SYNY"}}, @fixtures["supported"])

    assert {:error, :invalid_candidate} = PresentationAssessment.record(other.id)
    assert Assessments.history(other.id) == []
  end

  defp candidate(ctx, text) do
    id = Ecto.UUID.generate()

    {:ok, check} =
      Lens.StorageFixtures.record_http(%{
        check_id: id,
        issuer_code: ctx.target.security_code,
        url: "https://example.test/2028-q2-presentation.pdf",
        kind: :pdf,
        checked_at: DateTime.utc_now(),
        metadata: %{target_id: ctx.target.id, source_id: ctx.source.id},
        result: %{
          outcome: :success,
          bytes: "%PDF-#{id}",
          final_url: "https://example.test/2028-q2-presentation.pdf",
          http_status: 200,
          requests: 1,
          retryable: false
        }
      })

    acquisition = Repo.get!(Acquisition, check.acquisition_id)

    extraction =
      if text do
        {:ok, extraction} = Extractions.begin(acquisition.original_id, "fixture", "1")
        {:ok, extraction} = Extractions.succeed(extraction.id, text)
        extraction
      end

    {check, acquisition, extraction}
  end
end
