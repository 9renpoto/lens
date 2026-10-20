# Documentation

Use ADRs for decisions and their reasons, GitHub issues for current implementation work, and operational references for implemented behavior. Follow the [ADR maintenance policy](adr/README.md). Planning documents are deprecated and temporary planning material must be removed before the v0.2 tag. Historical execution plans, measurement reports and duplicate issue-body copies have been removed.

- Decisions: [original retention](adr/0004-retain-earnings-pdfs-for-reprocessing.md), [RustFS](adr/0005-store-pdfs-in-rustfs.md), [recovery](adr/0006-record-file-storage-work-before-writing.md), [registration API](adr/0007-register-pilot-sources-through-an-interface.md).
- Existing implementation decisions: [PDF runner](adr/0003-bound-pdf-runner-replacement.md), [Japanese search](adr/0008-use-postgresql-for-japanese-substring-search.md), [large text](adr/0009-preserve-complete-text-when-search-vectors-overflow.md). ADRs 0001–0002 are superseded history.
- Release scope: [v0.2 tracker #68](https://github.com/9renpoto/lens/issues/68) covers one issuer's bounded acquisition, extraction, identity confirmation, Japanese search, exact-original comparison, and oral review. Its release children are #69–#73. Use the issue for current completion evidence and remaining release work.
- Capability work: [#184](https://github.com/9renpoto/lens/issues/184) groups ADR 0007 tasks #124–#131 independently of release milestones. Storage and recovery work is tracked in [#138](https://github.com/9renpoto/lens/issues/138). These capability trackers do not add prerequisites to v0.2. Documentation consolidation [#139](https://github.com/9renpoto/lens/issues/139) is complete.
- Operations: [deployment](deployment.md), [backup and recovery](operations.md), [ingestion](ingestion.md), [PDF extraction](earnings-extraction.md), [search](search.md).
- Product direction for review: [value and discovery](explanation/product-value.md), a maintained Why/What explanation distinct from the current release scope and implemented behavior.
- Reference: [API](api.md), [pipeline](reference/earnings-pipeline.md), [candidate collection](reference/earnings-collector.md), [earnings-search value-validation procedure](reference/earnings-value-validation.md), [HTTP transport](reference/earnings-http.md), [HTTP history](reference/earnings-http-history.md), [assessment records](reference/earnings-assessments.md), [run budgets](reference/earnings-run-budget.md), [glossary](../CONTEXT.md).

The registered-source collector stores new PDF bytes in RustFS and retains identity, acquisition history, storage-work records, and extraction/search data in PostgreSQL. Existing PostgreSQL-backed originals remain readable through their recorded storage location. Source registration, bounded collection, extraction, and exact-original retrieval are implemented; use the references above for their contracts. Local k3s Lens is the agreed deployment-verification environment. The v0.2 pilot uses disposable development/test data under [ADR 0010](adr/0010-defer-backups-for-disposable-development-data.md); it does not establish production backup/restore guarantees.

<details>
<summary>日本語</summary>

# ドキュメント

判断と理由はADR、現在の実装作業はGitHub Issue、実装済みの挙動は操作・参照資料に記載する。[ADR管理方針](adr/README.md)に従う。Planning文書は非推奨とし、一時的な計画資料はv0.2タグ前に削除する。過去の実行プラン・測定報告・Issue本文の重複コピーは削除した。

- 判断：[原本保持](adr/0004-retain-earnings-pdfs-for-reprocessing.md)、[RustFS](adr/0005-store-pdfs-in-rustfs.md)、[復旧](adr/0006-record-file-storage-work-before-writing.md)、[登録API](adr/0007-register-pilot-sources-through-an-interface.md)。
- 既存実装の判断：[PDFランナー](adr/0003-bound-pdf-runner-replacement.md)、[日本語検索](adr/0008-use-postgresql-for-japanese-substring-search.md)、[大きな本文](adr/0009-preserve-complete-text-when-search-vectors-overflow.md)。ADR 0001〜0002は引継ぎ済みの履歴。
- リリース範囲：[v0.2管理#68](https://github.com/9renpoto/lens/issues/68)は、1社の上限付き取得・抽出・識別確定・日本語検索・正確な原本照合・口頭レビューを対象とする。リリースの子Issueは#69〜#73。現在の完了証跡と残るリリース作業はIssueを参照する。
- 機能単位の作業：[#184](https://github.com/9renpoto/lens/issues/184)は、リリースマイルストーンとは独立してADR 0007の#124〜#131をまとめる。保存・復旧は[#138](https://github.com/9renpoto/lens/issues/138)で追跡する。これらの機能管理Issueはv0.2の前提を増やさない。文書集約の[#139](https://github.com/9renpoto/lens/issues/139)は完了済み。
- 操作：[配置](deployment.md)、[バックアップ・復旧](operations.md)、[取り込み](ingestion.md)、[PDF抽出](earnings-extraction.md)、[検索](search.md)。
- レビュー対象のプロダクト方向性：[価値と発見](explanation/product-value.md)。現行リリースの範囲や実装済みの挙動と区別し、Why/Whatを継続して説明する。
- 参照：[API](api.md)、[処理基盤](reference/earnings-pipeline.md)、[候補収集](reference/earnings-collector.md)、[決算検索の価値検証手順](reference/earnings-value-validation.md)、[HTTP取得](reference/earnings-http.md)、[HTTP履歴](reference/earnings-http-history.md)、[判定記録](reference/earnings-assessments.md)、[実行予算](reference/earnings-run-budget.md)、[用語集](../CONTEXT.md)。

登録済み取得先のCollectorは新しいPDFバイト列をRustFSへ保存し、識別・取得履歴・保存作業記録・抽出／検索データをPostgreSQLへ保持する。既存のPostgreSQL保存原本も、記録された保存場所を通じて読み取れる。取得先登録・上限付き収集・抽出・正確な原本取得は実装済みであり、契約は上記の参照資料に記載する。実環境の検証にはローカルk3s上のLensを使う。v0.2のパイロットは[ADR 0010](adr/0010-defer-backups-for-disposable-development-data.md)に従う破棄可能な開発・テストデータを使い、本番バックアップ／復元の保証を確立するものではない。

</details>
