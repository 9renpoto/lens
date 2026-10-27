# Documentation

Use GitHub issues to define planned work and ADRs to record and agree on current design decisions before implementation. Creating standalone planning documents, roadmaps, and execution plans is discouraged. Keep implemented procedures in operational/reference guides. Follow [ADR 0011](adr/0011-plan-work-through-issues-and-adrs.md) and the [ADR maintenance policy](adr/README.md).

- Decisions: [original retention](adr/0004-retain-earnings-pdfs-for-reprocessing.md), [RustFS](adr/0005-store-pdfs-in-rustfs.md), [storage simplification](adr/0013-retire-interrupted-storage-recovery.md), [registration API](adr/0007-register-pilot-sources-through-an-interface.md), [retained earnings publication](adr/0014-publish-retained-earnings-through-rss.md).
- Existing implementation decisions: [PDF runner](adr/0003-bound-pdf-runner-replacement.md), [Japanese search](adr/0008-use-postgresql-for-japanese-substring-search.md), [large text](adr/0009-preserve-complete-text-when-search-vectors-overflow.md).
- Development: [setup and checks](development.md). Planned work and release boundaries: [GitHub issues](https://github.com/9renpoto/lens/issues).
- Operations: [container runtime contract](deployment.md), [release publication](releasing.md), [local application operations](operations.md), [ingestion](ingestion.md), [PDF extraction](earnings-extraction.md), [search](search.md).
- Product direction for review: [value and discovery](explanation/product-value.md), a maintained Why/What explanation distinct from the current release scope and implemented behavior.
- Reference: [API](api.md), [pipeline](reference/earnings-pipeline.md), [candidate collection](reference/earnings-collector.md), [earnings-search value-validation procedure](reference/earnings-value-validation.md), [HTTP transport](reference/earnings-http.md), [HTTP history](reference/earnings-http-history.md), [ingestion errors](reference/ingestion-errors.md), [earnings subscriptions](reference/earnings-subscriptions.md), [assessment records](reference/earnings-assessments.md), [assessment experiment](reference/earnings-assessment-experiment.md), [run budgets](reference/earnings-run-budget.md), [glossary](../CONTEXT.md).

The registered-source collector stores new PDF bytes in RustFS and retains identity, acquisition history, and extraction/search data in PostgreSQL. Source registration, bounded collection, extraction, and exact-original retrieval are implemented; use the references above for their contracts. Bounded validation uses disposable development/test data under [ADR 0010](adr/0010-defer-backups-for-disposable-development-data.md); it does not establish production backup/restore guarantees.

Storage uses synchronous verified saves under [ADR 0013](adr/0013-retire-interrupted-storage-recovery.md). Collection failures surface through collector errors and acquisition outcomes; the collector and HTTP references describe those contracts.

<details>
<summary>日本語</summary>

# ドキュメント

実装前にGitHub Issueで予定する作業を定義し、ADRへ現在の設計判断を記録して合意する。独立した計画文書・ロードマップ・実行計画の作成は非推奨とする。実装済み手順は操作・参照資料へ維持する。[ADR 0011](adr/0011-plan-work-through-issues-and-adrs.md)と[ADR管理方針](adr/README.md)に従う。

- 判断：[原本保持](adr/0004-retain-earnings-pdfs-for-reprocessing.md)、[RustFS](adr/0005-store-pdfs-in-rustfs.md)、[保存の簡素化](adr/0013-retire-interrupted-storage-recovery.md)、[登録API](adr/0007-register-pilot-sources-through-an-interface.md)、[保存済み決算情報の公開](adr/0014-publish-retained-earnings-through-rss.md)。
- 既存実装の判断：[PDFランナー](adr/0003-bound-pdf-runner-replacement.md)、[日本語検索](adr/0008-use-postgresql-for-japanese-substring-search.md)、[大きな本文](adr/0009-preserve-complete-text-when-search-vectors-overflow.md)。ADR 0001〜0002・0006は引継ぎ済みの履歴。
- 開発：[セットアップと検証](development.md)。予定する作業とリリース境界：[GitHub Issue](https://github.com/9renpoto/lens/issues)。
- 操作：[コンテナ実行契約](deployment.md)、[リリース公開](releasing.md)、[ローカルのアプリ操作](operations.md)、[取り込み](ingestion.md)、[PDF抽出](earnings-extraction.md)、[検索](search.md)。
- レビュー対象のプロダクト方向性：[価値と発見](explanation/product-value.md)。現行リリースの範囲や実装済みの挙動と区別し、Why/Whatを継続して説明する。
- 参照：[API](api.md)、[処理基盤](reference/earnings-pipeline.md)、[候補収集](reference/earnings-collector.md)、[決算検索の価値検証手順](reference/earnings-value-validation.md)、[HTTP取得](reference/earnings-http.md)、[HTTP履歴](reference/earnings-http-history.md)、[取り込みエラー](reference/ingestion-errors.md)、[決算購読](reference/earnings-subscriptions.md)、[判定記録](reference/earnings-assessments.md)、[判定比較実験](reference/earnings-assessment-experiment.md)、[実行予算](reference/earnings-run-budget.md)、[用語集](../CONTEXT.md)。

登録済み取得先のCollectorは新しいPDFバイト列をRustFSへ保存し、識別・取得履歴・抽出／検索データをPostgreSQLへ保持する。取得先登録・上限付き収集・抽出・正確な原本取得は実装済みであり、契約は上記の参照資料に記載する。上限付き検証は[ADR 0010](adr/0010-defer-backups-for-disposable-development-data.md)に従う破棄可能な開発・テストデータを使い、本番バックアップ／復元の保証を確立するものではない。

保存は[ADR 0013](adr/0013-retire-interrupted-storage-recovery.md)に従う同期的な検証済み保存を使う。収集の失敗はCollectorのエラーと取得結果で示し、Collector・HTTP参照資料にその契約を記載する。

</details>
