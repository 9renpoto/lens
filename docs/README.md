# Documentation

Use ADRs for decisions and their reasons, GitHub issues for current implementation work, and operational references for implemented behavior. Follow the [ADR maintenance policy](adr/README.md). Planning documents are deprecated and temporary planning material must be removed before the v0.2 tag. Historical execution plans, measurement reports and duplicate issue-body copies have been removed.

- Decisions: [original retention](adr/0004-retain-earnings-pdfs-for-reprocessing.md), [RustFS](adr/0005-store-pdfs-in-rustfs.md), [recovery](adr/0006-record-file-storage-work-before-writing.md), [registration API](adr/0007-register-pilot-sources-through-an-interface.md).
- Existing implementation decisions: [PDF runner](adr/0003-bound-pdf-runner-replacement.md), [Japanese search](adr/0008-use-postgresql-for-japanese-substring-search.md), [large text](adr/0009-preserve-complete-text-when-search-vectors-overflow.md). ADRs 0001–0002 are superseded history.
- Current implementation work: [release tracker #68](https://github.com/9renpoto/lens/issues/68), including ADR 0007 tasks #124–#131. Unfinished storage, interrupted-write recovery, migration and integration work is tracked in [#138](https://github.com/9renpoto/lens/issues/138); documentation consolidation is tracked in [#139](https://github.com/9renpoto/lens/issues/139). These follow-ups do not change the release scope.
- Operations: [deployment](deployment.md), [backup and recovery](operations.md), [ingestion](ingestion.md), [PDF extraction](earnings-extraction.md), [search](search.md).
- Reference: [API](api.md), [pipeline](reference/earnings-pipeline.md), [candidate collection](reference/earnings-collector.md), [HTTP transport](reference/earnings-http.md), [HTTP history](reference/earnings-http-history.md), [run budgets](reference/earnings-run-budget.md), [glossary](../CONTEXT.md).

The implementation currently stores PDF bytes in PostgreSQL. Source registration is implemented; its API contract is in the generated OpenAPI, and its decisions and migration/compatibility contract are in ADR 0007. RustFS remains an accepted direction awaiting implementation; its ADR is not a claim of operational availability. Local k3s Lens is the agreed deployment-verification environment.

<details>
<summary>日本語</summary>

# ドキュメント

判断と理由はADR、現在の実装作業はGitHub Issue、実装済みの挙動は操作・参照資料に記載する。[ADR管理方針](adr/README.md)に従う。Planning文書は非推奨とし、一時的な計画資料はv0.2タグ前に削除する。過去の実行プラン・測定報告・Issue本文の重複コピーは削除した。

- 判断：[原本保持](adr/0004-retain-earnings-pdfs-for-reprocessing.md)、[RustFS](adr/0005-store-pdfs-in-rustfs.md)、[復旧](adr/0006-record-file-storage-work-before-writing.md)、[登録API](adr/0007-register-pilot-sources-through-an-interface.md)。
- 既存実装の判断：[PDFランナー](adr/0003-bound-pdf-runner-replacement.md)、[日本語検索](adr/0008-use-postgresql-for-japanese-substring-search.md)、[大きな本文](adr/0009-preserve-complete-text-when-search-vectors-overflow.md)。ADR 0001〜0002は引継ぎ済みの履歴。
- 現在の実装作業：[リリース管理#68](https://github.com/9renpoto/lens/issues/68)。ADR 0007のタスク#124〜#131を含む。保存・中断書込の復旧・移行・接続の未完了作業は[#138](https://github.com/9renpoto/lens/issues/138)、文書の集約は[#139](https://github.com/9renpoto/lens/issues/139)で追跡する。これらの後続作業はリリース範囲を変更しない。
- 操作：[配置](deployment.md)、[バックアップ・復旧](operations.md)、[取り込み](ingestion.md)、[PDF抽出](earnings-extraction.md)、[検索](search.md)。
- 参照：[API](api.md)、[処理基盤](reference/earnings-pipeline.md)、[候補収集](reference/earnings-collector.md)、[HTTP取得](reference/earnings-http.md)、[HTTP履歴](reference/earnings-http-history.md)、[実行予算](reference/earnings-run-budget.md)、[用語集](../CONTEXT.md)。

現在の実装はPDFバイト列をPostgreSQLへ保存する。取得先登録は実装済みで、API契約は生成OpenAPI、判断と移行・互換性の契約はADR 0007に記載する。RustFSは合意した方針だが実装待ちであり、そのADRは利用可能という主張ではない。実環境の検証にはローカルk3s上のLensを使う。

</details>
