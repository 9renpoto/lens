# Earnings source evaluation

This is a source-selection aid for [release tracker #68](https://github.com/9renpoto/lens/issues/68).
No acquisition route has been selected or implemented. Facts below were checked
against official sources on 2026-09-15. A partial live recheck was made on
2026-09-30; details and remaining gaps are recorded below. The reproducible
fixture and classification contract is in
[the source catalog fixture contract](planning/v0.2/source-catalog-fixtures.md).

| Candidate | Verified facts | Remaining decision or investigation |
| --- | --- | --- |
| TDnet public disclosure viewer | Lists the most recent 31 days, with PDF and financial-results XBRL/HTML. JPX asks users to refrain from automated acquisition such as scraping. | Do not adopt this viewer as the pilot's automated acquisition route. |
| TDnet API | Paid service providing five years of disclosures, including earnings PDFs and XBRL; documentation and a test environment are available. | Evaluate cost, terms, and preservation conditions if a paid route is desired. |
| Company official IR | A company IR library can provide categorized earnings materials and historical documents. Structure and coverage vary by company. | Inventory each selected issuer's URLs, document types, historical coverage, and automated-acquisition conditions. |
| EDINET | A statutory disclosure system, including annual securities reports; its API requires registration and a key. | Treat as a separate source candidate rather than assuming it substitutes for earnings releases. |

Sources: [JPX public-viewer guidance](https://www.jpx.co.jp/listing/disclosure/01.html),
[TDnet API](https://www.jpx.co.jp/markets/paid-info-listing/tdnet/02.html),
[example company IR library](https://www.fastretailing.com/eng/ir/library/),
[FSA EDINET overview](https://www.fsa.go.jp/search/20130917.html), and
[EDINET portal](https://disclosure2.edinet-fsa.go.jp/week0020.aspx).

The JPX viewer guidance describes title corrections and removal of PDF access
after deletion. A source URL is therefore not sufficient to guarantee future
access to material. The agreed original-preservation direction is recorded in
[preservation issue #70](https://github.com/9renpoto/lens/issues/70).

## Pilot catalog fields to investigate

- Issuer identity and dated evidence for its selection.
- Official listing URL and original-document URL.
- Document category, format, language, and available history.
- Acquisition conditions and supported update-discovery mechanism.
- Publisher-reported publication time, where available.
- Representative material for acquisition, preservation, extraction, and search
  acceptance scenarios.

These fields are an investigation checklist, not a committed database schema.

## Fixed pilot company set

The agreed selection rule is the three largest Nikkei 225 index weights at a
recorded reference date, held fixed for the pilot. The official daily summary
available during planning gives the following set for **2026-09-14**:

| Code | Company | Index weight |
| --- | --- | --- |
| 6857 | Advantest | 11.81% |
| 9983 | Fast Retailing | 8.46% |
| 8035 | Tokyo Electron | 8.07% |

Source: [Nikkei official daily summary, 2026-09-14](https://indexes.nikkei.co.jp/nkave/archives/summary?dt=20260914&idx=nk225).
Index weight is the selection measure; it is not the day's price-movement
contribution or company market capitalization. Do not automatically replace
companies when weights change.

Initial documents are Japanese earnings-release PDFs: select the latest
confirmed regular release for each issuer at collection initialization, then
retain newly listed periods as separate identities. Company IR routes and
acquisition conditions still require verification; inclusion in this table
does not assert an operational collection route.

## Verified initial document candidates

The following Japanese PDFs and their issuer, period, and publisher-reported
publication date were confirmed on 2026-09-30. As of that date, these are the
latest regular releases shown by the official listings: Advantest's next Q2
release was scheduled for 2026-10-28, Tokyo Electron's next Q2 release for
2026-10-30, and Fast Retailing's listing showed Q3 as its newest regular
release. These are dated results, not hard-coded choices for a later
initialization.

| Company | Official listing | Latest confirmed release | Original PDF |
| --- | --- | --- | --- |
| Advantest | [Results](https://www.advantest.com/ja/investors/ir-library/result/) | FY ending March 2027, Q1; 2026-07-29 | [Original](https://www.advantest.com/document/ja/investors/ir-library/result/J_FR_FY2026_1Q.pdf) |
| Fast Retailing | [Earnings releases](https://www.fastretailing.com/jp/ir/library/tanshin.html) | FY ending August 2026, Q3; 2026-07-09 | [Original](https://www.fastretailing.com/jp/ir/library/pdf/tanshin202608_3q.pdf) |
| Tokyo Electron | [Calendar and materials](https://www.tel.co.jp/ir/calendar/) | FY ending March 2027, Q1; 2026-07-30 | [Original](https://www.tel.co.jp/ir/library/report/negqvb0000000eqw-att/fy27q1tanshin-j.pdf) |

Acquisition-condition review remains **unresolved for all three**. The terms
pages are [Advantest](https://www.advantest.com/ja/legal/),
[Fast Retailing](https://www.fastretailing.com/jp/disclaimer/), and
[Tokyo Electron](https://www.tel.co.jp/copyright/index.html). On 2026-09-30,
Advantest robots.txt returned HTTP 200 with no disallow rule; Fast Retailing and
Tokyo Electron returned HTTP 404. The reviewed terms and responses do not
establish permission for automated polling or retained copies, nor a publisher
request cadence. Keep each route inactive until those conditions are resolved.

Discovery details to verify in [#69](https://github.com/9renpoto/lens/issues/69):

- Advantest's listing year and the fiscal year-end printed in the PDF use
  different labels; do not use the listing year alone as disclosure identity.
- Tokyo Electron also lists correction materials. Define whether a listing is
  a regular new-period release before selecting initial/new releases; preserve
  changed acquired bytes without implying correction analysis is implemented.
- The initial research-tool text extraction did not show Fast Retailing's PDF
  links. Direct HTML inspection on 2026-09-30 found the published href recorded
  below; the fixture preserves that observed link instead of extrapolating a URL
  from its filename.

## #69 verification status (2026-09-30)

Official listing pages and five linked PDFs (three initial candidates and one
historical regular/correction pair) were inspected on 2026-09-30 using the
official company domains. This was a read-only review. Terms pages and
robots.txt responses were reviewed, but they did not establish permission for
automated polling or retained copies, or a publisher request cadence. Proposed
daily client policy is recorded below; all routes remain inactive pending
permission review. Local fixtures provide a separate, reproducible check of
discovery and identity expectations.

| Issuer | Listing observation and PDF evidence | Current identity result | Remaining condition check |
| --- | --- | --- | --- |
| Advantest (6857) | [Official listing](https://www.advantest.com/ja/investors/ir-library/result/) displays FY2026 Q1 dated 2026-07-29 and links to `J_FR_FY2026_1Q.pdf`; [linked PDF](https://www.advantest.com/document/ja/investors/ir-library/result/J_FR_FY2026_1Q.pdf) states 2027年3月期第1四半期, date 2026-07-29, code 6857. The [IR calendar](https://www.advantest.com/ja/investors/ir-calendar/) scheduled Q2 for 2026-10-28. | 2027-03-31 / Q1 / earnings_release / 2026-07-29 verified on 2026-09-30; latest listed regular release as of that date. This confirms that the listing-year label cannot be the fiscal-year identity. robots.txt returned HTTP 200 with `User-agent: *` and an empty `Disallow`. | [Terms](https://www.advantest.com/ja/legal/) require prior written consent for use of site information beyond legally permitted scope. Automated acquisition and original-retention use need clarification; robots.txt does not grant permission. Polling rate unknown. |
| Fast Retailing (9983) | [Official listing](https://www.fastretailing.com/jp/ir/library/tanshin.html) states last updated 2026-07-09 and lists 2026年8月期 Q3, Q2, Q1. Direct HTML inspection found the published href `/jp/ir/library/pdf/tanshin202608_3q.pdf`; the [linked PDF](https://www.fastretailing.com/jp/ir/library/pdf/tanshin202608_3q.pdf) returned HTTP 200, `application/pdf`, 762,804 bytes. | PDF states 2026年8月期第3四半期, code 9983, publication date 2026-07-09. Identity 2026-08-31 / Q3 / earnings_release / 2026-07-09 verified on 2026-09-30; newest regular release on the listing as of that date. PDF SHA-256: `e3237a04df1c97f7cf0a5f9b6b42ed1877fc0698c7ecba89824fd8bfda130ba3`. | [Site usage](https://www.fastretailing.com/jp/termsofuse/) documents RSS for news and IR-news updates, not permission to poll the PDF library. [Disclaimer/copyright terms](https://www.fastretailing.com/jp/disclaimer/) limit reproduction to private use and other statutorily permitted scope absent copyright-holder permission. robots.txt returned HTTP 404. Automated request/storage permission and cadence remain unknown. |
| Tokyo Electron (8035) | [Official IR calendar](https://www.tel.co.jp/ir/calendar/) links the 2027年3月期 Q1 release dated 2026-07-30 to [a PDF](https://www.tel.co.jp/ir/library/report/negqvb0000000eqw-att/fy27q1tanshin-j.pdf); linked PDF confirms issuer, period, code 8035, and date. The calendar scheduled Q2 for 2026-10-30. | 2027-03-31 / Q1 / earnings_release / 2026-07-30 verified on 2026-09-30; latest listed regular release as of that date. robots.txt returned HTTP 404. | [Site terms](https://www.tel.co.jp/copyright/index.html) limit copying to noncommercial intra-organization use and reserve other rights unless a document says otherwise. Review individual PDF conditions; automated acquisition permission and cadence remain unknown. |

The Fast Retailing listing response was HTTP 200 (`text/html`); the PDF response
was HTTP 200 (`application/pdf`, 762,804 bytes). The captured listing SHA-256 is
`e62bd75bfe4adc2db406e7416a61d2ff86803e2000d751673f030550a5fa17e9`. Response
date was 2026-09-29 23:08:14 UTC (2026-09-30 JST). Advantest robots.txt was
HTTP 200 and has no disallow rule for `User-agent: *`; Fast Retailing and Tokyo
Electron robots.txt returned HTTP 404, so their crawler rules are unavailable.
No request interval was recorded. The company terms reviewed for Advantest and
Fast Retailing do not establish automated polling or original-retention
permission. Tokyo Electron's site terms state the copying limitation noted
above. Advantest's terms prohibit use of site information beyond the legally
permitted scope without prior written consent; the public release's automated
acquisition and retained-copy use therefore need written clarification. Fast
Retailing's site-use page documents RSS delivery for news and IR-news updates,
not approval to poll the PDF library; its RSS does not currently provide this
catalog route. Its [disclaimer and copyright terms](https://www.fastretailing.com/jp/disclaimer/)
limit reproduction to private use and other statutorily permitted scope absent
copyright-holder permission. Do not treat robots.txt behavior or ordinary
browser access as permission to retain or automatically poll originals.

Proposed Lens client policy (not publisher-approved): check each listing at
most once per host per day; fetch newly discovered PDFs and recheck retained document URLs sequentially,
within the documented per-run request bound; do
not retry a failed request in the same run. Keep all routes inactive until the
applicable permission and preservation terms are resolved.

The initial-selection rule considers only confirmed regular releases, sorting by
fiscal year-end descending and then period (`Q1` < `Q2` < `Q3` < `FY`). This
selects the newest regular period per issuer in the evidence available at
initialization; same-identity conflicts remain pending. Advantest's FY2026
listing label is normalized from the PDF's March 2027 fiscal period. The
correction-selection rule is grounded in a live official archive example:
[Tokyo Electron's 2020-03 Q3 listing](https://www.tel.co.jp/ir/library/report/index.html)
links to the [regular Q3 release](https://www.tel.co.jp/ir/library/report/hq95qj0000002rko-att/fy57q3tanshin_r1-j.pdf)
(published 2020-01-30) and a distinct [correction notice](https://www.tel.co.jp/ir/library/report/hq95qj0000002rko-att/fy57q3tanshin_teisei-j.pdf)
(published 2020-02-04). The correction identifies the original release and
period, so the two materials map to issuer 8035 / FY ending 2020-03-31 / Q3
with categories `earnings_release` and `correction`; only the regular release
is eligible for initial-release selection. The exact discovered URLs and
expected mapping are in the local fixture bundle.

For reproducible fixtures, the dated expected identities remain Advantest
6857 / 2027-03-31 / Q1 / earnings_release / 2026-07-29; Fast Retailing 9983 /
2026-08-31 / Q3 / earnings_release / 2026-07-09; Tokyo Electron 8035 /
2027-03-31 / Q1 / earnings_release / 2026-07-30. They are not dynamic “latest”
selections for a collection initialized today. Corrections must be classified
separately, and ambiguous fields must remain pending rather than inferred from
URL or fetch time.

The source-evaluation criteria are documented. The unresolved operational work
is to obtain publisher clarification on automated acquisition and storage and
an acceptable request interval. If a route is disallowed or remains
unclear, report that finding rather than silently substituting another issuer
or a paid service.

<details>
<summary>日本語</summary>

# 決算情報の取得元評価

[親issue #68](https://github.com/9renpoto/lens/issues/68)の取得元選定資料。取得経路の確定や実装はまだ行っていない。一般候補は2026-09-15、固定3社の一覧・原本・利用条件は2026-09-30に公式情報で確認した。取得を始める前に条件を再確認する。

| 候補 | 確認した事実 | 残る決定・調査 |
| --- | --- | --- |
| TDnetの無料閲覧サービス | 直近31日分を掲載し、PDFと決算情報のXBRL・HTMLを提供。JPXはスクレイピング等の自動取得を控えるよう案内 | パイロットの自動取得経路には採用しない |
| TDnet API | 過去5年分の開示を提供する有料サービス。決算PDF・XBRLに対応し、仕様書とテスト環境がある | 有料経路を検討する場合に費用・利用条件・保存条件を評価 |
| 企業公式IR | 種類別の決算資料や過去資料を掲載する企業IRライブラリーがある。構造と掲載範囲は企業ごとに異なる | 選定企業ごとのURL・資料種類・掲載期間・自動取得条件を台帳化 |
| EDINET | 有価証券報告書等を扱う法定開示システム。APIには利用登録とキーが必要 | 決算短信の代替とみなさず、別の取得元候補として扱う |

出典：[JPXの無料閲覧サービス案内](https://www.jpx.co.jp/listing/disclosure/01.html)、[TDnet API](https://www.jpx.co.jp/markets/paid-info-listing/tdnet/02.html)、[企業IRライブラリーの例](https://www.fastretailing.com/eng/ir/library/)、[金融庁のEDINET概要](https://www.fsa.go.jp/search/20130917.html)、[EDINET](https://disclosure2.edinet-fsa.go.jp/week0020.aspx)。

JPXの閲覧サービス案内では、表題訂正や削除後のPDF閲覧停止が説明されている。そのため、取得元URLだけでは将来の参照を保証できない。合意した原本保存の方針は[preservation issue #70](https://github.com/9renpoto/lens/issues/70)を参照。

## パイロット台帳で調べる項目

- 発行企業の識別情報と、基準日付きの選定根拠。
- 公式の資料一覧URLと原本URL。
- 資料の分類・形式・言語・過去資料の掲載範囲。
- 取得条件と更新情報の発見方法。
- 発行元が示す公開日時（存在する場合）。
- 取得・保存・本文抽出・検索の受入シナリオに使う代表資料。

これらは調査チェックリストであり、確定したDBスキーマではない。

## 固定するパイロット対象企業

選定規則は、記録した基準日の日経平均構成比率上位3社をパイロット期間中固定すること。計画時に確認した公式日次サマリーの**2026-09-14**の値は以下のとおり。

| コード | 企業 | 構成比率 |
| --- | --- | --- |
| 6857 | アドバンテスト | 11.81% |
| 9983 | ファーストリテイリング | 8.46% |
| 8035 | 東京エレクトロン | 8.07% |

出典：[日経公式日次サマリー・2026-09-14](https://indexes.nikkei.co.jp/nkave/archives/summary?dt=20260914&idx=nk225)。選定に使うのは指数の構成比率であり、当日の騰落寄与度や時価総額とは異なる。構成比率が変わっても対象企業を自動では入れ替えない。

初期対象は日本語の決算短信PDF。収集開始時点で識別が確定した通常資料のうち、決算期末・対象期間が最も新しいものを選ぶ。その後の掲載分は別の識別情報として保持する。各社IRの取得経路と条件は引き続き検証が必要であり、この表への掲載は運用可能な取得経路の確定を意味しない。

## 確認した初回資料の候補

以下の日本語PDFについて、企業・対象期間・発行元公表日を2026-09-30に確認した。同日現在、公式一覧上で各社の最新通常資料である。アドバンテストの次のQ2資料は2026-10-28、東京エレクトロンの次のQ2資料は2026-10-30に予定され、ファーストリテイリングの一覧ではQ3が最新だった。後日収集を開始する環境でURLを固定するものではない。

| 企業 | 公式一覧 | 確認した最新短信 | 原本PDF |
| --- | --- | --- | --- |
| アドバンテスト | [決算公表資料](https://www.advantest.com/ja/investors/ir-library/result/) | 2027年3月期 第1四半期、2026-07-29 | [原本](https://www.advantest.com/document/ja/investors/ir-library/result/J_FR_FY2026_1Q.pdf) |
| ファーストリテイリング | [決算短信一覧](https://www.fastretailing.com/jp/ir/library/tanshin.html) | 2026年8月期 第3四半期、2026-07-09 | [原本](https://www.fastretailing.com/jp/ir/library/pdf/tanshin202608_3q.pdf) |
| 東京エレクトロン | [IRカレンダー・資料一覧](https://www.tel.co.jp/ir/calendar/) | 2027年3月期 第1四半期、2026-07-30 | [原本](https://www.tel.co.jp/ir/library/report/negqvb0000000eqw-att/fy27q1tanshin-j.pdf) |

取得条件は**3社とも未解決**。[利用条件](https://www.advantest.com/ja/legal/)、[ファーストリテイリングの免責・著作権条件](https://www.fastretailing.com/jp/disclaimer/)、[東京エレクトロンの条件](https://www.tel.co.jp/copyright/index.html)とrobots.txt応答を2026-09-30に確認した。アドバンテストはHTTP 200で禁止規則なし、他2社はHTTP 404。これらから自動巡回・原本保存の許可や発行元のリクエスト間隔は確定できない。条件が明らかになるまで各経路は無効のままにする。

[#69](https://github.com/9renpoto/lens/issues/69)で確認する発見処理の詳細：

- アドバンテストは一覧の年度表記とPDF内の決算期末表記が異なる。一覧の年だけを決算短信の識別に使わない。
- 東京エレクトロンは訂正資料も掲載する。初回・新規資料を選ぶ前に通常の新期短信を識別する規則を定める。取得したバイト列の変更は保存するが、訂正分析の実装を意味するものではない。
- 初回の調査ツールによるテキスト抽出ではファーストリテイリングのPDFリンクを確認できなかったが、2026-09-30に実HTMLから実際のhrefを発見した。固定データには観察したhrefを保存し、ファイル名からURLを推測しない。

## #69 確認状況（2026-09-30）

2026-09-30に公式企業ドメインの一覧ページと5件のPDF（初期候補3件、東京エレクトロンの過去の通常資料・訂正資料）を確認した。これは読み取り専用の確認である。利用条件とrobots.txt応答も確認したが、自動巡回や原本保存の許可、および発行元の取得間隔は確立していない。クライアント側の日次方針案を下記に記録し、許可確認まで自動取得経路は無効にする。ローカル固定データは別途、発見・識別結果の再現可能な確認に使う。

| 企業 | 一覧の観察とPDF証跡 | 現在確認できた識別情報 | 残る取得条件 |
| --- | --- | --- | --- |
| アドバンテスト（6857） | [公式一覧](https://www.advantest.com/ja/investors/ir-library/result/)にFY2026第1四半期、2026-07-29と掲載され、[原本PDF](https://www.advantest.com/document/ja/investors/ir-library/result/J_FR_FY2026_1Q.pdf)へのリンクあり。PDFに2027年3月期第1四半期・公表日2026-07-29・コード6857と記載。[IRカレンダー](https://www.advantest.com/ja/investors/ir-calendar/)はQ2を2026-10-28予定としている。 | 2027-03-31／Q1／通常決算短信／2026-07-29を2026-09-30確認。確認可能な一覧上で同日現在の最新通常資料。年度ラベルだけでは決算期を識別できないことも確認。robots.txtはHTTP 200、`User-agent: *`に`Disallow`なし。 | [利用条件](https://www.advantest.com/ja/legal/)は、法的に許容される範囲を超えた利用に事前の書面承諾を要求。自動取得・原本保存の許可や取得間隔は未確認。robots.txtは許可を意味しない。 |
| ファーストリテイリング（9983） | [公式一覧](https://www.fastretailing.com/jp/ir/library/tanshin.html)の実HTMLから`/jp/ir/library/pdf/tanshin202608_3q.pdf`を発見。原本PDFはHTTP 200、762,804 bytes。SHA-256：`e3237a04df1c97f7cf0a5f9b6b42ed1877fc0698c7ecba89824fd8bfda130ba3`。PDFに2026年8月期第3四半期・コード9983・公表日2026-07-09と記載。 | 2026-08-31／Q3／通常決算短信／2026-07-09を2026-09-30確認。確認可能な一覧上で同日現在の最新通常資料。 | [サイト利用方法](https://www.fastretailing.com/jp/termsofuse/)のRSS説明はニュース・IRニュース向けで、PDF一覧の巡回許可ではない。[免責・著作権条件](https://www.fastretailing.com/jp/disclaimer/)は、私的使用その他著作権法上認められた範囲を超える複製を著作権者の許諾なしに認めない。robots.txtはHTTP 404。自動取得・原本保存の許可と間隔は不明。 |
| 東京エレクトロン（8035） | [公式IRカレンダー](https://www.tel.co.jp/ir/calendar/)から2027年3月期第1四半期・2026-07-30の[原本PDF](https://www.tel.co.jp/ir/library/report/negqvb0000000eqw-att/fy27q1tanshin-j.pdf)へリンク。PDFで発行元・期間・コード8035・公表日を確認。同カレンダーはQ2を2026-10-30予定としている。 | 2027-03-31／Q1／通常決算短信／2026-07-30を2026-09-30確認。確認可能な一覧上で同日現在の最新通常資料。robots.txtはHTTP 404。 | [利用条件](https://www.tel.co.jp/copyright/index.html)と個別PDF条件を確認。サイト条件は非営利かつ組織内利用に限る複製を認め、それ以外の権利を留保。自動取得許可と間隔は不明。 |

ファーストリテイリング一覧の応答はHTTP 200（`text/html`）、PDFはHTTP 200（`application/pdf`、762,804 bytes）。取得した一覧のSHA-256は`e62bd75bfe4adc2db406e7416a61d2ff86803e2000d751673f030550a5fa17e9`。応答日時は2026-09-29 23:08:14 UTC（2026-09-30 JST）。アドバンテストのrobots.txtはHTTP 200で`User-agent: *`に禁止規則なし。ファーストリテイリングと東京エレクトロンのrobots.txtはHTTP 404で取得できなかった。リクエスト間隔は観察していない。アドバンテストの利用条件は法的に許容される範囲を超える利用に事前の書面承諾を要求する。ファーストリテイリングのサイト利用方法はニュース・IRニュースのRSS配信を説明しているが、PDFライブラリーの巡回許可は示していない。免責・著作権条件は、私的使用等の法的例外を超える複製について権利者の許諾を求めている。東京エレクトロンのサイト条件には上記の複製制限がある。robots.txtや通常のブラウザーアクセスを、原本保存や自動巡回の許可として扱わない。

Lens側の日次方針案（発行元の許可ではない）：ホストごとの一覧確認は1日1回まで。新規発見PDFの取得と保存済み資料URLの再確認を、文書化した実行あたりの要求上限内で逐次実行し、同一実行内で失敗リクエストを再試行しない。適用される許可と保存条件が明確になるまで、全経路を無効のままにする。

初期資料は識別が確定した通常資料だけを決算期末の降順、次に期間順（Q1 < Q2 < Q3 < FY）で並べ、先頭を選ぶ。同一識別情報の候補が複数ある場合は確認待ちにする。アドバンテストのFY2026という一覧表記はPDFの2027年3月期から正規化する。訂正資料の選択規則は公式アーカイブの実例で確認した。[東京エレクトロンの2020年3月期第3四半期一覧](https://www.tel.co.jp/ir/library/report/index.html)から、2020-01-30公表の[通常短信](https://www.tel.co.jp/ir/library/report/hq95qj0000002rko-att/fy57q3tanshin_r1-j.pdf)と2020-02-04公表の[別掲載訂正資料](https://www.tel.co.jp/ir/library/report/hq95qj0000002rko-att/fy57q3tanshin_teisei-j.pdf)を確認した。訂正資料は元資料と期間を明示するため、企業8035／決算期末2020-03-31／Q3に対応させ、通常短信と訂正資料で資料種類を分ける。初期資料として選ぶのは通常短信のみ。発見URLと期待結果はローカル固定データにある。

固定データ向けの候補識別情報は、アドバンテスト6857／2027-03-31／Q1／通常決算短信／2026-07-29、ファーストリテイリング9983／2026-08-31／Q3／通常決算短信／2026-07-09、東京エレクトロン8035／2027-03-31／Q1／通常決算短信／2026-07-30。これらは2026-09-30時点の最新通常資料として確認した候補であり、後日の収集開始時は一覧を再発見して選択規則を適用する。訂正資料は別分類とし、曖昧な値はURLや取得時刻から推測せず確認待ちにする。

選定・発見・識別の確認項目は記録済み。残る運用上の作業は、3社に自動取得・原本保存の条件と許容可能なリクエスト間隔を確認すること。経路が禁止または不明確なら、その事実を報告し、他社や有料サービスに無断で置き換えない。

</details>
