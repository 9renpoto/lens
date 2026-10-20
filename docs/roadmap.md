# Development roadmap

This document describes release boundaries and development direction. GitHub
issues are authoritative for task state, dependencies, and completion evidence.
Completed execution plans are removed after their lasting decisions and
operational instructions are recorded in maintained documents.

## v0.2: one-issuer earnings-search validation

[#68](https://github.com/9renpoto/lens/issues/68) defines the checkpoint:
one official source, bounded manual collection, extraction, identity
confirmation, representative Japanese search, exact-original comparison, and
oral review. Its children are #69–#73. Follow the
[validation procedure](reference/earnings-value-validation.md) and the release
issue for remaining review and documentation work.

The checkpoint uses disposable development/test data. Recurring earnings
collection, automatic latest-release selection, multiple-company operation,
search UI, and production backup/restore guarantees are outside its scope.
A mismatch or an unhelpful result is an observation for discussion rather than
an automatic release failure.

## v0.3: one RSS notification source

[#185](https://github.com/9renpoto/lens/issues/185) and
[#186](https://github.com/9renpoto/lens/issues/186) cover manual candidate
registration through an API, persistence with stable IDs, and one locally
served RSS feed. The checkpoint is that registered candidates can be detected
through RSS for notification. It does not require demonstrating eventual
discovery value, a search UI, subscriber read-state management, or a particular
notification client. Local operation starts without application authentication.

## Capability work without a release commitment

[#184](https://github.com/9renpoto/lens/issues/184) groups the operator-managed
assessment workflow from ADR 0007 (#124–#131).
[#138](https://github.com/9renpoto/lens/issues/138) tracks storage and recovery.
These capability parents do not make all their children release prerequisites.
Later release milestones are not assigned in this roadmap.

The [product-value explanation](explanation/product-value.md) describes the
longer-term discovery hypothesis. Architectural choices and their rationale
are recorded in [ADRs](adr/README.md); this roadmap does not claim that proposed
capabilities are implemented.

<details>
<summary>日本語</summary>

# 開発ロードマップ

この文書はリリース境界と開発の方向性を示す。タスク状態・依存関係・完了証跡は
GitHub Issueを正とする。完了した実行計画は、継続して必要な決定と操作手順を
維持する文書へ記録した後に削除する。

## v0.2：1社の決算検索検証

[#68](https://github.com/9renpoto/lens/issues/68)は公式取得先1件、上限付き手動収集、
抽出、識別確定、代表的日本語検索、正確な原本照合、口頭レビューを区切りとする。
子Issueは#69〜#73。[検証手順](reference/earnings-value-validation.md)を使い、
残るレビューと文書作業はリリースIssueを参照する。

明示的に破棄可能な開発・テストデータを使う。決算資料の定期収集、最新短信の自動選択、
複数社運用、検索UI、本番バックアップ／復元保証は対象外。
不一致や有用でない結果も議論する観測結果であり、自動的なリリース失敗とはしない。

## v0.3：RSS通知元1件

[#185](https://github.com/9renpoto/lens/issues/185)と
[#186](https://github.com/9renpoto/lens/issues/186)は、APIでの候補手動登録、
安定IDを持つ永続化、ローカルで配信する単一RSSを対象とする。
登録候補を通知の対象としてRSSで検出できることを区切りとする。
最終的な発見価値の実証、検索UI、購読側の既読管理、特定の通知クライアントは求めない。
ローカル運用はアプリの認証なしで始める。

## リリースを約束しない機能単位の作業

[#184](https://github.com/9renpoto/lens/issues/184)はADR 0007の運用者管理の判定フロー
（#124〜#131）、[#138](https://github.com/9renpoto/lens/issues/138)は保存・復旧をまとめる。
これらの親Issueの全子Issueをリリース前提とはしない。
このロードマップでは後続リリースのマイルストーンを割り当てない。

長期的な発見の価値仮説は[プロダクト価値の説明](explanation/product-value.md)、
設計の選択と理由は[ADR](adr/README.md)に記録する。
このロードマップは提案中の機能を実装済みとは扱わない。

</details>
