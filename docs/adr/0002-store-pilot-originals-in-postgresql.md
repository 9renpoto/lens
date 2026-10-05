---
status: superseded
---

# Store pilot originals in PostgreSQL

Historical decision: store PDF bytes with their acquisition records in PostgreSQL to keep a small initial corpus within one backup and restore boundary. This reduced the initial operational work but increased database size.

Superseded by [ADR 0005](0005-store-pdfs-in-rustfs.md). The existing implementation still retains bytes in PostgreSQL; the RustFS integration and migration are planned in [tasks B–D](../tasks/v0.2.md). Changing this ADR does not migrate data.

<details>
<summary>日本語</summary>

# パイロットの原本をPostgreSQLに保存する

過去の判断：小規模な初期データを一組でバックアップ・復元できるよう、PDFのバイト列と取得記録をPostgreSQLへ保存する。初期の運用作業を減らせる一方、DB容量が増える。

[ADR 0005](0005-store-pdfs-in-rustfs.md)へ引き継いだ。既存実装は現在もバイト列をPostgreSQLに保存しており、RustFS接続と移行は[タスクB〜D](../tasks/v0.2.md)に記載する。ADRの変更だけでデータが移行されるわけではない。

</details>
