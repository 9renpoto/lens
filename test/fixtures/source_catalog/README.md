# Source catalog fixtures

`cases.json` is a compact deterministic fixture set for the discovery and
identity contract in `docs/planning/v0.2/source-catalog-fixtures.md`. It keeps
only small listing snippets and first-page PDF identity text; it does not copy
the companies' full pages or original PDFs. Its four `live-*` cases reflect the
three current initial candidates and a historical Tokyo Electron regular-release
/ correction pair checked against official listing/PDF evidence on 2026-09-30.
`synthetic-*` cases are deliberately fictional parser inputs and are not
publisher evidence.

To reproduce expectations, parse each case's `listing_html` anchors relative to
`listing_url`, then compare the discovered URLs and each document's `expected`
object. Map PDF identity text only to fields stated in the PDF; leave absent
fields null.
The Fast Retailing URL is present as the href observed in the fetched official
listing HTML, not constructed from its title or naming pattern.

These are manually reduced/transcribed inputs, not raw HTML snapshots or PDF
bytes. `SHA256SUMS` records the bundled JSON digest, not publisher responses.
They establish expected cases; collection integration tests still need HTTP and
text-bearing PDF fixtures. Verify integrity with `shasum -a 256 -c SHA256SUMS`
from this directory. No publisher network access is needed.

<details>
<summary>日本語</summary>

# 取得元台帳の固定データ

`cases.json`は`docs/planning/v0.2/source-catalog-fixtures.md`の発見・識別契約に
対応する決定的な入力。小型の一覧スニペットとPDF識別情報の文字列を保持し、
企業のページ全体や原本PDFは含めない。4件の`live-*`ケースは2026-09-30に
確認した3社の初期候補と東京エレクトロンの過去の通常短信・訂正資料の組に
由来する。`synthetic-*`は架空の入力で、発行元の証跡ではない。

各`listing_html`のアンカーを`listing_url`から解決し、発見URLと各資料の
`expected`を比較する。PDF識別文字列に明示された値だけを対応付け、欠落値は
nullにする。ファーストリテイリングのリンクは観察したhrefを保持し、表題や
命名規則から生成しない。

これらは手動で縮小・転記した入力で、生のHTMLやPDFバイト列ではない。
`SHA256SUMS`は同梱JSONのダイジェストであり、発行元応答のダイジェストではない。
収集統合テストにはHTTP応答とテキストPDFの固定データが別途必要。
このディレクトリで`shasum -a 256 -c SHA256SUMS`を実行すると整合性を確認できる。
発行元への通信は不要。

</details>
