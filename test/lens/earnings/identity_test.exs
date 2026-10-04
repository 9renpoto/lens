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

  test "ignores prior release titles mentioned in the regular release narrative" do
    result =
      Identity.from_text(
        "6857",
        "2027年3月期 第1四半期決算短信\n2026年7月29日\n比較対象は2026年3月期 決算短信をご参照ください\nコード番号 6857"
      )

    assert result.status == :identified
    assert result.release.fiscal_year_end == ~D[2027-03-31]
    assert result.release.period == "q1"
    assert result.published_on == ~D[2026-07-29]
  end

  test "ignores same-line and wrapped prior-release references when selecting the latest release" do
    prior = candidate("https://example.test/prior", "2026年3月期 決算短信")

    for separator <- ["", " ", "\n", "\n\n", "\r\n"],
        title <- ["2026年3月期 決算短信", "「2026年3月期 決算短信」", "2026年3月期 決算短信〔IFRS〕"],
        suffix <- [
          "をご参照ください",
          "に記載しています",
          "をご確認ください",
          "記載の数値を比較しています",
          "掲載の数値を比較しています",
          "を参照",
          "は比較対象です"
        ] do
      latest =
        candidate(
          "https://example.test/latest",
          "2027年3月期 第1四半期決算短信\n比較対象は次の短信です。\n" <>
            title <> separator <> suffix
        )

      assert latest.status == :identified
      assert latest.release.fiscal_year_end == ~D[2027-03-31]
      assert latest.release.period == "q1"
      assert Identity.select_initial([prior, latest]) == {:ok, latest}
    end
  end

  test "ignores prior correction-title references without losing the current identity" do
    for separator <- ["", "\n", "\n\n", "\r\n"] do
      result =
        Identity.from_text(
          "6857",
          "2027年3月期 第1四半期決算短信\nコード番号 6857\n「2026年3月期 決算短信」" <>
            separator <> "の一部訂正に関するお知らせ" <> separator <> "をご参照ください"
        )

      assert result.status == :identified
      assert result.release.fiscal_year_end == ~D[2027-03-31]
      assert result.release.period == "q1"
    end
  end

  test "accepts CRLF-delimited regular release headings and dates" do
    result =
      Identity.from_text("6857", "2027年3月期 第1四半期決算短信\r\n2026年7月29日\r\nコード番号 6857")

    assert result.status == :identified
    assert result.release.category == "earnings_release"
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

  test "accepts CRLF-delimited title-prefixed correction headings" do
    result =
      Identity.from_text(
        "8035",
        "2020年2月4日\r\nコード番号 8035\r\n「2020年3月期 第3四半期決算短信」の一部訂正に関するお知らせ\r\n"
      )

    assert result.status == :identified
    assert result.release.category == "correction"
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

  test "a correction prefix on a narrative line does not reclassify a regular release" do
    result =
      Identity.from_text(
        "6857",
        "2027年3月期 第1四半期決算短信\nコード番号 6857\n(訂正) 前期比較の表示を修正しています"
      )

    assert result.status == :identified
    assert result.release.category == "earnings_release"
  end

  test "wrapped narrative correction markers do not exclude the latest regular release" do
    prior = candidate("https://example.test/prior", "2026年3月期 決算短信")

    for separator <- ["\n", "\n\n", "\r\n"],
        marker <- ["(訂正)", "(訂正版)", "【訂正】", "[訂正]", "〈訂正〉", "“訂正”", "訂正について"] do
      latest =
        candidate(
          "https://example.test/latest",
          "2027年3月期 第1四半期決算短信\nコード番号 6857\n" <>
            marker <> separator <> "前期比較の表示を修正しています"
        )

      assert latest.status == :identified
      assert latest.release.category == "earnings_release"
      assert Identity.select_initial([prior, latest]) == {:ok, latest}
    end
  end

  test "correction labels after a regular title remain pending" do
    for separator <- ["\n", "\n\n", "\r\n"],
        label <- ["(訂正版)", "〔訂正〕", "訂正について", "一部訂正", "訂正に関するお知らせ"] do
      result =
        Identity.from_text(
          "6857",
          "2027年3月期 第1四半期決算短信" <> separator <> label <> "\nコード番号 6857"
        )

      assert result.status == :pending_confirmation
      assert result.release == nil
      assert Identity.select_initial([result]) == :empty
    end
  end

  test "recognized correction notices after the title remain excluded from initial selection" do
    for separator <- ["\n", "\n\n", "\r\n"],
        label <- ["一部訂正に関するお知らせ", "決算数値の訂正に関するお知らせ"] do
      result =
        Identity.from_text(
          "6857",
          "2027年3月期 第1四半期決算短信" <> separator <> label <> "\nコード番号 6857"
        )

      assert result.status == :identified
      assert result.release.category == "correction"
      assert Identity.select_initial([result]) == :empty
    end
  end

  test "repeated regular titles cannot override an unsupported correction heading" do
    for heading <- [
          "「2027年3月期 第1四半期決算短信」の訂正について",
          "2027年3月期 第1四半期決算短信(訂正版)",
          "2027年3月期 第1四半期決算短信\n(訂正版)",
          "2027年3月期 第1四半期決算短信\n訂正に関するお知らせ",
          "訂正に関するお知らせ",
          "訂正について",
          "(訂正版)",
          "〔訂正〕",
          "(訂正・数値データ訂正)「2027年3月期 第1四半期決算短信」の一部訂正について",
          "(一部訂正)2027年3月期 第1四半期決算短信",
          "〔訂正・数値データ訂正〕2027年3月期 第1四半期決算短信"
        ],
        separator <- ["\n", "\n\n", "\r\n"] do
      result =
        Identity.from_text(
          "6857",
          heading <> separator <> "2027年3月期 第1四半期決算短信\nコード番号 6857"
        )

      assert result.status == :pending_confirmation
      assert result.release == nil
      assert result.fields.category == nil
      assert Identity.select_initial([result]) == :empty
    end
  end

  test "correction-bearing Unicode delimiters stay pending when the original title is repeated" do
    for {opening, closing} <- [
          {"【", "】"},
          {"[", "]"},
          {"〈", "〉"},
          {"《", "》"},
          {"『", "』"},
          {"「", "」"},
          {"＜", "＞"},
          {"“", "”"}
        ],
        label <- ["訂正", "訂正・数値データ訂正"],
        placement <- [:prefix, :suffix, :standalone] do
      title = "2027年3月期 第1四半期決算短信"
      marker = opening <> label <> closing

      heading =
        case placement do
          :prefix -> marker <> title
          :suffix -> title <> marker
          :standalone -> marker <> "\n" <> title
        end

      result = Identity.from_text("6857", heading <> "\n" <> title <> "\nコード番号 6857")
      assert result.status == :pending_confirmation
      assert result.release == nil
      assert Identity.select_initial([result]) == :empty
    end
  end

  test "compound correction prefixes in narrative references do not block the regular release" do
    for separator <- ["", "\n", "\n\n", "\r\n"],
        marker <- ["(訂正・数値データ訂正)", "【訂正】", "[訂正]", "〈訂正〉", "＜訂正＞", "“訂正”"] do
      result =
        Identity.from_text(
          "6857",
          "2027年3月期 第1四半期決算短信\nコード番号 6857\n" <>
            marker <>
            "「2026年3月期 決算短信」の一部訂正について" <>
            separator <> "をご確認ください"
        )

      assert result.status == :identified
      assert result.release.fiscal_year_end == ~D[2027-03-31]
      assert result.release.category == "earnings_release"
    end
  end

  test "a narrative notice reference does not discard the latest regular release" do
    prior = candidate("https://example.test/prior", "2026年3月期 決算短信")

    latest =
      candidate("https://example.test/latest", "2027年3月期 第1四半期決算短信\n詳細は一部訂正に関するお知らせを参照してください。")

    assert latest.release.category == "earnings_release"
    assert Identity.select_initial([prior, latest]) == {:ok, latest}

    for suffix <- ["をご参照ください", "に記載しています", "をご確認ください"] do
      wrapped =
        candidate(
          "https://example.test/wrapped",
          "2027年3月期 第1四半期決算短信\n参考資料として\n「2027年3月期 第1四半期決算短信」\nの一部訂正に関するお知らせ\n" <> suffix
        )

      assert wrapped.release.category == "earnings_release"
      assert Identity.select_initial([prior, wrapped]) == {:ok, wrapped}
    end
  end

  test "title-prefixed correction headings cannot become initial regular releases" do
    for heading <- [
          "「2027年3月期 第1四半期決算短信」の一部訂正に関するお知らせ",
          "「2027年3月期 第1四半期決算短信」\nの一部訂正に関するお知らせ",
          "「2027年3月期\n第1四半期決算短信」\nの一部\n訂正に関するお知らせ",
          "「2027年3月期 第1四半期決算短信」の決算数値の訂正に関するお知らせ"
        ] do
      result = Identity.from_text("8035", heading <> "\nコード番号 8035")
      assert result.fields.category == "correction"

      assert Identity.select_initial([
               Map.put(result, :url, "https://example.test/correction.pdf")
             ]) == :empty
    end

    narrative =
      Identity.from_text(
        "8035",
        "2027年3月期 第1四半期決算短信\nコード番号 8035\n詳細は「2027年3月期 第1四半期決算短信」の一部訂正に関するお知らせを参照してください。"
      )

    assert narrative.fields.category == "earnings_release"
  end

  test "initial combined fixture retains pending correction without displacing regular release" do
    fixture =
      File.read!(Path.expand("../../fixtures/source_catalog/cases.json", __DIR__))
      |> Jason.decode!()
      |> Enum.find(&(&1["id"] == "synthetic-tokyo-electron-initial-with-ambiguous-correction"))

    candidates =
      Enum.map(fixture["documents"], fn document ->
        Identity.from_text("8035", document["pdf_identity_text"])
        |> Map.put(:url, document["expected"]["url"])
      end)

    assert Enum.any?(candidates, &(&1.status == :pending_confirmation))
    assert {:ok, selected} = Identity.select_initial(candidates)
    assert selected.url == fixture["expected_initial_regular_release"]
  end

  test "quarter and full-year titles claiming different identities remain pending" do
    text = "2027年3月期 第1四半期決算短信\n2027年3月期 決算短信\nコード番号 6857"
    assert Identity.from_text("6857", text).status == :pending_confirmation
  end

  test "conflicting title fields retain each independently unambiguous component" do
    period_conflict =
      Identity.from_text(
        "6857",
        "2027年3月期 第1四半期決算短信\n2027年3月期 第2四半期決算短信\nコード番号 6857"
      )

    assert period_conflict.status == :pending_confirmation
    assert period_conflict.release == nil
    assert period_conflict.fields.fiscal_year_end == ~D[2027-03-31]
    assert period_conflict.fields.period == nil

    year_conflict =
      Identity.from_text(
        "6857",
        "2027年3月期 第1四半期決算短信\n2026年3月期 第1四半期決算短信\nコード番号 6857"
      )

    assert year_conflict.status == :pending_confirmation
    assert year_conflict.release == nil
    assert year_conflict.fields.fiscal_year_end == nil
    assert year_conflict.fields.period == "q1"
    assert Identity.select_initial([period_conflict, year_conflict]) == :empty
  end

  test "invalid fiscal month or interim qualifier does not clear another valid title field" do
    invalid_month = Identity.from_text("6857", "2027年8月期 第1四半期決算短信\nコード番号 6857")
    assert invalid_month.status == :pending_confirmation
    assert invalid_month.fields.fiscal_year_end == nil
    assert invalid_month.fields.period == "q1"

    invalid_interim =
      Identity.from_text("6857", "2027年3月期 第1四半期(中間期)決算短信\nコード番号 6857")

    assert invalid_interim.status == :pending_confirmation
    assert invalid_interim.fields.fiscal_year_end == ~D[2027-03-31]
    assert invalid_interim.fields.period == nil
    assert Identity.select_initial([invalid_month, invalid_interim]) == :empty
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

  test "unsupported correction layouts remain pending rather than regular releases" do
    assert Identity.from_text("8035", "2027年3月期\n第1四半期決算短信\nコード番号 8035").status == :identified

    for suffix <- ["の訂正について", "の訂正に関する補足資料"] do
      result = Identity.from_text("8035", "「2027年3月期 第1四半期決算短信」" <> suffix <> "\nコード番号 8035")
      assert result.status == :pending_confirmation
      assert result.release == nil
      assert result.fields.fiscal_year_end == ~D[2027-03-31]

      assert Identity.select_initial([
               Map.put(result, :url, "https://example.test/correction.pdf")
             ]) == :empty
    end

    for suffix <- [
          "の訂正について",
          "の訂正に関する補足資料",
          "の決算数値の訂正に関するお知らせ"
        ] do
      result =
        Identity.from_text("8035", "2027年3月期 第1四半期決算短信" <> suffix <> "\nコード番号 8035")

      assert result.status == :pending_confirmation
      assert result.release == nil
      assert result.fields.period == "q1"
      assert result.fields.category == nil

      wrapped =
        Identity.from_text(
          "8035",
          "2027年3月期 第1四半期決算短信\n" <> suffix <> "\nコード番号 8035"
        )

      assert wrapped.status == :pending_confirmation
      assert wrapped.release == nil
      assert wrapped.fields.category == nil

      separated =
        Identity.from_text(
          "8035",
          "2027年3月期 第1四半期決算短信\n\n" <> suffix <> "\nコード番号 8035"
        )

      assert separated.status == :pending_confirmation
      assert separated.release == nil
      assert separated.fields.category == nil
    end

    for qualifier <- ["（訂正）", "〔訂正〕"] do
      result =
        Identity.from_text(
          "8035",
          "2027年3月期 第1四半期決算短信" <> qualifier <> "\nコード番号 8035"
        )

      assert result.status == :pending_confirmation
      assert result.release == nil
      assert result.fields.category == nil
    end
  end

  test "wrapped historical date references cannot become publication dates" do
    base = "コード番号 8035\n（訂正）「2020年3月期 第3四半期決算短信」の一部訂正に関するお知らせ\n2020年1月30日\nに公表した短信を訂正します"
    assert Identity.from_text("8035", base).published_on == nil
    assert Identity.from_text("8035", "2020年2月4日\n" <> base).published_on == ~D[2020-02-04]

    for separator <- ["\n", "\n\n", "\r\n"],
        continuation <- [
          "公表の短信を訂正します",
          "付で公表した短信を訂正します",
          "発表の短信を訂正します",
          "開示の短信を訂正します",
          "公開の短信を訂正します",
          "発行の短信を訂正します",
          "掲載の短信を訂正します",
          "記載の短信を訂正します"
        ] do
      wrapped = String.replace(base, "\nに公表した短信を訂正します", separator <> continuation)
      assert Identity.from_text("8035", wrapped).published_on == nil
      assert Identity.from_text("8035", "2020年2月4日\n" <> wrapped).published_on == ~D[2020-02-04]
    end

    separated = String.replace(base, "\nに公表", "\n\nに公表")
    assert Identity.from_text("8035", separated).published_on == nil
    assert Identity.from_text("8035", "2020年2月4日\n" <> separated).published_on == ~D[2020-02-04]
  end

  test "financial-statement dates after issuer metadata cannot replace the header publication date" do
    for separator <- ["\n", "\n\n", "\r\n"],
        suffix <- ["現在", "時点", "残高", "発表の短信を参照", ""] do
      text = "2027年3月期 第1四半期決算短信\nコード番号 6857\n2026年6月30日" <> separator <> suffix
      assert Identity.from_text("6857", text).published_on == nil
      assert Identity.from_text("6857", "2026年7月29日\n" <> text).published_on == ~D[2026-07-29]
    end
  end

  test "header as-of dates remain excluded without clearing the own publication date" do
    for suffix <- ["現在", "時点", "残高"] do
      text = "2027年3月期 第1四半期決算短信\n2026年6月30日\n" <> suffix <> "\nコード番号 6857"
      assert Identity.from_text("6857", text).published_on == nil
      assert Identity.from_text("6857", "2026年7月29日\n" <> text).published_on == ~D[2026-07-29]
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

  test "initial selection excludes candidates without a confirmed supported issuer" do
    regular = candidate("https://example.test/release", "2027年3月期 第1四半期決算短信")

    for issuer <- [nil, "1234"] do
      unconfirmed = put_in(regular.release.issuer_code, issuer)
      assert Identity.select_initial([unconfirmed]) == :empty
    end
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
