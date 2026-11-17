---
status: accepted
---

# Save earnings PDFs synchronously

Use one synchronous, verified RustFS save for each accepted earnings PDF within the disposable development/test scope in [ADR 0010](0010-defer-backups-for-disposable-development-data.md). Keep the save and failure outcome explicit without durable payload staging, worker leases, retry budgets, retry audits or a recovery queue.

## Save and failure contract

Validate acquisition provenance and the HTTP observation before object I/O. Save with conditional creation and verify exact size and SHA-256 using the existing RustFS client. Only then atomically commit the original identity and its immutable RustFS reference, successful acquisition and immutable HTTP check. Preserve byte deduplication, changed-content versions, exact-original retrieval and the extraction/search boundary. Object I/O does not hold a database transaction open and does not initiate extraction.

A storage failure is explicit and does not create a successful PDF check or
original. Failure to persist the outcome is also surfaced. HTTP transport
success alone is not acquisition success. There is no storage recovery queue,
persisted pending payload or automatic publisher refetch. A new observation is
not recovery of a previous download. A process death can lose in-memory bytes;
no completed acquisition is claimed. An object saved before a failed database
transaction may remain unreferenced. Do not delete it or other originals as
cleanup; a later identical conditional save may verify and reuse it. This loss
of interrupted-work resumability is acceptable only in the disposable scope.

## Preservation and schema boundary

Keep original references directly on `earnings_originals` under [ADR 0005](0005-store-pdfs-in-rustfs.md). Define the supported schema without recovery-work, retry-audit, backend-control or read-selection tables. Recreate disposable databases from the current schema under ADR 0010; retain no old-schema transition or data-copy protocol. Preserve current integrity/provenance constraints and extraction/search behavior. Non-disposable records and production operation require separately agreed and verified preservation under ADR 0010.

<details>
<summary>日本語</summary>

# 決算PDFを同期的に保存する

受理した決算PDFごとに同期的なRustFS保存と検証を1回行う。[ADR 0010](0010-defer-backups-for-disposable-development-data.md)の破棄可能な開発・テスト範囲を対象とする。ペイロードの永続的な準備、ワーカーのリース、再試行予算、再試行監査、復旧キューを使わず、保存と失敗結果を明示する。

## 保存と失敗の契約

オブジェクト通信前に取得経緯とHTTP観測情報を検証する。既存のRustFSクライアントで条件付き作成を行い、正確なサイズとSHA-256を検証する。その後にのみ、原本識別と不変のRustFS参照・成功取得・変更不可のHTTP確認を同時に確定する。バイト単位の重複排除、内容変更時の別版、正確な原本取得、抽出・検索の境界を維持する。オブジェクト通信中はDBトランザクションを開かず、抽出も開始しない。

保存失敗は明示し、成功PDF確認や原本を作らない。結果の永続化に失敗した場合も通知する。
HTTP取得成功だけでは取得成功と扱わない。保存復旧キュー、永続化した待機ペイロード、
公開元からの自動再取得は行わない。新たな観測は以前のダウンロードの復旧ではない。
プロセス終了でメモリ上のバイト列を失う場合、完了した取得とは扱わない。オブジェクト保存後に
DBトランザクションが失敗すると、変更不可のオブジェクトが参照されず残る場合がある。
整理のためにそれや他の原本を削除しない。後の同一内容の条件付き保存では検証して再利用できる。
中断作業の再開を意図的に失うことは、破棄可能な範囲だけで許容する。

## 保持とスキーマの境界

[ADR 0005](0005-store-pdfs-in-rustfs.md)に従い、原本参照を`earnings_originals`へ直接記録する。現行スキーマに復旧作業・再試行監査・バックエンド制御・読取先選択のテーブルは置かない。ADR 0010に従い破棄可能なDBを現行スキーマから再生成し、旧スキーマの移行・データコピー手順を維持しない。現在の整合性・取得経緯の制約と抽出・検索の挙動を維持する。破棄できない記録や本番運用には、ADR 0010に従う保持の合意と検証が別途必要となる。

</details>
