# Extract and regenerate earnings text from retained originals

GitHub issue: [#72](https://github.com/9renpoto/lens/issues/72)

## Objective

Generate searchable text from retained PDFs and recover from extraction failures without refetching publishers.

## Details

Support text-bearing PDFs only. Extraction is derived processing of an original version and is separate from acquisition success. Preserve the existing Japanese/CJK search normalization behavior.

## Checklist

- [ ] A retained text-bearing PDF produces meaningful plain text associated with the exact original used; preserve paragraph structure where available.
- [ ] Pending, successful, and failed extraction are inspectable. Image-only, unreadable, empty-output, and timed-out inputs retain their original and report a useful failure.
- [ ] Provide a bounded CLI operation to retry one failed original and regenerate already processed material from PostgreSQL with publisher network access disabled.
- [ ] Reprocessing does not create acquisitions, alter original bytes, or duplicate the logical release/search result. Record enough extractor identification to explain the current derived text.
- [ ] Select the latest eligible original with successful extraction for each release. Older/out-of-order extraction completion must not overwrite the text selected for a newer eligible original.
- [ ] When a newer original fails, retain earlier successful text and expose its stale status. With no successful extraction, keep the release inspectable without pretending it has searchable text.
- [ ] The same normalization/rebuild behavior is used for derived search data; regression checks preserve existing feed and CJK behavior.

## Dependencies

Blocked by [#70](P2-preservation.md). Can proceed alongside [#71](P3-collection.md) using synthetic PDF fixtures.

## Notes

Extractor/library choice, timeout and resource bounds, and exact derived-data schema belong to implementation review. Document deterministic version ordering. OCR, financial-table structuring, and semantic revision comparison are deferred. Follow repository TDD and update extraction/rebuild documentation in both languages. Reference: [ADR 0001](../../adr/0001-preserve-original-material-for-reprocessing.md). Related: completed #46.

<details>
<summary>日本語</summary>

# 保存した原本から決算本文を抽出・再生成する

GitHub issue: [#72](https://github.com/9renpoto/lens/issues/72)

## 目的

保存済みPDFから検索用本文を生成し、発行元から再取得せずに抽出失敗から回復できるようにする。

## 詳細

文字情報を持つPDFだけに対応する。本文抽出は原本の版からの派生処理であり、取得成功とは分ける。既存の日本語・CJK検索の正規化動作を維持する。

## チェックリスト

- [ ] 保存した文字情報付きPDFから意味のある本文を生成し、使用した原本を特定できるようにする。取得できる場合は段落構造を保持する。
- [ ] 抽出待ち・成功・失敗を確認できるようにする。画像のみ・読取不能・出力が空・タイムアウトの場合も原本を維持し、失敗理由を示す。
- [ ] 外部の発行元への通信を無効にした状態で、失敗原本1件の再試行と、処理済み資料の再生成をPostgreSQLから実行できる、上限付きのCLI操作を用意する。
- [ ] 再処理で取得記録を増やさず、原本を変更せず、論理的な短信や検索結果を重複させない。現在の派生本文を説明できる抽出器の識別情報を記録する。
- [ ] 短信ごとに、対象となる原本のうち最新の抽出成功版を選ぶ。古い処理が遅れて完了しても、新しい対象原本用に選択された本文を上書きしない。
- [ ] 新版が失敗した場合は旧版の成功本文を維持し、旧版であることを示す。成功本文がない場合は、検索用本文があるように装わず短信を確認できる状態にする。
- [ ] 派生検索データで正規化・再構築の挙動を共通化し、既存フィード・CJK検索の回帰検証を行う。

## 依存関係

[#70](P2-preservation.md)の完了が必要。合成PDFの固定データを使い、[#71](P3-collection.md)と並行して進められる。

## 補足

抽出器・ライブラリー、タイムアウト・資源上限、派生データの厳密なスキーマは実装レビューで決める。版の決定的な順序を記録する。OCR・財務表の構造化・訂正内容の意味的な比較は後続。リポジトリのTDDに従い、本文抽出・再構築の説明を日英で更新する。[ADR 0001](../../adr/0001-preserve-original-material-for-reprocessing.md)を参照。関連：完了済み#46。

</details>
