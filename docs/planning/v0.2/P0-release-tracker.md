# Deliver the v0.2 earnings collection and preservation pilot

GitHub issue: [#68](https://github.com/9renpoto/lens/issues/68)

## Objective

Deliver collection, original preservation, text regeneration, and search for the fixed three-company earnings pilot.

## Details

The fixed set is Advantest (6857), Fast Retailing (9983), and Tokyo Electron (8035), selected by Nikkei 225 index weights on 2026-09-14. Collect Japanese earnings-release PDFs from reviewed official IR routes: the latest reporting release when each source is initialized, then new listings, with daily and manual runs.

Preserve distinct originals in PostgreSQL with acquisition URL/time, deduplicate identical bytes, and retain acquisition history. The initial per-file limit is 20 MiB (20,971,520 bytes); failures never delete older originals. Identify releases by company, fiscal year-end, reporting period, and category; ambiguous identity remains pending confirmation.

Keep extraction outcomes separate from acquisition. Ordinary search uses the latest successfully extracted version per release, flags stale text when a newer version fails, and exposes past originals and failures through API/CLI.

## Checklist

- [ ] [#69: source catalog](P1-source-catalog.md) establishes all three routes and evaluation cases.
- [x] [#70: preservation](P2-preservation.md) enforces identity, immutable bytes, and acquisition history.
- [ ] [#71: collection](P3-collection.md) connects reviewed discovery and HTTP history to bounded daily/manual operation.
- [x] [#72: extraction](P4-extraction.md) supports offline regeneration and visible failures.
- [ ] [#73: API and CLI](P5-api-cli.md) exposes search, originals, history, and unresolved states.
- [ ] [#74: verification](P6-verification.md) records end-to-end and restore evidence.
- [ ] English documentation and collapsed Japanese translations match implemented behavior.

## Implementation status on latest base (`origin/main` at `5bdd33b`, 2026-10-04)

The base includes source-listing discovery, original preservation, extraction and search integration, and bounded HTTP/check-history primitives. The official source routes remain inactive pending their acquisition conditions. The HTTP primitives are not yet connected to an earnings collector that applies the reviewed route policy and runs daily/manual, so #71 remains incomplete at release level. Release detail/search endpoints and the extraction CLI exist, but original-byte/version retrieval, API/CLI access to unresolved and failed cases, and operator identity confirmation are not complete. Local system checks cover synthetic releases and offline extraction/search; restart and PostgreSQL backup/restore evidence remains outstanding. #69, #71, #73, and #74 remain incomplete.

## Dependencies

Completion requires #69–#74. [#75: saved-search monitoring](F1-monitoring.md) is outside v0.2.

## Notes

No dedicated new screen, OCR, financial-number modeling, bulk historical import, dynamic company selection, analytical verification, or RSSHub expansion is required. Existing issues #43, #44, #47, #48, #49, #50, #51, #53, #54, and #55 retain their scope outside this milestone.

Reference: [release plan](../../next-minor-plan.md), [preservation ADR](../../adr/0001-preserve-original-material-for-reprocessing.md), and [storage ADR](../../adr/0002-store-pilot-originals-in-postgresql.md). Implementation is separate from this planning task.

<details>
<summary>日本語</summary>

# v0.2の決算情報収集・保存パイロットを完成させる

GitHub issue: [#68](https://github.com/9renpoto/lens/issues/68)

## 目的

固定3社の決算情報について、収集・原本保存・本文再生成・検索を実現する。

## 詳細

対象は2026-09-14の日経平均構成比率で選定した、アドバンテスト（6857）・ファーストリテイリング（9983）・東京エレクトロン（8035）。検証した公式IR経路から日本語の決算短信PDFを取得する。各収集元の初期化時は最新の決算回、その後は新規掲載分を対象とし、日次・手動実行に対応する。

異なる原本を取得元URL・取得日時とともにPostgreSQLへ保存し、同一バイト列の重複を排除しながら取得履歴を残す。原本1件の初期上限は20 MiB（20,971,520バイト）とし、失敗時も過去の原本を削除しない。企業・決算期末・対象期間・資料種類で短信を識別し、曖昧な場合は確認待ちにする。

本文抽出と取得の結果を分離する。通常の検索では短信ごとに最新の抽出成功版を使い、新版の抽出失敗時は旧版本文であることを表示する。過去原本と失敗状態はAPI・CLIで確認できるようにする。

## チェックリスト

- [ ] [#69：取得元台帳](P1-source-catalog.md)で3社の経路と評価ケースを確立する。
- [x] [#70：原本保存](P2-preservation.md)で同一性・原本の不変性・取得履歴を保証する。
- [ ] [#71：収集](P3-collection.md)で検証済みの発見・HTTP履歴を、上限付きの日次・手動収集に接続する。
- [x] [#72：本文抽出](P4-extraction.md)で外部取得なしの再生成と失敗確認を可能にする。
- [ ] [#73：API・CLI](P5-api-cli.md)で検索・原本・履歴・未解決状態を参照可能にする。
- [ ] [#74：検証](P6-verification.md)で一連の動作と復元の証跡を残す。
- [ ] 英語ドキュメントと折りたたみ内の日本語訳を実装の挙動に揃える。

## 最新ベースブランチでの実装状況（`origin/main` `5bdd33b`、2026-10-04）

ベースブランチには、取得元一覧からの発見、原本保存、本文抽出・検索連携、上限付きHTTP取得・確認履歴の基盤が含まれる。公式取得経路は取得条件の確認待ちで、まだ無効。HTTP基盤は、検証済み経路の判定を適用して日次・手動実行する決算収集処理に未接続のため、リリース全体では#71を未完了とする。短信詳細・検索APIと抽出CLIはあるが、原本バイト列・版の取得、未解決・失敗状態のAPI・CLI参照、運用者による識別確定は未完了。ローカル固定データによるシステム確認では合成短信の抽出・検索を扱うが、アプリ再起動とPostgreSQLバックアップ・復元の証跡は未取得。#69・#71・#73・#74は未完了。

## 依存関係

完了には#69〜#74が必要。[#75：保存検索による監視](F1-monitoring.md)はv0.2に含めない。

## 補足

新しい専用画面、OCR、財務数値のモデル化、過去分の一括取込、対象企業の自動選定、分析の検証、RSSHubの拡張は対象外。既存の#43・#44・#47・#48・#49・#50・#51・#53・#54・#55は範囲を維持し、このマイルストーンの外に残す。

参照：[リリース計画](../../next-minor-plan.md)、[原本保存ADR](../../adr/0001-preserve-original-material-for-reprocessing.md)、[保存先ADR](../../adr/0002-store-pilot-originals-in-postgresql.md)。実装はこの計画作業とは別に行う。

</details>
