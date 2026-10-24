---
status: accepted
---

# Recreate disposable databases from the current schema

Use disposable development/test databases and recreate them from the current
schema definition when the schema changes. Keeping only the supported schema
avoids maintaining compatibility, incremental migration history, rollback and
data-transfer code for discarded designs.

Keep the current indexes and relational constraints. Preserve original
immutability, acquisition provenance and search structures. Initialize an empty database explicitly;
initialization must not silently drop or overwrite an existing schema. Provide
an explicit reset operation for disposable databases. Remove obsolete tables
and columns from the schema rather than retaining compatibility structures.
Do not provide an upgrade or data-copy path from older schemas.

Database recreation loses registrations, retained database records and their
relationships. Operators must recreate the configuration and data they need.
This development model does not provide continuity for retained records or
authorize deleting objects in an external RustFS bucket.

Defer backup/restore implementation while the data is explicitly disposable.
Before retaining non-disposable records or operating in production, agree and
verify preservation appropriate to that scope, including a coordinated
PostgreSQL/RustFS recovery point and reference/hash reconciliation. Database
recreation does not supply backup integrity or restore evidence.

<details>
<summary>日本語</summary>

# 破棄可能なDBを現行スキーマから再生成する

開発・テストでは破棄可能なDBを使い、スキーマ変更時は現在のスキーマ定義から
再生成する。サポート対象のスキーマだけを残すことで、破棄した設計のための互換性・
差分migration履歴・ロールバック・データ移行コードを維持しない。

現在のindex・外部キー・不変性／取得経緯の保護・検索構造は維持する。
空DBを明示的に初期化し、初期化によって既存スキーマを黙って削除・上書きしない。
破棄可能なDBには明示的なreset操作を用意する。互換構造を残さず、不要なテーブル・
カラムをスキーマから削除する。旧スキーマからの更新・データコピー経路は提供しない。

DB再生成では登録設定・保持したDB記録・その関連を失う。必要な設定とデータは
運用者が再作成する。この開発モデルは保持記録の継続性を提供せず、外部RustFSの
bucket内のオブジェクト削除を許可するものでもない。

データを明示的に破棄可能とする間は、バックアップ・復元の実装を延期する。
破棄できない記録の保持や本番運用を始める前に、PostgreSQL/RustFSを揃えた復旧時点と
参照・ハッシュの照合を含め、その範囲に適した保持を合意して検証する。
DB再生成はバックアップの整合性や復元の証跡を提供しない。

</details>
