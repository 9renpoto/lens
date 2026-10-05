# Documentation

Use ADRs for decisions and their reasons, task documents for remaining work, and operational references for implemented behavior. Historical execution plans, measurement reports and duplicate issue-body copies have been removed.

- Decisions: [original retention](adr/0004-retain-earnings-pdfs-for-reprocessing.md), [RustFS](adr/0005-store-pdfs-in-rustfs.md), [recovery](adr/0006-record-file-storage-work-before-writing.md), [registration API](adr/0007-register-pilot-sources-through-an-interface.md).
- Existing implementation decisions: [PDF runner](adr/0003-bound-pdf-runner-replacement.md), [Japanese search](adr/0008-use-postgresql-for-japanese-substring-search.md), [large text](adr/0009-preserve-complete-text-when-search-vectors-overflow.md). ADRs 0001–0002 are superseded history.
- Remaining work and paused decisions: [v0.2 tasks](tasks/v0.2.md).
- Operations: [deployment](deployment.md), [backup and recovery](operations.md), [ingestion](ingestion.md), [PDF extraction](earnings-extraction.md), [search](search.md).
- Reference: [API](api.md), [pipeline](reference/earnings-pipeline.md), [HTTP transport](reference/earnings-http.md), [HTTP history](reference/earnings-http-history.md), [run budgets](reference/earnings-run-budget.md), [glossary](../CONTEXT.md).

The implementation currently stores PDF bytes in PostgreSQL. RustFS and source registration are accepted directions awaiting implementation; their ADRs are not claims of operational availability. Local k3s Lens is the agreed deployment-verification environment.

<details>
<summary>日本語</summary>

# ドキュメント

判断と理由はADR、残作業はタスク文書、実装済みの挙動は操作・参照資料に記載する。過去の実行プラン・測定報告・Issue本文の重複コピーは削除した。

- 判断：[原本保持](adr/0004-retain-earnings-pdfs-for-reprocessing.md)、[RustFS](adr/0005-store-pdfs-in-rustfs.md)、[復旧](adr/0006-record-file-storage-work-before-writing.md)、[登録API](adr/0007-register-pilot-sources-through-an-interface.md)。
- 既存実装の判断：[PDFランナー](adr/0003-bound-pdf-runner-replacement.md)、[日本語検索](adr/0008-use-postgresql-for-japanese-substring-search.md)、[大きな本文](adr/0009-preserve-complete-text-when-search-vectors-overflow.md)。ADR 0001〜0002は引継ぎ済みの履歴。
- 残作業・中断中の判断：[v0.2タスク](tasks/v0.2.md)。
- 操作：[配置](deployment.md)、[バックアップ・復旧](operations.md)、[取り込み](ingestion.md)、[PDF抽出](earnings-extraction.md)、[検索](search.md)。
- 参照：[API](api.md)、[処理基盤](reference/earnings-pipeline.md)、[HTTP取得](reference/earnings-http.md)、[HTTP履歴](reference/earnings-http-history.md)、[実行予算](reference/earnings-run-budget.md)、[用語集](../CONTEXT.md)。

現在の実装はPDFバイト列をPostgreSQLへ保存する。RustFSと取得先登録は合意した方針だが実装待ちであり、ADRは利用可能という主張ではない。実環境の検証にはローカルk3s上のLensを使う。

</details>
