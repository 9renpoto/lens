defmodule Lens.Earnings.SearchTest do
  use Lens.DataCase
  alias Lens.Earnings
  alias Lens.Earnings.{Extraction, Extractions}
  alias Lens.Search

  @tag :readable_title
  test "titles use the registered issuer and confirmed identity without changing provenance" do
    {:ok, _target} =
      Lens.Analysis.create_target(%{
        security_code: "6857",
        display_name: "架空株式会社",
        market: "TSE",
        sector: "電気機器",
        active: false
      })

    retained = retain("readable-title", 0)
    extraction = extract(retained.original.id, "未確認の別表題\n表題検証用語")
    acquisition_before = Repo.get!(Lens.Earnings.Acquisition, retained.acquisition.id)
    release_before = Repo.get!(Lens.Earnings.Release, retained.release.id)

    assert {:ok, [result]} = Search.search("表題検証用語")
    assert result.title == "架空株式会社 2027年3月期 第1四半期 決算短信"
    assert result.id == retained.release.id
    assert result.resource_type == "earnings_release"
    assert result.original_id == retained.original.id
    assert result.extraction_id == extraction.id
    assert result.canonical_url == "https://example.test/readable-title.pdf"
    assert result.provenance_url == "/api/earnings/releases/#{retained.release.id}"
    assert Repo.get!(Lens.Earnings.Acquisition, retained.acquisition.id) == acquisition_before
    assert Repo.get!(Lens.Earnings.Release, retained.release.id) == release_before
  end

  @tag :readable_title
  test "unregistered issuers keep searchable results with readable periods and kind fallbacks" do
    for {period, category, label} <- [
          {"q1", "earnings_release", "第1四半期 決算短信"},
          {"q2", "earnings_release", "第2四半期 決算短信"},
          {"q3", "earnings_release", "第3四半期 決算短信"},
          {"full_year", "earnings_release", "通期 決算短信"},
          {"q1", "correction", "第1四半期 決算短信訂正"},
          {"q1", "other_document", "第1四半期 other_document"}
        ] do
      key = "#{period}-#{category}"

      retained =
        retain(key, 0, %{
          fiscal_year_end: ~D[2027-12-31],
          period: period,
          category: category
        })

      extract(retained.original.id, "fallbackmarker #{key}")
      assert {:ok, results} = Search.search("fallbackmarker")
      result = Enum.find(results, &(&1.id == retained.release.id))
      assert result
      assert result.title == "6857 2027年12月期 #{label}"
    end
  end

  test "valid large text remains successful and searchable at its tail" do
    retained = retain("large", 0)

    dense = Enum.map_join(1..100_000, " ", &"word#{&1}")
    marker = "\n\n完全保存末尾マーカー"

    body =
      binary_part(String.duplicate(dense <> " ", 9), 0, 8_388_608 - byte_size(marker)) <> marker

    assert {:ok, pending} = Extractions.begin(retained.original.id, "fixture", "1")
    assert {:ok, success} = Extractions.succeed(pending.id, body)
    assert success.status == "succeeded"
    assert Repo.get!(Extraction, success.id).text == body
    assert {:ok, [result]} = Search.search("完全保存末尾マーカー")
    assert result.extraction_id == success.id
    assert :ok = Search.rebuild(batch_size: 1)
    assert {:ok, [_]} = Search.search("完全保存末尾マーカー")
    assert Repo.get!(Extraction, success.id).text == body
  end

  test "shared originals yield one result per release with global feed pagination" do
    first = retain("shared", 0)

    second =
      retain("shared", 60, %{
        fiscal_year_end: ~D[2027-03-31],
        period: "q2",
        category: "earnings_release"
      })

    assert first.original.id == second.original.id
    extract(first.original.id, "Common paginationtoken")

    {:ok, source} =
      Lens.Content.create_source(%{
        source_type: "rss",
        endpoint_url: "https://example.test/mixed.xml",
        poll_interval_seconds: 300
      })

    {:ok, %{document: document}} =
      Lens.Content.observe_document(source, %{
        canonical_url: "https://example.test/feed-note",
        title: "Notes",
        content: "Common paginationtoken"
      })

    assert {:ok, results} = Search.search("paginationtoken")
    assert length(results) == 3
    assert Enum.find(results, &(&1.id == document.id)).title == "Notes"

    assert Enum.sort(Enum.map(results, & &1.id)) ==
             Enum.sort([first.release.id, second.release.id, document.id])

    for {expected, offset} <- Enum.with_index(results) do
      assert {:ok, [^expected]} = Search.search("paginationtoken", limit: 1, offset: offset)
    end
  end

  test "one release searches only the selected text and exposes stale fallback" do
    old = retain("old", 0)
    newer = retain("new", 60)
    first = extract(old.original.id, "旧版売上高 ＰｏｓｔｇｒｅＳＱＬ")
    assert {:ok, [result]} = Search.search("旧版売上高")
    assert result.id == old.release.id
    assert result.resource_type == "earnings_release"
    assert result.original_id == old.original.id
    assert result.extraction_id == first.id
    assert result.stale
    assert {:ok, [_]} = Search.search("postgresql")
    assert {:ok, failed} = Extractions.begin(newer.original.id, "fixture", "1")
    assert {:ok, _} = Extractions.fail(failed.id, "timeout")
    assert {:ok, [%{stale: true}]} = Search.search("旧版売上高")
    current = extract(newer.original.id, "最新版営業利益")
    assert {:ok, []} = Search.search("旧版売上高")
    assert {:ok, [result]} = Search.search("営業利益")
    assert result.extraction_id == current.id
    refute result.stale
    extract(old.original.id, "遅延完了売上高")
    assert {:ok, []} = Search.search("遅延完了")
    assert {:ok, [_]} = Search.search("営業利益")
  end

  test "failed and unconfirmed originals do not invent searchable text" do
    retained = retain("failed", 0)
    assert {:ok, failed} = Extractions.begin(retained.original.id, "fixture", "1")
    assert {:ok, _} = Extractions.fail(failed.id, "empty_output")
    unknown = retain("unknown", 60, nil)
    extract(unknown.original.id, "未確定営業利益")
    assert {:ok, []} = Search.search("営業利益")
    assert {:ok, %{extraction: nil}} = Extractions.release_text(retained.release.id)
  end

  test "rebuild restores the same CJK-normalized derived data without new attempts" do
    retained = retain("rebuild", 0)
    attempt = extract(retained.original.id, "再構築対象語 ＡＢＣ１２３")

    Repo.update_all(from(e in Extraction, where: e.id == ^attempt.id),
      set: [search_text: "stale"]
    )

    assert {:ok, []} = Search.search("再構築")
    count = Repo.aggregate(Extraction, :count)
    assert :ok = Search.rebuild(batch_size: 1)
    assert {:ok, [_]} = Search.search("再構築")
    assert {:ok, [_]} = Search.search("abc123")
    assert Repo.aggregate(Extraction, :count) == count
    assert Repo.aggregate(Lens.Earnings.Acquisition, :count) == 1
  end

  defp extract(id, text) do
    assert {:ok, pending} = Extractions.begin(id, "fixture", "1")
    assert {:ok, success} = Extractions.succeed(pending.id, text)
    success
  end

  defp retain(
         bytes,
         seconds,
         identity \\ %{
           fiscal_year_end: ~D[2027-03-31],
           period: "q1",
           category: "earnings_release"
         }
       ) do
    assert {:ok, result} =
             Earnings.record_success(%{
               bytes: "%PDF-#{bytes}",
               acquisition_id: "#{bytes}-#{seconds}",
               issuer_code: "6857",
               acquired_at: DateTime.add(~U[2026-09-27 01:00:00.000000Z], seconds),
               url: "https://example.test/#{bytes}.pdf",
               release: identity
             })

    result
  end
end
