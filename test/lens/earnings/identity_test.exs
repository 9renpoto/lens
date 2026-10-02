defmodule Lens.Earnings.IdentityTest do
  use ExUnit.Case, async: true

  alias Lens.Earnings.Identity

  test "uses PDF fiscal year rather than Advantest's listing year" do
    result = Identity.from_text("6857", "2027年3月期 第1四半期決算短信〔IFRS〕\n2026年7月29日\nコード番号 6857")
    assert result.status == :identified

    assert result.release == %{
             issuer_code: "6857",
             fiscal_year_end: ~D[2027-03-31],
             period: "q1",
             category: "earnings_release"
           }

    assert result.published_on == ~D[2026-07-29]
  end

  test "normalizes full-width digits and identifies Fast Retailing" do
    result = Identity.from_text("9983", "2026年８月期 第３四半期決算短信〔ＩＦＲＳ〕\n2026年７月９日\nコード番号 9983")
    assert result.release.fiscal_year_end == ~D[2026-08-31]
    assert result.release.period == "q3"
    assert result.published_on == ~D[2026-07-09]
  end

  test "recognizes an explicit second-quarter interim title with extraction whitespace" do
    result =
      Identity.from_text("8035", "2027 年 3 月期 第 2 四半期（中間期）決算短信\n2026 年 10 月 30 日\nコード番号 8035")

    assert result.status == :identified
    assert result.release.period == "q2"
    assert result.release.fiscal_year_end == ~D[2027-03-31]
    assert result.published_on == ~D[2026-10-30]
  end

  test "classifies a separately listed correction and uses its own date" do
    result =
      Identity.from_text(
        "8035",
        "2020年2月4日\nコード番号 8035\n（訂正）「2020年3月期 第3四半期決算短信」の一部訂正に関するお知らせ\n2020年1月30日に公表した短信の一部訂正"
      )

    assert result.release.category == "correction"
    assert result.release.period == "q3"
    assert result.published_on == ~D[2020-02-04]
  end

  test "recognizes a full-year release without inventing a publication date" do
    result = Identity.from_text("8035", "2027年3月期 決算短信\nコード番号 8035")
    assert result.release.period == "full_year"
    assert result.published_on == nil
  end

  test "missing period and fiscal year stay pending" do
    result = Identity.from_text("8035", "決算数値の訂正に関するお知らせ\nコード番号 8035")
    assert result.status == :pending_confirmation
    assert result.release == nil
    assert result.fields.category == "correction"
    assert result.fields.fiscal_year_end == nil
    assert result.fields.period == nil
  end

  test "issuer mismatch, conflicting periods, and unsupported fiscal month stay pending" do
    for text <- [
          "2027年3月期 第1四半期決算短信\nコード番号 9983",
          "2027年3月期 第1四半期決算短信\n2027年3月期 第2四半期決算短信\nコード番号 6857",
          "2027年8月期 第1四半期決算短信\nコード番号 6857",
          "2027年3月期 第1四半期決算短信"
        ] do
      assert Identity.from_text("6857", text).status == :pending_confirmation
    end
  end

  test "a footnote mentioning corrections does not reclassify a regular release" do
    result = Identity.from_text("6857", "2027年3月期 第1四半期決算短信\nコード番号 6857\n前期の数値には訂正が含まれます")
    assert result.release.category == "earnings_release"
  end

  test "a narrative notice reference does not discard the latest regular release" do
    prior = candidate("https://example.test/prior", "2026年3月期 決算短信")

    latest =
      candidate("https://example.test/latest", "2027年3月期 第1四半期決算短信\n詳細は一部訂正に関するお知らせを参照してください。")

    assert latest.release.category == "earnings_release"
    assert Identity.select_initial([prior, latest]) == {:ok, latest}
  end

  test "quarter and full-year titles claiming different identities remain pending" do
    text = "2027年3月期 第1四半期決算短信\n2027年3月期 決算短信\nコード番号 6857"
    assert Identity.from_text("6857", text).status == :pending_confirmation
  end

  test "dated source fixtures map to the documented identities" do
    cases =
      File.read!(Path.expand("../../fixtures/source_catalog/cases.json", __DIR__))
      |> Jason.decode!()

    for fixture <- cases do
      documents = Map.get(fixture, "documents", [fixture])

      for document <- documents do
        expected = document["expected"]
        result = Identity.from_text(expected["issuer_code"], document["pdf_identity_text"])
        assert result.fields.issuer_code == expected["issuer_code"]
        assert date_string(result.fields.fiscal_year_end) == expected["fiscal_year_end"]

        assert result.fields.period ==
                 expected["period"]
                 |> then(fn
                   "Q1" -> "q1"
                   "Q2" -> "q2"
                   "Q3" -> "q3"
                   "FY" -> "full_year"
                   nil -> nil
                 end)

        assert result.fields.category == expected["category"]
        assert date_string(result.published_on) == expected["published_on"]

        assert result.status ==
                 if(expected["fiscal_year_end"] && expected["period"],
                   do: :identified,
                   else: :pending_confirmation
                 )
      end
    end
  end

  test "invalid or conflicting dates remain unknown" do
    for date <- ["2026年2月30日", "2026年7月29日\n2026年7月30日"] do
      result = Identity.from_text("6857", "2027年3月期 第1四半期決算短信\n#{date}\nコード番号 6857")
      assert result.status == :identified
      assert result.published_on == nil
    end
  end

  test "unsupported issuers return an explicit error" do
    assert Identity.from_text("1234", "2027年3月期 決算短信") == {:error, :unsupported_issuer}
  end

  test "initial selection orders fiscal years and periods, excludes corrections and pending" do
    q1 = candidate("https://example.test/q1", "2027年3月期 第1四半期決算短信")
    q2 = candidate("https://example.test/q2", "2027年3月期 第2四半期決算短信")
    prior = candidate("https://example.test/prior", "2026年3月期 決算短信")
    correction = candidate("https://example.test/correction", "（訂正）2027年3月期 第2四半期決算短信")
    pending = candidate("https://example.test/pending", "決算数値の訂正")
    assert Identity.select_initial([prior, correction, q1, pending, q2]) == {:ok, q2}
    assert Identity.select_initial([correction, pending]) == :empty
  end

  test "conflicting URLs for the newest identity require review instead of falling back" do
    q1 = candidate("https://example.test/q1", "2027年3月期 第1四半期決算短信")
    q2 = candidate("https://example.test/q2", "2027年3月期 第2四半期決算短信")
    conflict = %{q2 | url: "https://example.test/other"}
    assert Identity.select_initial([q1, q2, conflict]) == {:pending_confirmation, [q2, conflict]}
    assert Identity.select_initial([q2, q2]) == {:ok, q2}
  end

  test "selection never mixes issuers" do
    adv = candidate("https://example.test/adv", "2027年3月期 第1四半期決算短信")

    tel =
      Map.put(
        Identity.from_text("8035", "2027年3月期 決算短信\nコード番号 8035"),
        :url,
        "https://example.test/tel"
      )

    assert Identity.select_initial([adv, tel]) == {:error, :mixed_issuers}
  end

  defp date_string(nil), do: nil
  defp date_string(date), do: Date.to_iso8601(date)

  defp candidate(url, text) do
    "6857" |> Identity.from_text(text <> "\nコード番号 6857") |> Map.put(:url, url)
  end
end
