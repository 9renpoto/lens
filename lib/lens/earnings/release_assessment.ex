defmodule Lens.Earnings.ReleaseAssessment do
  @moduledoc "Assess registered-source earnings releases from retained extraction evidence."
  import Ecto.Query
  alias Lens.Analysis.Target
  alias Lens.Earnings.{Acquisition, Assessments, Extractions, HTTPCheck, Identity, Source}
  alias Lens.Repo

  @doc "Append an assessment using the candidate original's latest successful extraction."
  def record(candidate_id) do
    with {:ok, id} <- Ecto.UUID.cast(candidate_id),
         %{} = candidate <- candidate(id),
         %{} = extraction <- Extractions.latest_success(candidate.original_id) do
      result = Identity.from_text(candidate.issuer, extraction.text)

      result =
        if result.fields.category == "earnings_release" and presentation_title?(extraction.text) do
          result |> put_in([:fields, :category], nil) |> Map.put(:status, :pending_confirmation)
        else
          result
        end

      {outcome, reason} = decide(result, extraction.text)

      Assessments.record(id, %{
        outcome: outcome,
        document_kind: result.fields.category,
        assessor: "earnings_release",
        assessor_version: "1",
        reason: reason,
        identity: Map.put(result.fields, :published_on, result.published_on),
        evidence: %{
          extraction_id: extraction.id,
          original_id: candidate.original_id,
          text_sha256: Base.encode16(:crypto.hash(:sha256, extraction.text), case: :lower),
          normalization: "NFKC",
          observations: observations(extraction.text)
        }
      })
    else
      nil -> {:error, :extraction_unavailable}
      _ -> {:error, :invalid_candidate}
    end
  end

  defp candidate(id) do
    Repo.one(
      from(c in HTTPCheck,
        join: a in Acquisition,
        on: a.id == c.acquisition_id,
        join: s in Source,
        on: fragment("?::text = ?->>'source_id'", s.id, c.metadata),
        join: t in Target,
        on: t.id == s.target_id,
        where:
          c.id == ^id and c.status == "success" and c.kind == "pdf" and
            a.status == "success" and not is_nil(a.original_id) and
            fragment("?::text = ?->>'target_id'", t.id, c.metadata) and
            c.issuer_code == a.issuer_code and c.issuer_code == t.security_code,
        select: %{original_id: a.original_id, issuer: t.security_code}
      )
    ) || :invalid_candidate
  end

  defp decide(%{fields: %{category: "correction"}}, _),
    do: {"excluded", "Correction document requires separate assessment"}

  defp decide(%{status: :identified, fields: %{category: "earnings_release"}}, _),
    do: {"accepted", "Explicit earnings-release title, reporting period and matching issuer"}

  defp decide(_, text) do
    if String.contains?(String.normalize(text, :nfkc), "決算短信"),
      do: {"pending", "Missing or contradictory earnings-release identity"},
      else: {"excluded", "No supported earnings-release title"}
  end

  defp observations(text) do
    text
    |> String.normalize(:nfkc)
    |> String.split(~r/\r?\n/u)
    |> Enum.filter(&Regex.match?(~r/決算短信|コード\s*番号|[0-9]{4}\s*年/u, &1))
    |> Enum.take(16)
    |> Enum.map(&String.slice(&1, 0, 256))
  end

  defp presentation_title?(text) do
    Regex.match?(
      ~r/^[ \t]*[0-9]{4}\s*年\s*[0-9]{1,2}\s*月期\s*(?:第\s*[123]\s*四半期\s*(?:\(中間期\)\s*)?)?決算説明(?:資料|会資料)[ \t]*\r?$/mu,
      String.normalize(text, :nfkc)
    )
  end
end
