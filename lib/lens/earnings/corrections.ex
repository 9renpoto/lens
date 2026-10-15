defmodule Lens.Earnings.Corrections do
  @moduledoc "Conservative correction assessment using retained extraction evidence."
  import Ecto.Query
  alias Lens.Earnings.{Acquisition, Assessments, Extraction, HTTPCheck, Release, Source}
  alias Lens.Analysis.Target
  alias Lens.Repo

  @title ~r/^(?:\(訂正\)\s*)?「?([0-9]{4})\s*年\s*([0-9]{1,2})\s*月期\s*(?:第\s*([123])\s*四半期\s*(\(中間期\))?\s*)?決算短信(?:〔[^〕]*〕|\([^)]*\))*」?(?:の(?:一部|決算数値の)?訂正に関するお知らせ)?$/u
  @correction ~r/^(?:\(訂正\)\s*「?[0-9]{4}.*決算短信.*|「[0-9]{4}.*決算短信.*」の(?:一部|決算数値の)?訂正に関するお知らせ|(?:一部|決算数値の)訂正に関するお知らせ)$/u
  @date ~r/^([0-9]{4})年([0-9]{1,2})月([0-9]{1,2})日$/u
  @reference ~r/^([0-9]{4})年([0-9]{1,2})月([0-9]{1,2})日に公表した決算短信を訂正します。?$/u

  @doc "Append a correction assessment of an existing successful extraction of this candidate."
  def assess(candidate_id, extraction_id) do
    with {:ok, id} <- Ecto.UUID.cast(candidate_id),
         %{} = candidate <- candidate(id),
         {:ok, extraction} <- extraction(candidate, extraction_id) do
      observations = observe(extraction.text)
      {outcome, reason, linked} = decide(candidate, observations)
      identity = Map.put(observations.identity, :corrects_release_id, linked && linked.release_id)

      Assessments.record(id, %{
        outcome: outcome,
        document_kind: if(observations.correction?, do: "correction"),
        assessor: "earnings_correction",
        assessor_version: "1",
        reason: reason,
        identity: identity,
        evidence: %{
          extraction_id: extraction.id,
          normalization: "NFKC",
          observations: bounded_evidence(observations.evidence),
          relationship: linked
        }
      })
    else
      {:error, :invalid_extraction} = error -> error
      _ -> {:error, :invalid_candidate}
    end
  end

  defp bounded_evidence(observations) do
    counts = Map.new(observations, fn {key, values} -> {key, length(values)} end)

    observations
    |> Map.new(fn {key, values} ->
      {key,
       values
       |> Enum.take(8)
       |> Enum.map(fn
         value when is_binary(value) -> String.slice(value, 0, 128)
         value -> value
       end)}
    end)
    |> Map.put(:observation_counts, counts)
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
        select: %{original_id: a.original_id, acquired_at: a.acquired_at, issuer: t.security_code}
      )
    )
  end

  defp extraction(candidate, id) when is_integer(id) and id > 0 do
    case Repo.get(Extraction, id) do
      %Extraction{status: "succeeded", original_id: original_id} = extraction
      when original_id == candidate.original_id ->
        {:ok, extraction}

      _ ->
        {:error, :invalid_extraction}
    end
  end

  defp extraction(_, _), do: {:error, :invalid_extraction}

  defp observe(text) do
    lines =
      text |> String.normalize(:nfkc) |> String.split(~r/\r?\n/u) |> Enum.map(&String.trim/1)

    titles = Enum.filter(lines, &Regex.match?(@title, &1))
    fields = Enum.map(titles, &title_identity/1)

    codes =
      Regex.scan(~r/コード\s*番号\s*[:：]?\s*([0-9A-Z]{4})(?![0-9A-Z])/u, Enum.join(lines, "\n"),
        capture: :all_but_first
      )
      |> List.flatten()
      |> Enum.uniq()

    header = Enum.take_while(lines, &(not String.contains?(&1, "コード")))
    published = dates(header, @date)
    references = dates(lines, @reference)
    years = Enum.map(fields, & &1.fiscal_year_end) |> Enum.uniq()
    periods = Enum.map(fields, & &1.period) |> Enum.uniq()

    %{
      correction?: Enum.any?(lines, &correction_heading?/1),
      supported?: Enum.any?(lines, &Regex.match?(@correction, &1)),
      identity: %{
        issuer_code: one(codes),
        fiscal_year_end: one(years),
        period: one(periods),
        published_on: one(published),
        referenced_publication_date: one(references)
      },
      evidence: %{
        issuer_codes: codes,
        titles: titles,
        fiscal_year_ends: years,
        periods: periods,
        publication_dates: published,
        referenced_publication_dates: references,
        correction_headings: Enum.filter(lines, &correction_heading?/1)
      },
      complete?:
        length(codes) == 1 and length(years) == 1 and one(years) != nil and
          length(periods) == 1 and one(periods) != nil
    }
  end

  defp title_identity(title) do
    captures = Regex.run(@title, title, capture: :all_but_first)
    [year, month, quarter, interim] = Enum.take(captures ++ ["", ""], 4)

    year_end =
      case Date.new(String.to_integer(year), String.to_integer(month), 1) do
        {:ok, date} -> date |> Date.end_of_month() |> Date.to_iso8601()
        _ -> nil
      end

    period =
      cond do
        interim != "" and quarter != "2" -> nil
        quarter == "" -> "full_year"
        true -> "q" <> quarter
      end

    %{fiscal_year_end: year_end, period: period}
  end

  defp correction_heading?(line) do
    Regex.match?(@correction, line) or
      Regex.match?(
        ~r/^(?:[\p{Ps}\p{Pi}<][^\p{Pe}\p{Pf}>]*訂正[^\p{Pe}\p{Pf}>]*[\p{Pe}\p{Pf}>](?:\s*「?[0-9]{4}.*決算短信.*)?|「?[0-9]{4}.*決算短信.*訂正.*|訂正(?:について|版|に関するお知らせ))$/u,
        line
      )
  end

  defp dates(lines, pattern) do
    lines
    |> Enum.flat_map(fn line ->
      case Regex.run(pattern, line, capture: :all_but_first) do
        [year, month, day] ->
          case Date.new(String.to_integer(year), String.to_integer(month), String.to_integer(day)) do
            {:ok, date} -> [Date.to_iso8601(date)]
            _ -> [nil]
          end

        _ ->
          []
      end
    end)
    |> Enum.uniq()
  end

  defp one([value]), do: value
  defp one(_), do: nil

  defp decide(_, %{correction?: false}), do: {"excluded", "No supported correction heading", nil}

  defp decide(candidate, observations) do
    identity = observations.identity

    cond do
      not observations.supported? ->
        {"pending", "Unsupported correction heading", nil}

      not observations.complete? or identity.issuer_code != candidate.issuer ->
        {"pending", "Missing or conflicting issuer or reporting identity", nil}

      is_nil(identity.published_on) or is_nil(identity.referenced_publication_date) or
          identity.referenced_publication_date >= identity.published_on ->
        {"pending", "Missing or conflicting original-publication reference", nil}

      true ->
        case earlier_releases(candidate, identity) do
          [link] ->
            {"accepted", "Explicit correction identity and earlier publication match", link}

          _ ->
            {"pending", "Earlier release relationship is unresolved or conflicting", nil}
        end
    end
  end

  defp earlier_releases(candidate, identity) do
    year_end = Date.from_iso8601!(identity.fiscal_year_end)

    rows =
      Repo.all(
        from(r in Release,
          join: a in Acquisition,
          on: a.release_id == r.id,
          join: e in Extraction,
          on: e.original_id == a.original_id,
          where:
            r.issuer_code == ^candidate.issuer and r.fiscal_year_end == ^year_end and
              r.period == ^identity.period and r.category == "earnings_release" and
              a.issuer_code == ^candidate.issuer and a.status == "success" and
              a.acquired_at < ^candidate.acquired_at and e.status == "succeeded",
          order_by: [desc: e.id],
          limit: 101,
          select: %{release_id: r.id, extraction_id: e.id, text: e.text}
        )
      )

    if length(rows) > 100 do
      []
    else
      rows
      |> Enum.filter(fn row ->
        original = observe(row.text)

        original.complete? and not original.correction? and
          original.identity.issuer_code == candidate.issuer and
          original.identity.fiscal_year_end == identity.fiscal_year_end and
          original.identity.period == identity.period and
          original.identity.published_on == identity.referenced_publication_date
      end)
      |> Enum.uniq_by(& &1.release_id)
      |> Enum.map(fn row ->
        %{
          release_id: row.release_id,
          extraction_id: row.extraction_id,
          referenced_publication_date: identity.referenced_publication_date
        }
      end)
    end
  end
end
