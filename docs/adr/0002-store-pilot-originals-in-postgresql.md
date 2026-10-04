---
status: accepted
---

# Store pilot originals in PostgreSQL

For the three-company earnings pilot, store original PDF bytes in PostgreSQL
alongside their metadata and acquisition records. This increases database size
but keeps originals and provenance within one backup and restore boundary,
avoiding a separate persistent file volume or object-storage service for the
initial small corpus.

## Consequences

- Enforce an initial limit of 20 MiB (20,971,520 bytes) per original. Record
  oversized downloads and acquisition errors as retryable failures; keep
  previously retained originals and do not automatically delete them for space.
- Verify raw-byte integrity and text regeneration after database restore.
- Keep original bytes out of ordinary search/list responses.
- Revisit this storage choice when corpus size or backup cost justifies it.

This accepted storage choice is implemented on `main` as of `5bdd33b`. Backup
and restore evidence is still tracked by [#74](https://github.com/9renpoto/lens/issues/74).

<details>
<summary>日本語</summary>

# パイロットの原本をPostgreSQLに保存する

3社を対象とする決算情報パイロットでは、原本PDFのバイト列をメタデータ・取得記録とともにPostgreSQLへ保存する。DB容量は増えるが、原本と出典情報を一緒にバックアップ・復元でき、初期の少量データのために永続ファイルボリュームやオブジェクトストレージを追加せずに済む。

## 影響

- 原本1件の初期上限を20 MiB（20,971,520バイト）とする。上限超過・取得エラーは再試行可能な失敗として記録し、保存済みの原本を維持する。容量確保のための自動削除は行わない。
- DB復元後に、原本のバイト列の整合性と本文の再生成を検証する。
- 通常の検索・一覧レスポンスには原本のバイト列を含めない。
- データ量やバックアップの負担が増えた段階で、保存先を再検討する。

この保存先の選択は合意済みで、`main`の`5bdd33b`時点で実装済み。バックアップと復元の証跡は[#74](https://github.com/9renpoto/lens/issues/74)で引き続き確認する。

</details>
