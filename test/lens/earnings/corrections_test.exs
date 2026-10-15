defmodule Lens.Earnings.CorrectionsTest do
  use Lens.DataCase

  alias Lens.{Analysis, Earnings}
  alias Lens.Earnings.{Acquisition, Assessments, Corrections, Extractions, HTTPHistory, Sources}

  @fixtures "test/fixtures/earnings/corrections.json" |> File.read!() |> Jason.decode!()
  @at ~U[2026-08-08 00:00:00.000000Z]

  setup do
    {:ok, target} =
      Analysis.create_target(%{
        security_code: "7203",
        market: "TSE",
        display_name: "Example",
        sector: "Test"
      })

    {:ok, source} = Sources.create(target, %{listing_url: "https://example.test/results"})
    %{target: target, source: source}
  end

  test "records a known correction and its supported earlier release without changing acquisition",
       ctx do
    {original, _} = candidate(ctx, @fixtures["regular"], ~U[2026-08-06 00:00:00.000000Z])

    {:ok, earlier} =
      Earnings.confirm_identity(acquisition(original).acquisition_id, %{
        issuer_code: "7203",
        fiscal_year_end: ~D[2027-03-31],
        period: "q1",
        category: "earnings_release"
      })

    {check, extraction} = candidate(ctx, @fixtures["known"])
    before = acquisition(check)
    assert {:ok, assessment} = Corrections.assess(check.id, extraction.id)
    assert assessment.outcome == "accepted"
    assert assessment.document_kind == "correction"
    assert assessment.target_id == ctx.target.id
    assert assessment.identity["corrects_release_id"] == earlier.release_id
    assert assessment.identity["fiscal_year_end"] == "2027-03-31"
    assert assessment.evidence["extraction_id"] == extraction.id
    assert assessment.evidence["relationship"]["referenced_publication_date"] == "2026-08-05"
    assert acquisition(check) == before
    assert {:ok, second} = Corrections.assess(check.id, extraction.id)
    assert second.id != assessment.id
    assert Assessments.history(check.id) == [second, assessment]
  end

  test "ambiguous relationship stays pending while unrelated and ordinary documents are excluded",
       ctx do
    for {fixture, outcome, kind} <- [
          {"ambiguous", "pending", "correction"},
          {"known", "pending", "correction"},
          {"unrelated", "excluded", nil},
          {"regular", "excluded", nil}
        ] do
      {check, extraction} = candidate(ctx, @fixtures[fixture])
      assert {:ok, assessment} = Corrections.assess(check.id, extraction.id)
      assert assessment.outcome == outcome
      assert assessment.document_kind == kind
      assert assessment.identity["corrects_release_id"] == nil
      assert acquisition(check).release_id == nil
    end
  end

  test "contradictory issuer and reporting identity stay pending with observations", ctx do
    for text <- [
          @fixtures["known"] <> "\nコード番号 8035",
          @fixtures["known"] <> "\n（訂正）2027年3月期 第2四半期決算短信"
        ] do
      {check, extraction} = candidate(ctx, text)
      assert {:ok, assessment} = Corrections.assess(check.id, extraction.id)
      assert assessment.outcome == "pending"
      assert assessment.identity["corrects_release_id"] == nil
      assert assessment.evidence["observations"] != %{}
    end
  end

  test "rejects another original's extraction, failed extraction and invalid identifiers", ctx do
    {first, extraction} = candidate(ctx, @fixtures["known"])
    {second, _} = candidate(ctx, @fixtures["unrelated"])
    assert {:error, :invalid_extraction} = Corrections.assess(second.id, extraction.id)
    {:ok, pending} = Extractions.begin(acquisition(first).original_id, "fixture", "1")
    assert {:error, :invalid_extraction} = Corrections.assess(first.id, pending.id)
    assert {:error, :invalid_candidate} = Corrections.assess("invalid", extraction.id)
    assert {:error, :invalid_extraction} = Corrections.assess(first.id, -1)
    assert Assessments.history(first.id) == []
  end

  test "date conflicts and unsupported relationships remain pending even when a release exists",
       ctx do
    {original, _} = candidate(ctx, @fixtures["regular"], ~U[2026-08-06 00:00:00.000000Z])

    {:ok, _} =
      Earnings.confirm_identity(acquisition(original).acquisition_id, %{
        issuer_code: "7203",
        fiscal_year_end: ~D[2027-03-31],
        period: "q1",
        category: "earnings_release"
      })

    for text <- [
          String.replace(@fixtures["known"], "2026年8月5日に", "2026年8月4日に"),
          String.replace(@fixtures["known"], "2026年8月7日", "2026年8月4日"),
          @fixtures["known"] <> "\n2026年8月4日に公表した決算短信を訂正します。",
          String.replace(@fixtures["known"], "2026年8月7日\n", ""),
          String.replace(@fixtures["known"], "第1四半期", "第2四半期"),
          String.replace(@fixtures["known"], "第1四半期", "第1四半期(中間期)")
        ] do
      {check, extraction} = candidate(ctx, text)
      assert {:ok, assessment} = Corrections.assess(check.id, extraction.id)
      assert assessment.outcome == "pending"
      assert assessment.identity["corrects_release_id"] == nil
    end
  end

  test "full-year corrections support fiscal months outside the pilot assumptions", ctx do
    regular = @fixtures["regular"] |> String.replace("2027年3月期 第1四半期", "2026年12月期")
    correction = @fixtures["known"] |> String.replace("2027年3月期 第1四半期", "2026年12月期")
    {original, _} = candidate(ctx, regular, ~U[2026-08-06 00:00:00.000000Z])

    {:ok, earlier} =
      Earnings.confirm_identity(acquisition(original).acquisition_id, %{
        issuer_code: "7203",
        fiscal_year_end: ~D[2026-12-31],
        period: "full_year",
        category: "earnings_release"
      })

    {check, extraction} = candidate(ctx, correction)
    assert {:ok, assessment} = Corrections.assess(check.id, extraction.id)
    assert assessment.outcome == "accepted"
    assert assessment.identity["period"] == "full_year"
    assert assessment.identity["corrects_release_id"] == earlier.release_id
  end

  test "unsupported correction heading cannot substantiate an earlier regular release", ctx do
    text = "(訂正版)\n" <> @fixtures["regular"]
    {original, _} = candidate(ctx, text, ~U[2026-08-06 00:00:00.000000Z])

    {:ok, _} =
      Earnings.confirm_identity(acquisition(original).acquisition_id, %{
        issuer_code: "7203",
        fiscal_year_end: ~D[2027-03-31],
        period: "q1",
        category: "earnings_release"
      })

    {check, extraction} = candidate(ctx, @fixtures["known"])
    assert {:ok, assessment} = Corrections.assess(check.id, extraction.id)
    assert assessment.outcome == "pending"
    assert assessment.identity["corrects_release_id"] == nil
  end

  test "long recognized headings retain bounded evidence and do not prevent pending recording",
       ctx do
    text =
      String.replace(
        @fixtures["known"],
        "決算短信」の",
        "決算短信〔" <> String.duplicate("注", 30_000) <> "〕」の"
      )

    {check, extraction} = candidate(ctx, text)
    assert {:ok, assessment} = Corrections.assess(check.id, extraction.id)
    assert assessment.outcome == "pending"
    assert byte_size(Jason.encode!(assessment.evidence)) < 65_536
    assert assessment.evidence["extraction_id"] == extraction.id
  end

  defp candidate(ctx, text, at \\ @at) do
    {:ok, check} =
      HTTPHistory.record(%{
        check_id: Ecto.UUID.generate(),
        issuer_code: ctx.target.security_code,
        url: "https://example.test/#{Ecto.UUID.generate()}.pdf",
        kind: :pdf,
        checked_at: at,
        metadata: %{target_id: ctx.target.id, source_id: ctx.source.id},
        result: %{
          outcome: :success,
          bytes: "%PDF-" <> text,
          final_url: "https://example.test/doc.pdf",
          http_status: 200,
          requests: 1,
          retryable: false
        }
      })

    {:ok, attempt} = Extractions.begin(acquisition(check).original_id, "fixture", "1")
    {:ok, extraction} = Extractions.succeed(attempt.id, text)
    {check, extraction}
  end

  defp acquisition(check), do: Repo.get!(Acquisition, check.acquisition_id)
end
