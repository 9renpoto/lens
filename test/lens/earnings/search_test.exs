defmodule Lens.Earnings.SearchTest do
  use Lens.DataCase
  alias Lens.Earnings
  alias Lens.Earnings.{Extraction, Extractions}
  alias Lens.Search

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
