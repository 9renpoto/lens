defmodule Lens.Earnings.PresentationAssessment do
  @moduledoc "Assess retained presentation text separately from ordinary earnings releases."
  import Ecto.Query
  alias Lens.Analysis.Target
  alias Lens.Earnings.{Acquisition, Assessments, Extractions, HTTPCheck, Identity, Source}
  alias Lens.Repo

  @heading ~r/^(?:\(訂正\)\s*)?(?:[0-9]{4}[^\r\n]*月期[^\r\n]*)?決算説明(?:会資料|資料|会)(?:\s*(?:〔[^〕]*〕|\([^)]*\)))*$/u
  @title ~r/^(?<year>[0-9]{4})\s*年\s*(?<month>[0-9]{1,2})\s*月期\s*(?:第\s*(?<quarter>[123])\s*四半期\s*(?<interim>\(中間期\))?\s*)?決算説明(?:会資料|資料)$/u

  @doc "Append an assessment using the candidate original's latest successful extraction."
  def record(candidate_id) do
    with {:ok, id} <- Ecto.UUID.cast(candidate_id),
         %{} = candidate <- candidate(id),
         %{} = extraction <- Extractions.latest_success(candidate.original_id) do
      lines = lines(extraction.text)
      headings = headings(extraction.text)
      identity = Identity.from_text(candidate.issuer, extraction.text)
      {year_end, period} = headings |> Enum.map(&reporting_identity/1) |> unique_reporting()

      competing? =
        Enum.any?(
          lines,
          &Regex.match?(~r/^(?:\(訂正\)\s*)?「?[0-9]{4}.*決算短信|^(?:一部|決算数値の)訂正に関するお知らせ$/u, &1)
        )

      {outcome, reason} =
        decide(
          headings,
          identity.fields.issuer_code == candidate.issuer,
          year_end,
          period,
          competing?
        )

      Assessments.record(id, %{
        outcome: outcome,
        document_kind: if(headings != [], do: "earnings_presentation"),
        assessor: "earnings_presentation",
        assessor_version: "1",
        reason: reason,
        identity: %{
          issuer_code: identity.fields.issuer_code,
          fiscal_year_end: year_end,
          period: period,
          category: if(headings != [], do: "earnings_presentation"),
          published_on: identity.published_on
        },
        evidence: %{
          extraction_id: extraction.id,
          original_id: candidate.original_id,
          text_sha256: Base.encode16(:crypto.hash(:sha256, extraction.text), case: :lower),
          normalization: "NFKC",
          observations:
            lines
            |> Enum.filter(&Regex.match?(~r/決算|訂正|コード\s*番号|[0-9]{4}\s*年/u, &1))
            |> Enum.take(16)
            |> Enum.map(&String.slice(&1, 0, 256))
        }
      })
    else
      nil -> {:error, :extraction_unavailable}
      _ -> {:error, :invalid_candidate}
    end
  end

  @doc false
  def heading?(text), do: headings(text) != []

  defp headings(text) do
    nonempty = text |> lines() |> Enum.reject(&(&1 == ""))

    nonempty
    |> Enum.zip(Enum.drop(nonempty, 1) ++ [""])
    |> Enum.filter(fn {line, following} ->
      Regex.match?(@heading, line) and
        not Regex.match?(~r/^(?:の|[をにはがともでへ]|ご参照|参照|記載|掲載)/u, following)
    end)
    |> Enum.map(&elem(&1, 0))
  end

  defp lines(text),
    do: text |> String.normalize(:nfkc) |> String.split(~r/\r?\n/u) |> Enum.map(&String.trim/1)

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

  defp reporting_identity(heading) do
    case Regex.named_captures(@title, heading) do
      %{"year" => year, "month" => month, "quarter" => quarter, "interim" => interim} ->
        year_end =
          case Date.new(String.to_integer(year), String.to_integer(month), 1) do
            {:ok, date} when date.year > 0 -> Date.end_of_month(date)
            _ -> nil
          end

        period =
          if interim == "" or quarter == "2",
            do: if(quarter == "", do: "full_year", else: "q" <> quarter)

        {year_end, period}

      nil ->
        {nil, nil}
    end
  end

  defp unique_reporting(values) do
    {years, periods} = Enum.unzip(values)
    {unique_value(years), unique_value(periods)}
  end

  defp unique_value(values) do
    case Enum.uniq(values) do
      [value] -> value
      _ -> nil
    end
  end

  defp decide([], _, _, _, _), do: {"excluded", "No supported presentation heading"}

  defp decide(_, true, year_end, period, false) when not is_nil(year_end) and not is_nil(period),
    do: {"accepted", "Explicit presentation title, reporting period and matching issuer"}

  defp decide(_, _, _, _, _),
    do:
      {"pending", "Missing, unsupported or contradictory presentation identity or document kind"}
end
