# Source catalog fixture contract

This file defines deterministic fixture inputs for the live source investigation
in [#69](https://github.com/9renpoto/lens/issues/69). Fixtures verify discovery and classification
logic; they are not evidence that a publisher currently serves a URL or permits
automated access. Record live verification separately in
[the evaluation ledger](../../earnings-source-evaluation.md).

## Discovery input and output

For each issuer, retain the fetched listing bytes, final response URL, response
time, status, content type, and relevant response headers as a dated fixture.
The discovery step must parse actual anchors (including links inside scripts or
data attributes only when the page's documented rendering requires it), resolve
relative URLs against the final listing URL, and retain the original discovered
URL. It must not synthesize a PDF URL from a title, year, or naming pattern.
Redirects are bounded and requests are sequential. Proposed daily policy: at
most one listing check per host per day; fetch newly discovered PDFs and recheck retained document URLs only within the
documented request bound required by #71; do not retry a failed request in the
same run. The checked set and bounds must be defined before enabling a route. This is a
conservative client policy, not publisher authorization. Honor robots.txt
disallow rules; an unavailable robots.txt or unclear terms means the automated
route remains inactive pending review.

Normalize only for comparison: lowercase scheme/host, remove default ports and
fragments, and preserve path, query, and the exact discovered URL as provenance.
Never discard a candidate merely because its URL resembles a known correction
or prior filing.

## Identity mapping contract

Each candidate maps to issuer code, fiscal year-end, period (Q1/Q2/Q3/FY),
material category (`earnings_release` or `correction`), publisher-reported date,
listing URL, and original URL. Unknown values remain null. A candidate is
`pending_confirmation` if issuer, period, fiscal year-end, or category cannot be
resolved unambiguously from listing metadata and the PDF itself. A filename is
supporting evidence only, never the sole basis for release identity.

Fiscal-year labels are normalized from the period printed in the document. For
Advantest, a listing label such as FY2026 can describe the fiscal year ending in
March 2027; store the date `2027-03-31` as fiscal year-end while preserving the
source label as observed metadata. Fast Retailing's fiscal year-end is August
31. Tokyo Electron's is March 31. Do not infer a publication date from a URL,
filing period, or local fetch timestamp.

## Selection rule

Group candidates with a confirmed issuer code by issuer first; candidates with
missing or unsupported issuer codes remain pending and cannot be selected.
Within each issuer, among candidates with confirmed fiscal year-end, reporting
period, and `earnings_release` category,
order by fiscal year-end descending and then period ordinal descending
(`Q1` < `Q2` < `Q3` < `FY`). Select one first candidate per issuer for
initialization. Corrections are separate materials and never
displace the regular release. If two candidates claim the same logical
identity, or metadata conflicts, return both as pending and require review; do
not break the tie by URL order. A later regular-period release is a new
identity, not a replacement of the prior quarter.

## Expected fixture cases

Each document-level `expected` result, including single-document cases, records
both its original `url` and the `listing_url` used to discover that URL.

| Case | Fixture facts | Expected result |
| --- | --- | --- |
| Advantest initial | Listing label `FY2026 1Q`; PDF states year ending March 31, 2027, first quarter; date 2026-07-29; anchor points to `J_FR_FY2026_1Q.pdf` | Discover the anchor URL as published; retain the listing URL on the candidate; issuer 6857; fiscal year-end 2027-03-31; Q1; earnings_release; publication date 2026-07-29; selected as initial regular release for issuer 6857 |
| Fast Retailing initial | HTML anchor href points to `pdf/tanshin202608_3q.pdf`; link is discovered from fixture DOM, not constructed; PDF states year ending August 31, 2026, third quarter; date 2026-07-09 | Resolve against the listing URL; issuer 9983; fiscal year-end 2026-08-31; Q3; earnings_release; publication date 2026-07-09; selected |
| Tokyo Electron initial plus correction | Regular Q1 PDF states year ending March 31, 2027, date 2026-07-30; a separately listed correction has an ambiguous title and no explicit period | Discover both actual links; map the regular PDF to issuer 8035 / 2027-03-31 / Q1 / earnings_release and select it; keep correction pending unless its own contents establish identity/category |
| Tokyo Electron confirmed correction pair | Its official archive lists the 2020-03 Q3 regular release dated 2020-01-30 and a separately linked correction dated 2020-02-04; the correction names the original Q3 release | Discover both published hrefs; identify both as issuer 8035 / FY ending 2020-03-31 / Q3 with separate categories and dates; select the regular release and retain the correction as a distinct material |
| Later regular release | A subsequent listing and PDF unambiguously state the next fiscal period and ordinary earnings release | Discover the new anchor; classify with its own period identity and select it over the earlier regular release at initialization; retain the earlier identity |
| Ambiguous metadata | Listing title suggests Q2 but PDF has no period or fiscal-year-end and URL embeds a year | Discover the URL, but leave identity and selection pending; do not infer missing fields from URL or fetch time |
| Conflicting regular identities | Two PDFs for the same issuer both state FY ending March 31, 2027 / Q1 | Discover both URLs; keep both candidates pending and select neither |

The current [fixture bundle](../../../test/fixtures/source_catalog/cases.json)
contains manually reduced listing snippets and transcribed PDF identity text,
not raw response snapshots or retained publisher PDFs. Its SHA-256 manifest
checks fixture integrity only. It covers three initial candidates and a historical
regular/correction pair; later-period, ambiguous, and conflicting-identity cases are synthetic.
Collection integration tests must add small text-bearing PDF fixtures and HTTP
response fixtures; these text inputs alone do not prove PDF extraction or live
listing parser compatibility. Fixture assertions should include the
exact set of discovered URLs and identity result; a test that only checks a
hard-coded expected URL does not exercise discovery.

## Live evidence record template

For each host, record check date/time (UTC), request URL and final URL, status,
robots.txt result, terms page and relevant clause, observed request interval,
listing snapshot digest, discovered original URL, response type/size, and the
identity fields read from the PDF. If any item cannot be verified, write
`unknown` and keep the route inactive. The 2026-09-15 candidate URLs in the
evaluation ledger are historical reference points, not present-day verification.

<details>
<summary>日本語</summary>

# 取得元台帳の固定データ契約

この文書は[#69](https://github.com/9renpoto/lens/issues/69)の実サイト調査に使う、再現可能な固定データ入力を定義する。固定データは発見・分類処理の検証に使うもので、発行元が現在URLを提供していることや自動取得を許可していることの証拠ではない。実サイト確認は[取得元評価台帳](../../earnings-source-evaluation.md)に分けて記録する。

## 発見の入力と出力

各社について、取得した一覧ページのバイト列、最終応答URL、応答時刻、状態コード、Content-Type、関連ヘッダーを日付付き固定データとして保存する。発見処理は実際のアンカーを解析し（ページの仕様上必要な場合に限り、スクリプトやdata属性内のリンクも解析する）、一覧の最終URLを基準に相対URLを解決して、発見した原本URLをそのまま保持する。表題・年度・命名パターンからPDF URLを合成してはならない。リダイレクトには上限を設け、リクエストは逐次実行する。提案する日次方針は、ホストごとの一覧確認を1日1回までとし、新規発見PDFの取得と保存済み資料URLの再確認を#71で文書化するリクエスト上限内に限定し、同一実行内では失敗リクエストを再試行しないこと。有効化前に確認対象と上限を定める。これはクライアント側の保守的な方針であり、発行元の許可を意味しない。robots.txtの禁止規則に従う。robots.txtを取得できない場合や利用条件が不明確な場合、自動取得経路はレビューまで無効とする。

比較用の正規化では、スキーム・ホストを小文字化し、既定ポートとフラグメントを取り除く。パス・クエリ、および出典情報としての発見時URLは保持する。訂正や過去資料に似たURLでも候補から除外しない。

## 識別情報の対応規則

候補ごとに、企業コード、決算期末、対象期間（Q1/Q2/Q3/FY）、資料種類（`earnings_release`または`correction`）、発行元公表日、一覧URL、原本URLを対応付ける。一覧情報とPDFから企業・対象期間・決算期末・資料種類を一意に決められない場合は`pending_confirmation`とする。不明値はnullのまま保持する。ファイル名は補助的証拠に限り、短信の識別根拠として単独では使わない。

年度末は資料に記載された対象期間から正規化する。アドバンテストでは、一覧のFY2026が2027年3月期を指す場合がある。決算期末には`2027-03-31`を保存し、観察した元の年度ラベルもメタデータとして保持する。ファーストリテイリングの決算期末は8月31日、東京エレクトロンは3月31日。不明な公表日をURL、対象期間、取得時刻から推測しない。

## 選択規則

企業コードを確定できた候補だけを企業ごとに分ける。企業コードが不明または未対応の候補は確認待ちにし、選択しない。各企業内で決算期末・対象期間・`earnings_release`が確定したものを、決算期末の降順、次に対象期間の序数降順（`Q1` < `Q2` < `Q3` < `FY`）で並べ、企業ごとに先頭を初期資料として選ぶ。訂正資料は別資料として扱い、通常資料の代わりに選ばない。二つの候補が同じ論理識別情報を主張する場合、またはメタデータが矛盾する場合は両方を確認待ちにし、URL順で決着させない。後続期の通常資料は新しい識別情報であり、前期資料を置換しない。

## 期待する固定データケース

各資料の`expected`には、単一資料のケースも含め、原本`url`とリンク発見元の`listing_url`を記録する。

| ケース | 固定データの事実 | 期待結果 |
| --- | --- | --- |
| アドバンテスト初期資料 | 一覧ラベル`FY2026 1Q`。PDFに2027年3月31日終了年度の第1四半期、公表日2026-07-29と記載。アンカーは`J_FR_FY2026_1Q.pdf`を指す | 公開されたアンカーURLを発見。企業6857、決算期末2027-03-31、Q1、通常決算短信、公表日2026-07-29として識別し、初期資料に選択 |
| ファーストリテイリング初期資料 | HTMLアンカーのhrefが`pdf/tanshin202608_3q.pdf`を指す。PDFに2026年8月31日終了年度の第3四半期、公表日2026-07-09と記載 | 固定データDOMからリンクを発見し、一覧URLを基準に解決。企業9983、決算期末2026-08-31、Q3、通常決算短信、公表日2026-07-09として識別し選択 |
| 東京エレクトロン初期資料と訂正 | 通常の第1四半期PDFに2027年3月31日終了年度、公表日2026-07-30と記載。別掲載の訂正資料は表題が曖昧で、対象期間の明示なし | 実際の両リンクを発見。通常PDFは企業8035・2027-03-31・Q1・通常決算短信として選択。訂正PDFは内容で種類と識別が確定しなければ確認待ち |
| 東京エレクトロンの確認済み訂正資料の組 | 公式アーカイブに2020年3月期第3四半期の通常短信（2020-01-30）と別掲載の訂正資料（2020-02-04）があり、訂正資料が元短信を明示 | 両リンクを発見し、企業8035・2020-03-31・Q3に対応付ける。種類と公表日は分離し、通常短信のみを初期資料として選択 |
| 後続の通常資料 | 後続の一覧・PDFに次の決算期間と通常資料であることが明記 | 新しいアンカーを発見し、独自の期間識別情報を付与。初期化時には以前より新しい通常資料を選択し、前期識別情報も保持 |
| 曖昧なメタデータ | 一覧表題はQ2を示唆するがPDFに対象期間・決算期末がなく、URLには年度が含まれる | URLを発見するが識別・選択は確認待ち。URLや取得時刻から欠落情報を補わない |
| 同一識別情報が競合する通常資料 | 同一企業の2件のPDFに2027年3月期第1四半期と記載 | 両方のURLを発見し、両候補を確認待ちにして初期資料を選ばない |

現在の固定データは手動で縮小した一覧HTMLとPDF識別情報の転記であり、生の応答スナップショットや発行元PDFではない。SHA-256マニフェストは固定データの整合性だけを確認する。収集統合テストでは小型テキストPDFとHTTP応答の固定データを追加する必要があり、この文字列入力だけでPDF抽出や実一覧の解析互換性を実証したとは扱わない。リポジトリ内の[`cases.json`](../../../test/fixtures/source_catalog/cases.json)には、ライブ確認から派生した3社の初期候補と、東京エレクトロンの実際の通常第3四半期・別掲載訂正資料の組を収録した。後続期・曖昧な候補・同一識別情報が競合する通常資料は合成ケースと明記してある。期待リンク集合と識別結果を比較する。期待URLを固定値として確認するだけのテストではリンク発見を検証できない。

## 実サイト証跡の記録ひな型

ホストごとにUTC確認日時、要求URLと最終URL、状態コード、robots.txtの結果、利用条件ページと該当条項、観察したリクエスト間隔、一覧スナップショットのダイジェスト、発見した原本URL、応答形式・サイズ、PDFから読んだ識別情報を記録する。検証できない項目は`unknown`とし、取得経路は無効のままにする。取得元評価台帳の2026-09-15の候補URLは過去の参照点であり、現在の確認証跡ではない。

</details>
