---
status: accepted
---

# Store earnings PDFs only in RustFS

Use RustFS as the sole storage backend for earnings PDF bytes. Keep document
identity, acquisition history, extraction results and search data in PostgreSQL.
One PDF backend keeps storage behavior small enough to inspect and verify.

Store the endpoint, bucket, object key and verification metadata directly on
`earnings_originals`, alongside its SHA-256 and byte size. Each original has one
immutable storage reference. Do not maintain separate physical-location or
active-read-selection tables, PostgreSQL PDF copies, backend switching or
data-copy tooling. A different storage requirement needs its own design when
it arises.

Use content-based immutable object keys and conditional creation. Keep identical
bytes once and retain changed bytes as separate originals. Verify exact size
and SHA-256 after writes and before returning retained bytes. Check the recorded
endpoint and bucket against the configured client; configuration changes must
not silently redirect an original read. Surface missing objects, configuration
mismatches and integrity failures instead of returning another original.

Follow [synchronous storage](0013-retire-interrupted-storage-recovery.md) for
acquisition completion and failure handling. Retrieve and verify the retained
original before creating an extraction attempt. Retrieval failure is a storage
error, not an extractor failure; extraction and original retrieval require no
publisher access.

The [disposable-data boundary](0010-defer-backups-for-disposable-development-data.md)
defines database recreation and preservation requirements. RustFS storage alone
does not establish coordinated PostgreSQL/RustFS backup or restore guarantees.

<details>
<summary>日本語</summary>

# 決算PDFをRustFSだけに保存する

決算PDFのバイト列はRustFSだけに保存する。資料の識別情報・取得履歴・抽出結果・
検索データはPostgreSQLに保持する。PDFの保存先を一つにし、挙動を把握して検証できる
規模に保つ。

endpoint・bucket・object key・検証情報を、SHA-256・サイズとともに
`earnings_originals`へ直接記録する。各原本は一つの不変の保存参照を持つ。
物理保存先や有効読取先の別テーブル、PostgreSQLのPDFコピー、バックエンド切替、
データコピーツールは維持しない。別の保存要件が生じた時点で、その設計を行う。

内容に基づく不変のobject keyと条件付き作成を使う。同じバイト列は一つだけ保存し、
変更されたバイト列は別の原本として残す。書込後と保存原本の読取結果を返す前に、
正確なサイズとSHA-256を検証する。記録済みendpoint・bucketと設定したクライアントを
照合し、設定変更で原本の読取先を黙って変えない。欠落・設定不一致・整合性エラーは
別の原本を返さず明示する。

取得完了と失敗処理は[同期保存](0013-retire-interrupted-storage-recovery.md)に従う。
抽出試行を作成する前に保存原本を取得・検証する。取得失敗は抽出器の失敗ではなく
保存のエラーとする。本文抽出と原本取得は公開元へのアクセスを必要としない。

DB再生成と保持要件は[破棄可能なデータの境界](0010-defer-backups-for-disposable-development-data.md)
で定める。RustFS保存だけではPostgreSQL/RustFSの協調バックアップ・復元の保証は成立しない。

</details>
