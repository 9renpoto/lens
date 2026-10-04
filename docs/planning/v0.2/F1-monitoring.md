# Define saved-search monitoring after the preservation pilot

GitHub issue: [#75](https://github.com/9renpoto/lens/issues/75)

## Objective

Define the next increment that detects newly published information matching saved searches, using the preserved and searchable earnings foundation.

## Details

This is a follow-up design issue, outside v0.2. The agreed meaning is new-publication monitoring, not financial comparison or automatic interpretation of corrections. Do not silently turn query-filter issue #51 into a monitoring implementation.

## Checklist

- [ ] Define saved-search ownership and lifecycle within the single-user product.
- [ ] Decide the initial baseline: existing matching material versus publications first encountered after activation.
- [ ] Distinguish publisher publication time from first acquisition, and define late arrivals, missed polling windows, and unknown publication dates.
- [ ] Define matching identity and deduplication across URLs, original versions, re-extraction, and overlapping searches.
- [ ] Decide result delivery, acknowledgement/replay behavior, and any latency target; do not assume external notifications are authorized.
- [ ] Decide how corrections and changed search conditions affect monitoring, with explicit exclusions.
- [ ] Produce reviewed acceptance scenarios and separately scoped implementation issues.

## Dependencies

Delivery follows [#68: the v0.2 pilot](P0-release-tracker.md). This issue is unmilestoned and is not a prerequisite for closing v0.2.

## Notes

Reference: [release plan](../../next-minor-plan.md). Related: #51 adds filters but does not define saved searches or delivery. Keep decisions in English with collapsed Japanese translations.

<details>
<summary>日本語</summary>

# 保存基盤の後に保存検索による監視を定義する

GitHub issue: [#75](https://github.com/9renpoto/lens/issues/75)

## 目的

保存・検索可能な決算基盤を使い、保存検索に一致する情報の新規公開を検出する次の段階を定義する。

## 詳細

v0.2の対象外に置く、後続の設計issue。合意した意味は新規公開の監視であり、業績比較や訂正の自動解釈ではない。検索絞り込みの#51を、暗黙に監視機能の実装へ拡張しない。

## チェックリスト

- [ ] 単一ユーザー向け製品における保存検索の所有・作成から終了までの扱いを定義する。
- [ ] 有効化時に存在する一致資料と、有効化後に初めて見つかった公開情報の初期基準を決める。
- [ ] 発行元の公開日時と初回取得日時を区別し、遅れて発見した資料・収集できなかった期間・公開日不明の扱いを定める。
- [ ] URL・原本の版・本文再生成・検索条件の重複をまたぐ、一致情報の同一性と重複排除を定義する。
- [ ] 結果の届け方・確認済み状態・再配信・必要なら遅延目標を決める。外部通知の許可を前提にしない。
- [ ] 訂正や検索条件の変更が監視に与える影響と、対象外の範囲を決める。
- [ ] レビュー済みの受入シナリオと、範囲を分けた実装issueを作る。

## 依存関係

提供は[#68：v0.2パイロット](P0-release-tracker.md)の後。このissueはマイルストーン未設定とし、v0.2完了の前提にしない。

## 補足

[リリース計画](../../next-minor-plan.md)を参照。関連：#51は絞り込みを追加するが、保存検索や結果配信は定義しない。決定は英語本文と折りたたみ内の日本語訳で記録する。

</details>
