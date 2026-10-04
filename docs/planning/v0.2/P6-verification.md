# Verify earnings collection, reprocessing, and database recovery

GitHub issue: [#74](https://github.com/9renpoto/lens/issues/74)

## Objective

Demonstrate that the pilot preserves usable originals through collection failures, application restart, and database backup/restore.

## Details

Use deterministic local fixtures for automated checks and separately record the three-company source verification from #69. Test the observable behavior of the complete path rather than relying only on per-module tests.

## Checklist

- [ ] Exercise discovery → acquisition → retained bytes → extraction → Japanese search → original retrieval for each company's representative identity/layout.
- [ ] Cover identical reacquisition, changed bytes at the same URL, changed URL for one identity, ambiguous identity, and a later regular release.
- [ ] Inject HTTP failure, over-20-MiB input, interrupted acquisition, and extraction failure; confirm prior data remains and failure/status endpoints are useful.
- [ ] Confirm one search result per release and stale-text indication; retry extraction successfully without a publisher fetch and without creating acquisition history.
- [ ] Restart the application and demonstrate preservation of original bytes, acquisition history, and processing state.
- [ ] Back up PostgreSQL, restore into a separate clean test database, compare raw-original digests and metadata, then regenerate text and search with publisher network access disabled.
- [ ] Record commands, application revision, dataset size, environment, and results. Update operation/recovery instructions and generated API documentation where applicable, with aligned English/Japanese planning guidance.

## Dependencies

Blocked by [#71](P3-collection.md), [#72](P4-extraction.md), and [#73](P5-api-cli.md).

## Notes

The release tracker cannot claim all three sources operational while #69 leaves an acquisition route unresolved. Live endpoints are not required for routine CI. Follow repository TDD and required checks; do not claim a scale/latency guarantee from this small corpus. Related: #55's existing feed/provenance/CJK soak remains separate.

<details>
<summary>日本語</summary>

# 決算収集・再処理・DB復元を検証する

GitHub issue: [#74](https://github.com/9renpoto/lens/issues/74)

## 目的

収集失敗・アプリ再起動・DBバックアップと復元を経ても、パイロットが利用可能な原本を維持することを実証する。

## 詳細

自動検証には決定的なローカルの固定データを使い、#69による3社の取得元検証を別に記録する。モジュール単位のテストだけに頼らず、一連の流れで外から確認できる挙動を検証する。

## チェックリスト

- [ ] 各社の代表的な識別情報・レイアウトで、発見→取得→原本保存→抽出→日本語検索→原本取得を通す。
- [ ] 同一内容の再取得、同じURLのバイト列変更、同じ短信のURL変更、識別確認待ち、後続の通常短信を検証する。
- [ ] HTTP失敗・20 MiB超の入力・取得中断・抽出失敗を注入し、既存データの維持と失敗・状態APIの有用性を確認する。
- [ ] 短信ごとに検索結果1件となり、旧版本文であることを表示する。発行元から再取得せず、取得履歴を増やさずに本文抽出を再試行して成功させる。
- [ ] アプリを再起動し、原本バイト列・取得履歴・処理状態が維持されることを示す。
- [ ] PostgreSQLをバックアップし、別の空のテストDBへ復元する。原本のダイジェストとメタデータを比較し、発行元への通信を無効にした状態で本文再生成と検索を行う。
- [ ] コマンド・アプリのリビジョン・データ量・環境・結果を記録する。運用・復元手順と必要な生成API文書を更新し、計画上の説明は日英で揃える。

## 依存関係

[#71](P3-collection.md)・[#72](P4-extraction.md)・[#73](P5-api-cli.md)の完了が必要。

## 補足

#69で取得経路が未解決のまま、親issueで3社すべての運用完了を宣言しない。通常のCIで実サイトを必須にしない。リポジトリのTDDと所定の検証に従い、小さな資料群から規模・応答時間の保証を主張しない。関連：#55の既存フィード・出典・CJK検索の継続検証は別に維持する。

</details>
