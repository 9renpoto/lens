---
status: accepted
---

# Upgrade retained PostgreSQL databases with Ecto migrations

Use Phoenix's standard Ecto migrations in `priv/repo/migrations/` to evolve
the PostgreSQL schema. The first supported baseline is the schema at Lens
revision `f71d8b58da6bfff0969a4c3b380f83ffa650177b`. Maintain the migration
sequence from that schema forward. Match a legacy database to the baseline using
its schema fingerprint before adopting it into Ecto's migration history. This lets
existing installations retain their records and relationships while fresh
installations reach the same supported schema through the migration sequence.

`Lens.Release.prepare/0` applies pending compatible migrations before the new
application starts. Ecto records each migration version in `schema_migrations`
on success. Keep each automatic migration transactional and compatible with
the running previous release's database operations through the cutover.
Preparation stops on an unrecognized starting schema or a migration failure.

The initial adoption retains the listing sources, assessment history and
membership history, including their constraints. Keeping these tables makes
the adoption compatible with the previous release and preserves the records
until a separate change defines their disposition. The recreation policy in
[ADR 0010](0010-defer-backups-for-disposable-development-data.md) remains
available for explicitly disposable databases.

Decide the data preservation, cutover, and recovery procedure for each
destructive change when that change is proposed. Any destructive step that
requires operator intervention blocks preparation until the release-specific
procedure is complete.

<details>
<summary>日本語</summary>

# Ecto マイグレーションでデータを保持する PostgreSQL DB を更新する

PostgreSQL スキーマの更新には、`priv/repo/migrations/` に置く Phoenix 標準の
Ecto マイグレーションを使う。最初にサポートする起点は Lens のリビジョン
`f71d8b58da6bfff0969a4c3b380f83ffa650177b` のスキーマとし、そこから先の
マイグレーションを維持する。既存 DB を Ecto のマイグレーション履歴に引き継ぐ前に、
スキーマの fingerprint が対応する起点と一致することを確認する。既存環境ではデータと関連を保持し、新規環境では
マイグレーションを順に適用して同じサポート対象スキーマに到達する。

`Lens.Release.prepare/0` は新版のアプリケーションの起動前に、未適用の互換性のある
マイグレーションを適用する。Ecto は成功したマイグレーションのバージョンを
`schema_migrations` に記録する。自動マイグレーションはそれぞれトランザクション内で
実行し、切り替えまで稼働中の旧版の DB 操作と互換性を保つ。未知の移行元スキーマや
マイグレーションの失敗時は、準備を停止する。

最初の導入では、旧取得元・評価履歴・所属履歴のテーブルと制約を保持する。
これらを保持することで旧版と互換性を保ち、別の変更で取り扱いが決まるまで記録を維持する。
明示的に破棄可能な DB には、
[ADR 0010](0010-defer-backups-for-disposable-development-data.md) の再生成方針を引き続き適用できる。

破壊的変更ごとに、変更を提案する段階でデータの保全・切り替え・復旧の手順を決める。
運用者の作業を要する破壊的変更では、そのリリース固有の手順が完了するまで準備を停止する。

</details>
