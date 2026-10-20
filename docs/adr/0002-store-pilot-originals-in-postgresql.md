---
status: superseded
---

# Store pilot originals in PostgreSQL

Historical decision: store PDF bytes with their acquisition records in PostgreSQL to keep a small initial corpus within one backup and restore boundary. This reduced the initial operational work but increased database size.

Superseded by [ADR 0005](0005-store-pdfs-in-rustfs.md). The registered-source collector now stores new PDFs in RustFS; existing PostgreSQL-backed originals remain readable through their recorded storage location. See the [collector reference](../reference/earnings-collector.md) for implemented behavior and [#138](https://github.com/9renpoto/lens/issues/138) for storage/recovery work. This historical decision does not require copying existing originals between backends.

<details>
<summary>日本語</summary>

# パイロットの原本をPostgreSQLに保存する

過去の判断：小規模な初期データを一組でバックアップ・復元できるよう、PDFのバイト列と取得記録をPostgreSQLへ保存する。初期の運用作業を減らせる一方、DB容量が増える。

[ADR 0005](0005-store-pdfs-in-rustfs.md)へ引き継いだ。登録済み取得先のCollectorは現在、新しいPDFをRustFSへ保存する。既存のPostgreSQL保存原本も、記録された保存場所を通じて読み取れる。実装済みの挙動は[Collector参照資料](../reference/earnings-collector.md)、保存・復旧の作業は[#138](https://github.com/9renpoto/lens/issues/138)を参照する。この過去の判断は、既存原本をバックエンド間でコピーすることを要求しない。

</details>
