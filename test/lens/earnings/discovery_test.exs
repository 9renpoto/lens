defmodule Lens.Earnings.DiscoveryTest do
  use ExUnit.Case, async: true

  alias Lens.Earnings.{Discovery, Identity}

  test "discovers the exact URL sets from all source fixtures" do
    fixtures =
      File.read!(Path.expand("../../fixtures/source_catalog/cases.json", __DIR__))
      |> Jason.decode!()

    for fixture <- fixtures do
      assert {:ok, links} = Discovery.links(fixture["listing_url"], fixture["listing_html"])

      expected =
        Map.get(
          fixture,
          "expected_discovered_urls",
          get_in(fixture, ["expected", "discovered_urls"])
        )

      assert Enum.map(links, & &1.url) == expected

      expected_documents = fixture["documents"] || [fixture]
      assert length(links) == length(expected_documents)

      for {link, document} <- Enum.zip(links, expected_documents) do
        assert link.listing_url == document["expected"]["listing_url"]
        assert link.url == document["expected"]["url"]
      end

      if comparison = get_in(fixture, ["expected", "comparison_urls"]) do
        assert Enum.map(links, & &1.comparison_url) == comparison
        refute comparison == expected
      end

      if metadata = get_in(fixture, ["expected", "source_metadata"]) do
        assert Map.new(hd(links).headings, fn {level, text} -> {to_string(level), text} end) ==
                 metadata["headings"]

        assert metadata["source_fiscal_year_label"] in Map.values(metadata["headings"])
      end
    end
  end

  test "walks PDF anchors inside every heading level with heading provenance" do
    for level <- 1..6 do
      html = "<h#{level}><span><a href='release.pdf'>決算短信</a></span></h#{level}>"
      assert {:ok, [link]} = Discovery.links("https://example.test/", html)
      assert link.url == "https://example.test/release.pdf"
      assert link.headings == [{level, "決算短信"}]
    end
  end

  test "retains headings nested inside non-PDF anchors for following PDF candidates" do
    html = "<a href='archive.html'><h2>2027年3月期</h2></a><a href='release.pdf'>決算短信</a>"

    assert {:ok, [link]} = Discovery.links("https://example.test/", html)
    assert link.url == "https://example.test/release.pdf"
    assert link.headings == [{2, "2027年3月期"}]
  end

  test "retains headings nested inside accepted PDF anchors for following candidates" do
    html = "<a href='one.pdf'><h2>2027年3月期</h2></a><a href='two.pdf'>第1四半期決算短信</a>"

    assert {:ok, [first, second]} = Discovery.links("https://example.test/", html)
    assert first.headings == []
    assert second.headings == [{2, "2027年3月期"}]
  end

  test "resolves published hrefs, decodes entities and retains heading and anchor metadata" do
    html = """
    <h2>2026年8月期</h2><h3>第3四半期決算</h3>
    <a HREF='pdf/unpredictable.PDF?download=1&amp;lang=ja#page=1'><span>第3四半期決算</span> (PDF)</a>
    <a href='/ir/other.pdf'>訂正資料</a>
    """

    assert {:ok, [release, correction]} =
             Discovery.links("https://www.fastretailing.com/jp/ir/library/tanshin.html", html)

    assert release.href == "pdf/unpredictable.PDF?download=1&lang=ja#page=1"

    assert release.url ==
             "https://www.fastretailing.com/jp/ir/library/pdf/unpredictable.PDF?download=1&lang=ja#page=1"

    assert release.comparison_url ==
             "https://www.fastretailing.com/jp/ir/library/pdf/unpredictable.PDF?download=1&lang=ja"

    assert release.anchor_text == "第3四半期決算 (PDF)"
    assert release.headings == [{2, "2026年8月期"}, {3, "第3四半期決算"}]
    assert correction.url == "https://www.fastretailing.com/ir/other.pdf"
  end

  test "ignores links in comments and scripts and rejects non HTTP links and non PDF paths" do
    html = """
    <!-- <a href='/comment.pdf'>決算短信</a> -->
    <script>const fake = '<a href="/script.pdf">決算短信</a>';</script>
    <a href='javascript:open("bad.pdf")'>決算短信</a>
    <a href='data:application/pdf;base64,AAAA'>決算短信</a>
    <a href='file:///tmp/bad.pdf'>決算短信</a>
    <a href='https://user:password@example.test/bad.pdf'>決算短信</a>
    <a href='news.html?file=x.pdf'>決算短信</a>
    <a>決算短信</a>
    <a href='ok.pdf'>実際の資料</a>
    """

    assert {:ok, [%{url: "https://example.test/ir/ok.pdf"}]} =
             Discovery.links("https://example.test/ir/", html)
  end

  test "uses the final listing response URL, ignoring unreviewed HTML base overrides" do
    html = "<base href='https://unreviewed.example/'><a href='file.pdf'>決算短信</a>"

    assert {:ok, [%{url: "https://example.test/redirected/file.pdf"}]} =
             Discovery.links("https://example.test/redirected/list.html", html)
  end

  test "keeps changed and correction URLs and does not synthesize missing links" do
    html =
      "<p>FY2027 決算短信</p><a href='old.pdf'>決算短信</a><a href='changed.pdf'>決算短信</a><a href='correction.pdf'>訂正資料</a>"

    assert {:ok, links} = Discovery.links("https://example.test/", html)

    assert Enum.map(links, & &1.url) == [
             "https://example.test/old.pdf",
             "https://example.test/changed.pdf",
             "https://example.test/correction.pdf"
           ]

    assert {:ok, []} = Discovery.links("https://example.test/", "<p>FY2027 第1四半期 決算短信</p>")
  end

  test "a new heading clears older subordinate context" do
    html =
      "<h2>2027年3月期</h2><h3>第1四半期</h3><a href='q1.pdf'>決算短信</a><h2>2026年3月期</h2><a href='prior.pdf'>決算短信</a>"

    assert {:ok, [q1, prior]} = Discovery.links("https://example.test/", html)
    assert q1.headings == [{2, "2027年3月期"}, {3, "第1四半期"}]
    assert prior.headings == [{2, "2026年3月期"}]
  end

  test "canonical comparison deduplicates fragments but keeps the first discovered provenance" do
    html =
      "<a href='https://EXAMPLE.test:443/file.pdf#page=1'>first</a><a href='https://example.test/file.pdf#page=2'>second</a>"

    assert {:ok, [link]} = Discovery.links("https://example.test/", html)
    assert link.url == "https://EXAMPLE.test:443/file.pdf#page=1"
    assert link.comparison_url == "https://example.test/file.pdf"
    assert link.anchor_text == "first"
  end

  test "bounds HTML and candidate count explicitly instead of silently truncating" do
    assert Discovery.links("https://example.test/", String.duplicate("x", 2_097_153)) ==
             {:error, :listing_too_large}

    html = Enum.map_join(1..201, fn n -> "<a href='#{n}.pdf'>決算短信</a>" end)
    assert Discovery.links("https://example.test/", html) == {:error, :too_many_links}
  end

  test "invalid listing URLs and invalid UTF-8 produce explicit errors" do
    assert Discovery.links("file:///tmp/", "<a href='a.pdf'>資料</a>") ==
             {:error, :invalid_listing_url}

    assert Discovery.links("https://example.test/" <> <<255>>, "<a href='a.pdf'>資料</a>") ==
             {:error, :invalid_listing_url}

    assert Discovery.links("https://example.test/", <<255>>) == {:error, :invalid_html}
  end

  test "non-binary listing URLs return a listing URL error" do
    for listing_url <- [nil, :missing, 42] do
      assert Discovery.links(listing_url, "<a href='release.pdf'>決算短信</a>") ==
               {:error, :invalid_listing_url}
    end
  end

  test "identical regular identities in source fixtures remain pending as a selection conflict" do
    fixture =
      File.read!(Path.expand("../../fixtures/source_catalog/cases.json", __DIR__))
      |> Jason.decode!()
      |> Enum.find(&(&1["id"] == "synthetic-conflicting-regular-identities"))

    candidates =
      Enum.map(fixture["documents"], fn document ->
        Identity.from_text("8035", document["pdf_identity_text"])
        |> Map.put(:url, document["expected"]["url"])
      end)

    assert Enum.all?(candidates, &(&1.status == :identified))
    assert {:pending_confirmation, pending} = Identity.select_initial(candidates)
    assert Enum.map(pending, & &1.url) == fixture["expected_discovered_urls"]
    assert fixture["expected_initial_regular_release"] == nil
  end
end
