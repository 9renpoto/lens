---
status: accepted
---

# Retire interrupted storage recovery

Use one synchronous, verified RustFS save for each accepted earnings PDF. The current bounded validation uses explicitly disposable development/test data under [ADR 0010](0010-defer-backups-for-disposable-development-data.md). Durable payload staging, leases, retry budgets, manual retry audits and a recovery poller add more complexity than that scope warrants. Retire them and their unfinished-work API rather than replace them with another queue. This supersedes [ADR 0006](0006-record-file-storage-work-before-writing.md) and the interrupted-write recovery requirements in [ADR 0005](0005-store-pdfs-in-rustfs.md). ADR 0010's preservation and production boundary remains in force.

## Save and failure contract

Validate acquisition provenance and the HTTP observation before object I/O. Save with conditional creation and verify exact size and SHA-256 using the existing RustFS client. Only then atomically commit the original identity, selected storage location, successful acquisition and immutable HTTP check. Preserve byte deduplication, changed-content versions, existing PostgreSQL copies, exact-original retrieval and the extraction/search boundary. Object I/O does not hold a database transaction open and does not initiate extraction.

A storage failure returns an explicit source-associated `storage_failed` error and stops the whole collection run with `:storage_failed`. Persist a failed acquisition with the actual download's identifier, issuer, final URL, timestamp and a bounded storage-failure reason, without creating an original or a successful PDF check. HTTP transport success alone is not acquisition success. If that failure history or the final success transaction cannot be committed, stop with `:persistence_failed` and surface the persistence error. Deadline exhaustion before the save stops with `:run_deadline_exceeded` and records the accepted download as a failed acquisition. Do not continue collecting after an accepted PDF cannot be saved.

There is no automatic or manual storage recovery, persisted pending payload, source exclusion carried between runs, or automatic publisher refetch. An operator may explicitly invoke a later bounded collection under the same publisher conditions; it is a new observation with a new acquisition identifier. On process death, in-memory bytes can be lost and no completed acquisition is claimed. If an object write succeeds but its database transaction fails or the process exits, the immutable object can remain unreferenced. Do not delete it or other retained originals as cleanup; a later identical conditional save may verify and reuse it. This deliberate loss of interrupted-work resumability is acceptable only within the disposable validation scope.

## Preservation and schema boundary

Retain immutable originals, completed acquisition/HTTP history, storage locations and extraction/search data. Preserve applied migrations and use forward migrations for schema changes. Before removing recovery tables, inspect unfinished work and retained payloads; refuse removal while unfinished work exists rather than discard it. Stop old application writers before the schema transition. Removing code does not authorize destructive operations on deployed retained materials. Future production preservation still requires a separately scoped design and evidence for coordinated PostgreSQL/RustFS backup and restore under ADRs 0005 and 0010; interrupted-write retirement supplies neither.

<details>
<summary>日本語</summary>

# 中断した保存の復旧を廃止する

受理した決算PDFごとに同期的なRustFS保存と検証を1回行う。現在の上限付き検証では[ADR 0010](0010-defer-backups-for-disposable-development-data.md)に従い、明示的に破棄可能な開発・テストデータを使う。ペイロードの永続的な準備、リース、再試行予算、手動再試行の監査、復旧ポーラーは、この範囲に見合わない複雑さを生む。別のキューに置き換えず、未完了作業APIとともに廃止する。[ADR 0006](0006-record-file-storage-work-before-writing.md)と[ADR 0005](0005-store-pdfs-in-rustfs.md)の中断書き込み復旧要件を置き換える。ADR 0010の保持・本番運用の境界は維持する。

## 保存と失敗の契約

オブジェクト通信前に取得経緯とHTTP観測情報を検証する。既存のRustFSクライアントで条件付き作成を行い、正確なサイズとSHA-256を検証する。その後にのみ、原本識別・選択済み保存先・成功取得・変更不可のHTTP確認を同時に確定する。バイト単位の重複排除、内容変更時の別版、既存のPostgreSQLコピー、正確な原本取得、抽出・検索の境界を維持する。オブジェクト通信中はDBトランザクションを開かず、抽出も開始しない。

保存失敗は取得先に紐づく明示的な`storage_failed`エラーを返し、収集実行全体を`:storage_failed`で停止する。実際のダウンロードの識別子・発行元・最終URL・時刻・長さを制限した保存失敗理由を失敗取得へ記録し、原本や成功PDF確認を作らない。HTTP取得成功だけでは取得成功と扱わない。失敗履歴や最終成功トランザクションをコミットできない場合は`:persistence_failed`で停止し、永続化エラーを示す。保存前の期限切れは`:run_deadline_exceeded`で停止し、受理済みダウンロードを失敗取得として記録する。受理済みPDFを保存できない状態で収集を続行しない。

自動・手動の保存復旧、永続化した待機ペイロード、実行をまたぐ取得先除外、公開元からの自動再取得は行わない。運用者は同じ公開元条件の下で後から上限付き収集を明示的に実行できるが、新しい取得識別子を持つ別の観測とする。プロセス終了ではメモリ上のバイト列を失う可能性があり、完了した取得とは扱わない。オブジェクト保存後にDBトランザクションが失敗するかプロセスが終了した場合、変更不可のオブジェクトが参照されず残る場合がある。整理のためにそれや他の保持原本を削除しない。後の同一内容の条件付き保存では検証して再利用できる。中断作業の再開を意図的に失うことは、破棄可能な検証の範囲だけで許容する。

## 保持とスキーマの境界

変更不可の原本、完了した取得・HTTP履歴、保存先、抽出・検索データを保持する。適用済みmigrationを保持し、スキーマ変更には前方migrationを使う。復旧テーブルを削除する前に未完了作業と保持ペイロードを確認し、未完了作業があれば破棄せず削除を拒否する。スキーマ移行前に旧アプリのwriterを停止する。コード削除は配備済みの保持資料への破壊的操作を許可しない。将来の本番保存ではADR 0005・0010に従うPostgreSQL/RustFSの協調バックアップ・復元の設計と証跡を別途定める必要があり、中断書き込み復旧の廃止はどちらも提供しない。

</details>
