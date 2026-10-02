defmodule Lens.Earnings.Identity do
  @moduledoc "Conservative identity mapping from PDF text for the fixed earnings pilot."

  @fiscal_months %{"6857" => 3, "9983" => 8, "8035" => 3}
  @period_order %{"q1" => 1, "q2" => 2, "q3" => 3, "full_year" => 4}

  @doc "Read explicit PDF identity fields. Missing or contradictory identity stays pending."
  def from_text(issuer, text) when is_binary(text) and is_map_key(@fiscal_months, issuer) do
    text = String.normalize(text, :nfkc)
    codes = Regex.scan(~r/コード\s*番号\s*[:：]?\s*([0-9]{4})(?![0-9])/u, text, capture: :all_but_first)
    code = codes |> Enum.map(&hd/1) |> unique_value()

    titles =
      Regex.scan(
        ~r/^[ \t]*(?:\(訂正\)[ \t]*)?「?(?<year>[0-9]{4})\s*年\s*(?<month>[0-9]{1,2})\s*月期\s*(?:第\s*(?<quarter>[123])\s*四半期\s*(?<interim>\(中間期\))?\s*)?決算短信(?:[ \t]*(?:〔[^〕\r\n]*〕|\([^\)\r\n]*\)))*」?(?:\s*の\s*(?:一部|決算数値の)?\s*訂正(?:について|に関する(?:お知らせ|補足資料)))?[ \t]*\r?$(?!\n[ \t]*(?:\r?\n[ \t]*)*(?:の|[をにはがともでへ]|ご参照|参照|記載|掲載))/mu,
        text,
        capture: ["year", "month", "quarter", "interim"]
      )
      |> Enum.map(&title_fields(&1, Map.fetch!(@fiscal_months, issuer)))
      |> unique_value()

    {year_end, period} = titles || {nil, nil}
    category = category(text)

    fields = %{
      issuer_code: code,
      fiscal_year_end: year_end,
      period: period,
      category: category
    }

    identified? = code == issuer and year_end != nil and period != nil and category != nil

    %{
      status: if(identified?, do: :identified, else: :pending_confirmation),
      fields: fields,
      release: if(identified?, do: fields),
      published_on: publication_date(text)
    }
  end

  def from_text(_, _), do: {:error, :unsupported_issuer}

  @doc "Select one issuer's newest identified regular release, leaving competing candidates pending."
  def select_initial(candidates) when is_list(candidates) do
    regular =
      candidates
      |> Enum.filter(fn
        %{
          status: :identified,
          release: %{issuer_code: issuer, category: "earnings_release"}
        }
        when issuer in ["6857", "9983", "8035"] ->
          true

        _ ->
          false
      end)
      |> Enum.uniq()

    issuers = Enum.map(regular, & &1.release.issuer_code) |> Enum.uniq()

    case issuers do
      [] -> :empty
      [_] -> select_newest(regular)
      _ -> {:error, :mixed_issuers}
    end
  end

  defp select_newest(candidates) do
    newest = Enum.max_by(candidates, &sort_key/1) |> sort_key()
    competing = Enum.filter(candidates, &(sort_key(&1) == newest))

    case competing do
      [candidate] -> {:ok, candidate}
      multiple -> {:pending_confirmation, multiple}
    end
  end

  defp sort_key(candidate) do
    {Date.to_gregorian_days(candidate.release.fiscal_year_end),
     Map.fetch!(@period_order, candidate.release.period)}
  end

  defp title_fields([year, month, quarter, interim], fiscal_month) do
    year = String.to_integer(year)
    month = String.to_integer(month)

    if year > 0 and month == fiscal_month and (interim == "" or quarter == "2") do
      {:ok, first} = Date.new(year, month, 1)
      {Date.end_of_month(first), if(quarter == "", do: "full_year", else: "q" <> quarter)}
    else
      {nil, nil}
    end
  end

  defp category(text) do
    cond do
      Regex.match?(
        ~r/^[ \t]*(?:\(訂正\)[ \t]*)?(?:「[^」]*決算短信[^」]*」\s*の\s*)?(?:一部|決算数値の)\s*訂正に関するお知らせ[ \t]*\r?$(?!\s*(?:[をにはがともでへ]|ご参照|参照))/mu,
        text
      ) or
          Regex.match?(
            ~r/^[ \t]*\(訂正\)\s*[0-9]{4}\s*年\s*[0-9]{1,2}\s*月期\s*(?:第\s*[123]\s*四半期\s*(?:\(中間期\))?\s*)?決算短信(?:[ \t]*(?:〔[^〕\n]*〕|\([^\)\n]*\)))*[ \t]*\r?$/mu,
            text
          ) ->
        "correction"

      unsupported_correction_heading?(text) ->
        nil

      Regex.match?(
        ~r/^[ \t]*[0-9]{4}\s*年\s*[0-9]{1,2}\s*月期\s*(?:第\s*[123]\s*四半期\s*(?:\(中間期\))?\s*)?決算短信(?!(?:[ \t]*(?:〔[^〕\n]*訂正[^〕\n]*〕|\([^\)\n]*訂正[^\)\n]*\))))(?:[ \t]*(?:〔[^〕\n]*〕|\([^\)\n]*\)))*[ \t]*\r?$(?!\r?\n[ \t]*(?:\r?\n[ \t]*)*(?:の|(?:\([^\)\n]*訂正[^\)\n]*\)|〔[^〕\n]*訂正[^〕\n]*〕|(?:一部|決算数値の)?訂正(?:について|版|に関するお知らせ)?)[ \t]*\r?$))/mu,
        text
      ) ->
        "earnings_release"

      true ->
        nil
    end
  end

  defp unsupported_correction_heading?(text) do
    Regex.match?(
      ~r/^[ \t]*(?:\([^\)\r\n]*訂正[^\)\r\n]*\)|〔[^〕\r\n]*訂正[^〕\r\n]*〕)\s*「?[0-9]{4}\s*年\s*[0-9]{1,2}\s*月期\s*(?:第\s*[123]\s*四半期\s*(?:\(中間期\))?\s*)?決算短信(?:[ \t]*(?:〔[^〕\r\n]*〕|\([^\)\r\n]*\)))*」?(?:\s*の\s*(?:一部|決算数値の)?\s*訂正(?:について|に関する(?:お知らせ|補足資料)))?[ \t]*\r?$(?!\n[ \t]*(?:\r?\n[ \t]*)*(?:の|[をにはがともでへ]|ご参照|参照|記載|掲載))/mu,
      text
    ) or
      Regex.match?(
        ~r/^[ \t]*(?:\([^\)\r\n]*訂正[^\)\r\n]*\)|〔[^〕\r\n]*訂正[^〕\r\n]*〕|(?:一部|決算数値の)?訂正(?:について|版|に関する(?:お知らせ|補足資料))?)[ \t]*\r?$(?!\n[ \t]*(?:\r?\n[ \t]*)*(?:[をにはがともでへ]|ご参照|参照|記載|掲載))/mu,
        text
      ) or
      Regex.match?(
        ~r/^[ \t]*「?[0-9]{4}\s*年\s*[0-9]{1,2}\s*月期\s*(?:第\s*[123]\s*四半期\s*(?:\(中間期\))?\s*)?決算短信(?:[ \t]*(?:〔[^〕\r\n]*〕|\([^\)\r\n]*\)))*」?(?:\s*の\s*(?:一部|決算数値の)?\s*訂正(?:について|に関する(?:補足資料|お知らせ))|\s*(?:\([^\)\r\n]*訂正[^\)\r\n]*\)|〔[^〕\r\n]*訂正[^〕\r\n]*〕|(?:一部)?訂正(?:について|版|に関するお知らせ)?))[ \t]*\r?$(?!\n[ \t]*(?:\r?\n[ \t]*)*(?:[をにはがともでへ]|ご参照|参照|記載|掲載))/mu,
        text
      )
  end

  defp publication_date(text) do
    header =
      case Regex.split(~r/コード\s*番号\s*[:：]?\s*[0-9]{4}(?![0-9])/u, text, parts: 2) do
        [header, _body] -> header
        [_text] -> ""
      end

    Regex.scan(
      ~r/^\s*([0-9]{4})\s*年\s*([0-9]{1,2})\s*月\s*([0-9]{1,2})\s*日[ \t]*\r?$(?!\n[ \t]*(?:\r?\n[ \t]*)*(?:[をにはがともでへ付]|公表|発表|開示|公開|発行|掲載|記載|現在|時点|基準|残高|ご?参照))/mu,
      header,
      capture: :all_but_first
    )
    |> Enum.map(fn [year, month, day] ->
      case Date.new(String.to_integer(year), String.to_integer(month), String.to_integer(day)) do
        {:ok, date} -> date
        _ -> nil
      end
    end)
    |> unique_value()
  end

  defp unique_value(values) do
    case Enum.uniq(values) do
      [value] -> value
      _ -> nil
    end
  end
end
