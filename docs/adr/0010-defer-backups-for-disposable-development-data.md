---
status: accepted
---

# Recreate disposable databases from the current schema

Use disposable development and test databases. Provide an explicit reset to
recreate them from the supported schema. Initialization requires an empty
database and retains the current relational constraints, immutability,
acquisition provenance and search structures. The upgrade policy for retained
databases is defined in [ADR 0018](0018-upgrade-postgresql-with-ecto-migrations.md).

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

開発・テストでは破棄可能な DB を使い、対応スキーマから再生成するための
明示的な reset 操作を用意する。初期化は空 DB を必要とし、現行の外部キーなどの制約、
不変性、取得経緯、検索構造を維持する。データを保持する DB の更新方針は
[ADR 0018](0018-upgrade-postgresql-with-ecto-migrations.md) に定める。

DB再生成では登録設定・保持したDB記録・その関連を失う。必要な設定とデータは
運用者が再作成する。この開発モデルは保持記録の継続性を提供せず、外部RustFSの
bucket内のオブジェクト削除を許可するものでもない。

データを明示的に破棄可能とする間は、バックアップ・復元の実装を延期する。
破棄できない記録の保持や本番運用を始める前に、PostgreSQL/RustFSを揃えた復旧時点と
参照・ハッシュの照合を含め、その範囲に適した保持を合意して検証する。
DB再生成はバックアップの整合性や復元の証跡を提供しない。

</details>
