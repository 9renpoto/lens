defmodule Lens.Earnings.Identity do
  @moduledoc "Conservative identity mapping from explicit PDF text."

  @issuer_evidence ~r/コード\s*番号\s*[:：]?\s*([^\s()〔〕]{1,50})(?=[\s()〔〕]|$)/u

  @doc "Read explicit PDF identity fields. Missing or contradictory identity stays pending."
  def from_text(issuer, text)
      when is_binary(text) and is_binary(issuer) and byte_size(issuer) > 0 do
    text = String.normalize(text, :nfkc)
    codes = Regex.scan(@issuer_evidence, text, capture: :all_but_first)
    code = codes |> Enum.map(&hd/1) |> unique_value()

    {year_ends, periods} =
      Regex.scan(
        ~r/^[ \t]*(?:\(訂正\)[ \t]*)?「?(?<year>[0-9]{4})\s*年\s*(?<month>[0-9]{1,2})\s*月期\s*(?:第\s*(?<quarter>[123])\s*四半期\s*(?<interim>\(中間期\))?\s*)?決算短信(?:[ \t]*(?:〔[^〕\r\n]*〕|\([^\)\r\n]*\)))*」?(?:\s*の\s*(?:一部|決算数値の)?\s*訂正(?:について|に関する(?:お知らせ|補足資料)))?[ \t]*\r?$(?!\n[ \t]*(?:\r?\n[ \t]*)*(?:の|[をにはがともでへ]|ご参照|参照|記載|掲載))/mu,
        text,
        capture: ["year", "month", "quarter", "interim"]
      )
      |> Enum.map(&title_fields/1)
      |> Enum.unzip()

    year_end = unique_value(year_ends)
    period = unique_value(periods)
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

  defp title_fields([year, month, quarter, interim]) do
    year = String.to_integer(year)
    month = String.to_integer(month)

    year_end =
      case Date.new(year, month, 1) do
        {:ok, first} when year > 0 -> Date.end_of_month(first)
        _ -> nil
      end

    period =
      if interim == "" or quarter == "2" do
        if quarter == "", do: "full_year", else: "q" <> quarter
      end

    {year_end, period}
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
      ~r/^[ \t]*(?:[\p{Ps}\p{Pi}<][^\p{Pe}\p{Pf}>\r\n]*訂正[^\p{Pe}\p{Pf}>\r\n]*[\p{Pe}\p{Pf}>])\s*「?[0-9]{4}\s*年\s*[0-9]{1,2}\s*月期\s*(?:第\s*[123]\s*四半期\s*(?:\(中間期\))?\s*)?決算短信(?:[ \t]*(?:〔[^〕\r\n]*〕|\([^\)\r\n]*\)))*」?(?:\s*の\s*(?:一部|決算数値の)?\s*訂正(?:について|に関する(?:お知らせ|補足資料)))?[ \t]*\r?$(?!\n[ \t]*(?:\r?\n[ \t]*)*(?:の|[をにはがともでへ]|ご参照|参照|記載|掲載))/mu,
      text
    ) or
      Regex.match?(
        ~r/^[ \t]*(?:[\p{Ps}\p{Pi}<][^\p{Pe}\p{Pf}>\r\n]*訂正[^\p{Pe}\p{Pf}>\r\n]*[\p{Pe}\p{Pf}>]|(?:一部|決算数値の)?訂正(?:について|版|に関する(?:お知らせ|補足資料))?)[ \t]*\r?$\s*(?=[ \t]*「?[0-9]{4}\s*年\s*[0-9]{1,2}\s*月期\s*(?:第\s*[123]\s*四半期\s*(?:\(中間期\))?\s*)?決算短信(?:[ \t]*(?:〔[^〕\r\n]*〕|\([^\)\r\n]*\)))*」?[ \t]*\r?$(?!\n[ \t]*(?:\r?\n[ \t]*)*(?:の|[をにはがともでへ]|ご参照|参照|記載|掲載)))/mu,
        text
      ) or
      Regex.match?(
        ~r/^[ \t]*「?[0-9]{4}\s*年\s*[0-9]{1,2}\s*月期\s*(?:第\s*[123]\s*四半期\s*(?:\(中間期\))?\s*)?決算短信(?:[ \t]*(?:〔[^〕\r\n]*〕|\([^\)\r\n]*\)))*」?(?:\s*の\s*(?:一部|決算数値の)?\s*訂正(?:について|に関する(?:補足資料|お知らせ))|\s*(?:[\p{Ps}\p{Pi}<][^\p{Pe}\p{Pf}>\r\n]*訂正[^\p{Pe}\p{Pf}>\r\n]*[\p{Pe}\p{Pf}>]|(?:一部)?訂正(?:について|版|に関するお知らせ)?))[ \t]*\r?$(?!\n[ \t]*(?:\r?\n[ \t]*)*(?:[をにはがともでへ]|ご参照|参照|記載|掲載))/mu,
        text
      )
  end

  defp publication_date(text) do
    header =
      case Regex.split(@issuer_evidence, text, parts: 2) do
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
