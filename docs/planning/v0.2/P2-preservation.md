# Preserve immutable earnings originals and acquisition history

GitHub issue: [#70](https://github.com/9renpoto/lens/issues/70)

## Objective

Retain official PDF bytes independently of extraction, with release identity and acquisition provenance that survive retries and database restore.

## Details

Use PostgreSQL for original bytes and metadata. Release identity is company + fiscal year-end + reporting period (Q1/Q2/Q3/full year) + material category, not URL. Original-byte identity is distinct from the existing normalized Document content hash.

## Checklist

- [ ] Store distinct original bytes immutably and associate acquisition URL/time, issuer, and release identity when known.
- [ ] Two successful downloads of identical bytes keep one stored original and both acquisition records. Retrying persistence for the same acquisition does not invent a second acquisition.
- [ ] Different bytes at one URL preserve both originals; the same identified release at different URLs remains one logical release.
- [ ] Ambiguous identity stays pending confirmation without an automatic merge or fabricated metadata.
- [ ] Enforce the initial 20 MiB (20,971,520-byte) original limit. A rejected or failed acquisition creates failure state, not a successful original/observation; earlier data remains intact.
- [ ] Extraction failure does not roll back an already acquired original. No automatic deletion reclaims storage.
- [ ] Existing feed Documents/Observations remain valid without historical originals. Concurrent/retried writes preserve the deduplication and provenance invariants.

## Dependencies

None after the agreed planning contract. Blocks [#71](P3-collection.md) and [#72](P4-extraction.md).

## Notes

Follow repository TDD instructions; test identity collisions, repeated acquisition, failed writes, and boundary sizes using deterministic fixtures. Schema/module names and the migration approach belong to implementation review. See [ADR 0001](../../adr/0001-preserve-original-material-for-reprocessing.md) and [ADR 0002](../../adr/0002-store-pilot-originals-in-postgresql.md). Related: #45 and #50; analytical claims are not prerequisites.

<details>
<summary>日本語</summary>

# 不変の決算原本と取得履歴を保存する

GitHub issue: [#70](https://github.com/9renpoto/lens/issues/70)

## 目的

本文抽出とは独立して公式PDFのバイト列を保持し、短信の識別情報と取得元情報を再試行やDB復元後も維持する。

## 詳細

原本のバイト列とメタデータをPostgreSQLへ保存する。短信の同一性はURLではなく、企業＋決算期末＋対象期間（第1〜第3四半期・通期）＋資料種類で決める。原本バイト列の同一性は、既存Documentの正規化本文ハッシュとは区別する。

## チェックリスト

- [ ] 異なる原本バイト列を不変に保存し、取得元URL・取得日時・企業・判明している短信識別情報を関連付ける。
- [ ] 同一バイト列を2回取得した場合は原本を1件保持し、取得記録を2件残す。同じ取得の保存処理を再試行しても、架空の2回目の取得を作らない。
- [ ] 同一URLで異なるバイト列を取得した場合は両方を保持する。同じと識別できる短信は、URLが異なっても一つの論理的な短信として扱う。
- [ ] 識別が曖昧な資料は確認待ちとし、自動統合やメタデータの捏造を行わない。
- [ ] 原本の初期上限20 MiB（20,971,520バイト）を適用する。拒否・取得失敗は失敗状態を作り、成功した原本・Observationを作らず、既存データを維持する。
- [ ] 抽出失敗で取得済み原本を巻き戻さない。容量確保のための自動削除を行わない。
- [ ] 過去原本のない既存フィードのDocument・Observationを有効なまま維持する。同時書込み・再試行でも重複排除と取得履歴の不変条件を守る。

## 依存関係

合意した計画上の契約の後には前提issueなし。[#71](P3-collection.md)・[#72](P4-extraction.md)の前提。

## 補足

リポジトリのTDD指示に従い、識別の衝突・再取得・書込み失敗・サイズ境界を固定データで検証する。スキーマ・モジュール名・移行方式は実装レビューで決める。[ADR 0001](../../adr/0001-preserve-original-material-for-reprocessing.md)・[ADR 0002](../../adr/0002-store-pilot-originals-in-postgresql.md)を参照。関連：#45・#50。分析上の主張は前提としない。

</details>
