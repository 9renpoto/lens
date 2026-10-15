defmodule Lens.Earnings.AssessmentsTest do
  use Lens.DataCase

  alias Lens.{Analysis, Earnings}
  alias Lens.Earnings.{Acquisition, Assessment, Assessments, HTTPCheck, HTTPHistory, Sources}

  @at ~U[2026-10-15 00:00:00.000000Z]

  test "records outcomes with acquired-document provenance and unknown or contradictory identity" do
    {target, source, candidate} = candidate()

    for outcome <- ~w(accepted excluded pending) do
      attrs = %{
        outcome: outcome,
        document_kind: "correction",
        assessor: "fixture",
        assessor_version: "1",
        reason: "Evidence retained without inferred publication date",
        identity: %{
          issuer_code: target.security_code,
          period: if(outcome == "pending", do: ["q1", "q2"], else: "q1"),
          published_on: nil
        },
        evidence: %{title: "決算短信の訂正", origin: "pdf_text"}
      }

      assert {:ok, assessment} = Assessments.record(candidate.id, attrs)
      assert assessment.http_check_id == candidate.id
      assert assessment.target_id == target.id
      assert assessment.source_id == source.id
      assert assessment.outcome == outcome
      assert assessment.identity["period"] == attrs.identity.period
      assert Map.has_key?(assessment.identity, "published_on")
      assert assessment.identity["published_on"] == nil
      assert assessment.evidence["title"] == "決算短信の訂正"
      check = Repo.get!(HTTPCheck, assessment.http_check_id)
      acquisition = Repo.get!(Acquisition, check.acquisition_id)
      assert Earnings.original_bytes(acquisition.original_id) == {:ok, "%PDF-candidate"}
      assert acquisition.release_id == nil
    end
  end

  test "pending assessment does not prevent another candidate from being assessed" do
    {_, _, pending} = candidate()
    {_, _, accepted} = candidate()

    assert [{:ok, first}, {:ok, second}] =
             Enum.map([{pending, "pending"}, {accepted, "accepted"}], fn {check, outcome} ->
               Assessments.record(check.id, attrs(outcome))
             end)

    assert first.outcome == "pending"
    assert second.outcome == "accepted"
    assert Repo.get!(Acquisition, pending.acquisition_id).release_id == nil
  end

  test "reassessment appends history without replacing confirmed identity or acquisition facts" do
    {_, source, candidate} = candidate()
    acquisition = Repo.get!(Acquisition, candidate.acquisition_id)

    identity = %{
      issuer_code: "7203",
      fiscal_year_end: ~D[2027-03-31],
      period: "q1",
      category: "earnings_release"
    }

    assert {:ok, confirmed} = Earnings.confirm_identity(acquisition.acquisition_id, identity)
    assert {:ok, first} = Assessments.record(candidate.id, attrs("accepted"))

    assert {:ok, _} =
             Sources.update(source, %{listing_url: "https://example.test/changed", enabled: false})

    assert {:ok, second} = Assessments.record(candidate.id, attrs("pending"))
    assert first.id != second.id
    assert Repo.get!(Assessment, first.id) == first
    assert Assessments.history(candidate.id) == [second, first]
    assert Assessments.history(candidate.id, 1) == [second]
    assert Repo.get!(HTTPCheck, candidate.id) == candidate
    assert Repo.get!(Acquisition, acquisition.id) == confirmed
  end

  test "rejects missing, failed, listing, legacy, and contradictory candidate provenance" do
    {target, source, candidate} = candidate()
    assert {:error, :not_found} = Assessments.record(Ecto.UUID.generate(), attrs())
    assert {:error, :invalid_candidate} = Assessments.record("invalid", attrs())

    for changes <- [
          %{kind: :listing},
          %{metadata: %{}},
          %{metadata: %{target_id: Ecto.UUID.generate(), source_id: source.id}},
          %{metadata: %{target_id: target.id, source_id: "invalid"}},
          %{
            result: %{
              outcome: :failed,
              final_url: "https://example.test/doc.pdf",
              failure_reason: :timeout,
              requests: 1,
              retryable: true
            }
          }
        ] do
      input = check_attrs(target, source) |> Map.merge(changes)
      assert {:ok, check} = HTTPHistory.record(input)
      assert {:error, :invalid_candidate} = Assessments.record(check.id, attrs())
    end

    assert {:error, :invalid_assessment} = Assessments.record(candidate.id, nil)
    assert Repo.aggregate(Assessment, :count) == 0
  end

  test "validates outcome, assessor, supported kind and bounded JSON evidence" do
    {_, _, candidate} = candidate()

    for invalid <- [
          %{outcome: "unknown"},
          %{reason: " "},
          %{assessor: nil},
          %{assessor_version: ""},
          %{document_kind: "annual_report"},
          %{document_kind: nil},
          %{identity: []},
          %{identity: %{value: {:not, :json}}},
          %{evidence: %{}},
          %{evidence: nil},
          %{evidence: %{text: String.duplicate("a", 65_537)}}
        ] do
      assert {:error, %Ecto.Changeset{valid?: false}} =
               Assessments.record(candidate.id, Map.merge(attrs(), invalid))
    end

    assert {:ok, unknown} =
             Assessments.record(candidate.id, attrs("pending") |> Map.delete(:document_kind))

    assert unknown.document_kind == nil

    assert {:ok, _} =
             Assessments.record(candidate.id, attrs("excluded") |> Map.delete(:document_kind))

    assert Repo.aggregate(Assessment, :count) == 2
  end

  test "rejects JSONB-unsafe strings and keys without aborting subsequent candidate processing" do
    {_, _, candidate} = candidate()

    for field <- [:identity, :evidence],
        value <- [
          %{"text" => "excerpt\u0000suffix"},
          %{"key\u0000" => "value"},
          %{"nested" => [%{"text" => "excerpt\u0000"}]},
          %{"nested" => [%{"key\u0000" => "value"}]}
        ] do
      assert {:error, changeset} =
               Assessments.record(candidate.id, Map.put(attrs(), field, value))

      assert %Ecto.Changeset{valid?: false} = changeset
      assert Map.has_key?(errors_on(changeset), field)
    end

    assert Repo.aggregate(Assessment, :count) == 0
    literal = %{"text" => "literal \\u0000", "observations" => [nil, "valid"]}
    assert {:ok, valid} = Assessments.record(candidate.id, Map.put(attrs(), :evidence, literal))
    assert valid.evidence == literal
  end

  test "rejects NUL characters in assessment text before database insertion" do
    {_, _, candidate} = candidate()

    for field <- [:reason, :assessor, :assessor_version] do
      assert {:error, changeset} =
               Assessments.record(candidate.id, Map.put(attrs(), field, "text\u0000suffix"))

      assert %Ecto.Changeset{valid?: false} = changeset
      assert Map.has_key?(errors_on(changeset), field)
    end

    assert {:ok, _} = Assessments.record(candidate.id, attrs())
  end

  test "stored assessment history cannot be edited or deleted" do
    {_, _, candidate} = candidate()
    assert {:ok, assessment} = Assessments.record(candidate.id, attrs())

    for sql <- [
          "UPDATE earnings_assessments SET outcome = 'excluded' WHERE id = $1",
          "DELETE FROM earnings_assessments WHERE id = $1"
        ] do
      assert {:error, %Postgrex.Error{postgres: %{code: :raise_exception}}} =
               Repo.query(sql, [Ecto.UUID.dump!(assessment.id)], mode: :savepoint)
    end

    assert Assessments.history(candidate.id) == [assessment]
  end

  test "database rejects forged provenance and invalid outcomes even without the recording module" do
    {_, _, candidate} = candidate()
    {other_target, other_source, _} = candidate()
    assert {:ok, assessment} = Assessments.record(candidate.id, attrs())

    row = assessment |> Map.from_struct() |> Map.drop([:__meta__, :http_check, :source, :target])

    for changes <- [
          %{target_id: other_target.id, source_id: other_source.id},
          %{outcome: "unknown"}
        ] do
      forged = Map.merge(row, Map.put(changes, :id, Ecto.UUID.generate()))

      assert_raise Postgrex.Error, fn ->
        Repo.insert_all(Assessment, [forged], mode: :savepoint)
      end
    end

    assert Repo.aggregate(Assessment, :count) == 1
    assert Assessments.history(candidate.id, 0) == {:error, :invalid_limit}
    assert Assessments.history(candidate.id, 101) == {:error, :invalid_limit}
    assert Assessments.history("invalid") == []
  end

  defp attrs(outcome \\ "accepted") do
    %{
      outcome: outcome,
      document_kind: "earnings_release",
      assessor: "fixture",
      assessor_version: "1",
      reason: "Explicit title and issuer",
      evidence: %{title: "決算短信", issuer_code: "7203"}
    }
  end

  defp candidate do
    {:ok, target} =
      Analysis.create_target(%{
        security_code: "T#{System.unique_integer([:positive])}",
        market: "TSE",
        display_name: "Example",
        sector: "Test",
        active: false
      })

    {:ok, source} = Sources.create(target, %{listing_url: "https://example.test/results"})
    {:ok, check} = HTTPHistory.record(check_attrs(target, source))
    {target, source, check}
  end

  defp check_attrs(target, source) do
    %{
      check_id: Ecto.UUID.generate(),
      issuer_code: target.security_code,
      url: "https://example.test/doc.pdf",
      kind: :pdf,
      checked_at: @at,
      metadata: %{target_id: target.id, source_id: source.id, listing_url: source.listing_url},
      result: %{
        outcome: :success,
        bytes: "%PDF-candidate",
        final_url: "https://example.test/doc.pdf",
        http_status: 200,
        requests: 1,
        retryable: false
      }
    }
  end
end
