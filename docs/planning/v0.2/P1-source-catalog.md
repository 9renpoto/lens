# Validate official earnings sources for the fixed three-company pilot

GitHub issue: [#69](https://github.com/9renpoto/lens/issues/69)

## Objective

Produce a verified source catalog that lets the collection implementation use explicit, reproducible discovery rules.

## Details

Investigate the official Japanese IR listings for Advantest, Fast Retailing, and Tokyo Electron. The [source evaluation](../../earnings-source-evaluation.md) contains dated candidates, known listing differences, and pending acquisition-condition checks.

## Checklist

- [x] Record issuer code/name, 2026-09-14 selection evidence, official listing URL, original URLs, and verification date for all three.
- [x] Record applicable acquisition/preservation conditions and a daily request policy. Report unavailable or unresolved routes explicitly.
- [ ] Resolve publisher permission and request cadence for each proposed route; keep routes inactive until both are confirmed.
- [x] Verify actual link discovery, rather than generating URLs from known filenames.
- [x] Map listing/PDF metadata to company, fiscal year-end, reporting period, category, and publisher-reported publication date. Keep unknown dates unknown.
- [x] Define and demonstrate the latest regular reporting-release selection rule at initialization, including fiscal-year label differences and separately listed corrections.
- [x] Provide expected identity/link/discovery results for a latest release, a later regular release, and ambiguous metadata; document reproducible local fixtures and separate live verification evidence.

## Dependencies

None. Blocks [#71](P3-collection.md); [#70](P2-preservation.md) may proceed using synthetic identity and PDF fixtures.

## Notes

Do not silently replace a company or contract for a paid API when a route is unusable. Report the finding and revisit that route. This task does not implement a generic crawler or financial analysis. Update both English and collapsed Japanese source documentation.

<details>
<summary>日本語</summary>

# 固定3社の公式決算情報取得元を検証する

GitHub issue: [#69](https://github.com/9renpoto/lens/issues/69)

## 目的

明示的かつ再現可能な発見規則を使って収集を実装できる、検証済みの取得元台帳を作る。

## 詳細

アドバンテスト・ファーストリテイリング・東京エレクトロンの日本語公式IR一覧を調べる。[取得元評価](../../earnings-source-evaluation.md)に、日付付きの候補・一覧の相違・未確認の取得条件を記載している。

## チェックリスト

- [x] 3社の企業コード・名称、2026-09-14の選定根拠、公式一覧URL、原本URL、確認日を記録する。
- [x] 適用される取得・保存条件と日次リクエスト方針を記録し、利用不可・未確認の経路を明示する。
- [ ] 提案する各経路について発行元の許可とリクエスト頻度を確認する。両方を確認するまで取得経路を無効にする。
- [x] 既知のファイル名からURLを生成せず、実際のリンク発見を検証する。
- [x] 一覧・PDFの情報を企業・決算期末・対象期間・資料種類・発行元の公開日に対応付ける。不明な日付は不明のまま扱う。
- [x] 初期化時に最新の通常の決算短信を選ぶ規則を定義し、年度表記の差や別掲載の訂正資料を含めて実証する。
- [x] 最新資料・後続の通常資料・識別が曖昧な資料について、期待する識別・リンク・発見結果を用意する。再現可能なローカルの固定データと実サイト確認の証跡を分けて記録する。

## 依存関係

なし。[#71](P3-collection.md)の前提。[#70](P2-preservation.md)は合成した識別情報とPDFの固定データで進められる。

## 補足

経路を利用できない場合に、企業を無断で入れ替えたり有料APIを契約したりしない。調査結果を報告して経路を再検討する。汎用クローラーや財務分析は実装しない。取得元の英語文書と折りたたみ内の日本語訳を更新する。

</details>
