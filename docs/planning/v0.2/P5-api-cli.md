# Expose earnings search, original retrieval, and processing status

GitHub issue: [#73](https://github.com/9renpoto/lens/issues/73)

## Objective

Let an operator search collected earnings and inspect originals, provenance, and failures through API and CLI without a dedicated new screen.

## Details

Build on the existing JSON search/document boundary where appropriate. Release identity is company, fiscal year-end, reporting period, and category. Do not make the broader target or analytical-review model a dependency.

## Checklist

- [ ] Ordinary search returns one result per identified release using its latest successful extraction. Reacquisition and version history do not multiply results.
- [ ] Search/detail metadata identifies the selected original and indicates stale text when a newer original failed. Preserve existing query validation, normalization, ranking, and pagination behavior.
- [ ] Provide bounded listing/detail access for acquired-but-unsearchable material, pending identity, acquisition failures, and extraction failures through API/CLI.
- [ ] Allow an operator to confirm ambiguous identity through a documented API or CLI operation. Invalid or conflicting confirmation must not silently merge releases or rewrite immutable acquisition facts.
- [ ] Retrieve exact retained original bytes and version history, including older originals, with acquisition URL/time and publisher-reported publication time kept distinct. Do not embed PDF bytes in normal JSON lists/search results.
- [ ] Manual collection and extraction retry/regeneration are discoverable in CLI documentation; errors identify a retryable target without fabricating successful state.
- [ ] Document and test the HTTP/CLI contract, keep existing feed clients valid, and retain the deployment's existing private-access boundary.

## Dependencies

Blocked by [#71](P3-collection.md) and [#72](P4-extraction.md). Use [#70](P2-preservation.md)'s identity/provenance contract.

## Notes

Endpoint names, CLI names, and response schema are implementation choices subject to contract tests and OpenAPI documentation. No new UI or public-sharing feature is required. Related: #49 (existing observation API) and #51 (broader filters); neither is a hard dependency. Keep English and collapsed Japanese explanations aligned.

<details>
<summary>日本語</summary>

# 決算検索・原本取得・処理状態を公開する

GitHub issue: [#73](https://github.com/9renpoto/lens/issues/73)

## 目的

新しい専用画面を作らず、運用者がAPI・CLIで収集した決算情報を検索し、原本・出典情報・失敗を確認できるようにする。

## 詳細

適切な箇所では既存のJSON検索・Documentの境界を利用する。短信の同一性は企業・決算期末・対象期間・資料種類で定める。広範な対象企業モデルや分析レビューモデルを前提にしない。

## チェックリスト

- [ ] 通常の検索では、識別済みの短信ごとに最新の抽出成功版を1件返す。再取得や版の履歴で結果を増やさない。
- [ ] 検索・詳細のメタデータで選択中の原本を特定でき、新版の抽出失敗時は旧版本文であることを示す。既存のクエリ検証・正規化・順位付け・ページングを維持する。
- [ ] 取得済みだが未検索の資料、識別確認待ち、取得失敗、抽出失敗について、API・CLIから上限付きの一覧・詳細を確認できるようにする。
- [ ] 文書化したAPIまたはCLIで、運用者が曖昧な識別情報を確定できるようにする。不正・競合する確定操作によって、短信を黙って統合したり不変の取得事実を書き換えたりしない。
- [ ] 過去原本を含む、保存した原本の正確なバイト列と版の履歴を取得できるようにする。取得元URL・取得日時・発行元の公開日時を区別する。通常のJSON一覧・検索結果にPDFバイト列を埋め込まない。
- [ ] CLIの説明から手動収集・抽出の再試行・再生成を見つけられるようにする。エラーでは成功状態を捏造せず、再試行できる対象を示す。
- [ ] HTTP・CLIの契約を文書化・検証し、既存フィードの利用クライアントとデプロイの非公開アクセス境界を維持する。

## 依存関係

[#71](P3-collection.md)・[#72](P4-extraction.md)の完了が必要。[#70](P2-preservation.md)の識別・出典情報の契約を使う。

## 補足

API・CLI名とレスポンススキーマは、契約テストとOpenAPIの文書化を伴う実装上の選択とする。新しいUIや外部共有機能は不要。関連：#49（既存Observation API）・#51（広範な絞り込み）。いずれも必須の依存先ではない。英語と折りたたみ内の日本語説明を揃える。

</details>
