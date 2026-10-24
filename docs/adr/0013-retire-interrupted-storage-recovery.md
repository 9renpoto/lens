---
status: accepted
---

# Save earnings PDFs synchronously

Use one synchronous, verified RustFS save for each accepted earnings PDF within the disposable development/test scope in [ADR 0010](0010-defer-backups-for-disposable-development-data.md). Keep the save and failure outcome explicit without durable payload staging, worker leases, retry budgets, retry audits or a recovery queue.

## Save and failure contract

Validate acquisition provenance and the HTTP observation before object I/O. Save with conditional creation and verify exact size and SHA-256 using the existing RustFS client. Only then atomically commit the original identity and its immutable RustFS reference, successful acquisition and immutable HTTP check. Preserve byte deduplication, changed-content versions, exact-original retrieval and the extraction/search boundary. Object I/O does not hold a database transaction open and does not initiate extraction.

A storage failure returns an explicit source-associated `storage_failed` error and stops the whole collection run with `:storage_failed`. Persist a failed acquisition with the actual download's identifier, issuer, final URL, timestamp and a bounded storage-failure reason, without creating an original or a successful PDF check. HTTP transport success alone is not acquisition success. If that failure history or the final success transaction cannot be committed, stop with `:persistence_failed` and surface the persistence error. Deadline exhaustion before the save stops with `:run_deadline_exceeded` and records the accepted download as a failed acquisition. Do not continue collecting after an accepted PDF cannot be saved.

There is no automatic or manual storage recovery, persisted pending payload, source exclusion carried between runs, or automatic publisher refetch. An operator may explicitly invoke a later bounded collection under the same publisher conditions; it is a new observation with a new acquisition identifier. On process death, in-memory bytes can be lost and no completed acquisition is claimed. If an object write succeeds but its database transaction fails or the process exits, the immutable object can remain unreferenced. Do not delete it or other retained originals as cleanup; a later identical conditional save may verify and reuse it. This deliberate loss of interrupted-work resumability is acceptable only within the disposable validation scope.

## Preservation and schema boundary

Keep original references directly on `earnings_originals` under [ADR 0005](0005-store-pdfs-in-rustfs.md). Define the supported schema without recovery-work, retry-audit, backend-control or read-selection tables. Recreate disposable databases from the current schema under ADR 0010; retain no old-schema transition or data-copy protocol. Preserve current integrity/provenance constraints and extraction/search behavior. Non-disposable records and production operation require separately agreed and verified preservation under ADR 0010.

<details>
<summary>日本語</summary>

# 決算PDFを同期的に保存する

受理した決算PDFごとに同期的なRustFS保存と検証を1回行う。[ADR 0010](0010-defer-backups-for-disposable-development-data.md)の破棄可能な開発・テスト範囲を対象とする。ペイロードの永続的な準備、ワーカーのリース、再試行予算、再試行監査、復旧キューを使わず、保存と失敗結果を明示する。

## 保存と失敗の契約

オブジェクト通信前に取得経緯とHTTP観測情報を検証する。既存のRustFSクライアントで条件付き作成を行い、正確なサイズとSHA-256を検証する。その後にのみ、原本識別と不変のRustFS参照・成功取得・変更不可のHTTP確認を同時に確定する。バイト単位の重複排除、内容変更時の別版、正確な原本取得、抽出・検索の境界を維持する。オブジェクト通信中はDBトランザクションを開かず、抽出も開始しない。

保存失敗は取得先に紐づく明示的な`storage_failed`エラーを返し、収集実行全体を`:storage_failed`で停止する。実際のダウンロードの識別子・発行元・最終URL・時刻・長さを制限した保存失敗理由を失敗取得へ記録し、原本や成功PDF確認を作らない。HTTP取得成功だけでは取得成功と扱わない。失敗履歴や最終成功トランザクションをコミットできない場合は`:persistence_failed`で停止し、永続化エラーを示す。保存前の期限切れは`:run_deadline_exceeded`で停止し、受理済みダウンロードを失敗取得として記録する。受理済みPDFを保存できない状態で収集を続行しない。

自動・手動の保存復旧、永続化した待機ペイロード、実行をまたぐ取得先除外、公開元からの自動再取得は行わない。運用者は同じ公開元条件の下で後から上限付き収集を明示的に実行できるが、新しい取得識別子を持つ別の観測とする。プロセス終了ではメモリ上のバイト列を失う可能性があり、完了した取得とは扱わない。オブジェクト保存後にDBトランザクションが失敗するかプロセスが終了した場合、変更不可のオブジェクトが参照されず残る場合がある。整理のためにそれや他の保持原本を削除しない。後の同一内容の条件付き保存では検証して再利用できる。中断作業の再開を意図的に失うことは、破棄可能な検証の範囲だけで許容する。

## 保持とスキーマの境界

[ADR 0005](0005-store-pdfs-in-rustfs.md)に従い、原本参照を`earnings_originals`へ直接記録する。現行スキーマに復旧作業・再試行監査・バックエンド制御・読取先選択のテーブルは置かない。ADR 0010に従い破棄可能なDBを現行スキーマから再生成し、旧スキーマの移行・データコピー手順を維持しない。現在の整合性・取得経緯の制約と抽出・検索の挙動を維持する。破棄できない記録や本番運用には、ADR 0010に従う保持の合意と検証が別途必要となる。

</details>
