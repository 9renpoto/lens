# Documentation

Use ADRs for decisions and their reasons, GitHub issues for current implementation work, and operational references for implemented behavior. Follow the [ADR maintenance policy](adr/README.md). Planning documents are deprecated and temporary planning material must be removed before the v0.2 tag. Historical execution plans, measurement reports and duplicate issue-body copies have been removed.

- Decisions: [original retention](adr/0004-retain-earnings-pdfs-for-reprocessing.md), [RustFS](adr/0005-store-pdfs-in-rustfs.md), [recovery](adr/0006-record-file-storage-work-before-writing.md), [registration API](adr/0007-register-pilot-sources-through-an-interface.md).
- Existing implementation decisions: [PDF runner](adr/0003-bound-pdf-runner-replacement.md), [Japanese search](adr/0008-use-postgresql-for-japanese-substring-search.md), [large text](adr/0009-preserve-complete-text-when-search-vectors-overflow.md). ADRs 0001–0002 are superseded history.
- Current implementation work: [release tracker #68](https://github.com/9renpoto/lens/issues/68), including ADR 0007 tasks #124–#131. The [earlier v0.2 task summary](tasks/v0.2.md) is transitional and may retain earlier scope; remove it and this link before the v0.2 tag after preserving required content.
- Operations: [deployment](deployment.md), [backup and recovery](operations.md), [ingestion](ingestion.md), [PDF extraction](earnings-extraction.md), [search](search.md).
- Reference: [API](api.md), [source registration](reference/earnings-sources.md), [pipeline](reference/earnings-pipeline.md), [HTTP transport](reference/earnings-http.md), [HTTP history](reference/earnings-http-history.md), [run budgets](reference/earnings-run-budget.md), [glossary](../CONTEXT.md).

The implementation currently stores PDF bytes in PostgreSQL. Source registration is implemented as documented in the reference. RustFS remains an accepted direction awaiting implementation; its ADR is not a claim of operational availability. Local k3s Lens is the agreed deployment-verification environment.

<details>
<summary>日本語</summary>

# ドキュメント

判断と理由はADR、現在の実装作業はGitHub Issue、実装済みの挙動は操作・参照資料に記載する。[ADR管理方針](adr/README.md)に従う。Planning文書は非推奨とし、一時的な計画資料はv0.2タグ前に削除する。過去の実行プラン・測定報告・Issue本文の重複コピーは削除した。

- 判断：[原本保持](adr/0004-retain-earnings-pdfs-for-reprocessing.md)、[RustFS](adr/0005-store-pdfs-in-rustfs.md)、[復旧](adr/0006-record-file-storage-work-before-writing.md)、[登録API](adr/0007-register-pilot-sources-through-an-interface.md)。
- 既存実装の判断：[PDFランナー](adr/0003-bound-pdf-runner-replacement.md)、[日本語検索](adr/0008-use-postgresql-for-japanese-substring-search.md)、[大きな本文](adr/0009-preserve-complete-text-when-search-vectors-overflow.md)。ADR 0001〜0002は引継ぎ済みの履歴。
- 現在の実装作業：[リリース管理#68](https://github.com/9renpoto/lens/issues/68)。ADR 0007のタスク#124〜#131を含む。[以前のv0.2タスク要約](tasks/v0.2.md)は移行中の資料であり、以前の範囲が残る場合がある。必要な内容を保持したうえで、v0.2タグ前に要約とこのリンクを削除する。
- 操作：[配置](deployment.md)、[バックアップ・復旧](operations.md)、[取り込み](ingestion.md)、[PDF抽出](earnings-extraction.md)、[検索](search.md)。
- 参照：[API](api.md)、[取得先登録](reference/earnings-sources.md)、[処理基盤](reference/earnings-pipeline.md)、[HTTP取得](reference/earnings-http.md)、[HTTP履歴](reference/earnings-http-history.md)、[実行予算](reference/earnings-run-budget.md)、[用語集](../CONTEXT.md)。

現在の実装はPDFバイト列をPostgreSQLへ保存する。取得先登録は参照資料に記載したとおり実装している。RustFSは合意した方針だが実装待ちであり、そのADRは利用可能という主張ではない。実環境の検証にはローカルk3s上のLensを使う。

</details>
