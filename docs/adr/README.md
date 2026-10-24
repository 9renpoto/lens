# Architecture decision records

Keep agreed architectural decisions and their rationale in `docs/adr/`. Track implementation tasks, priorities, dependencies and progress in GitHub issues. An accepted ADR records agreement; it does not establish implemented behavior or completed verification. Use diagrams when they clarify responsibilities or information flow.

Creating standalone planning documents, roadmaps, and execution plans is discouraged. Define scoped work in GitHub issues, record and agree on relevant design decisions in ADRs, and then begin implementation. Reference existing accepted decisions where applicable. See [ADR 0011](0011-plan-work-through-issues-and-adrs.md).

GitHub issues are authoritative for release boundaries, tasks, dependencies, completion evidence and historical context. ADRs describe only active decisions and rationale in the present tense. Before deleting obsolete documents, preserve useful history in issues and repair incoming links. Keep implemented procedures in maintained guides; do not retain superseded ADRs, delivery chronology or an archive of obsolete designs in the repository.

Write English as the primary text and matching Japanese in a closed-by-default details block. Keep stable ADR numbers. Update active records to express the agreed design, and keep the change history in issues. Acceptance records agreement, not implementation completion.

<details>
<summary>日本語</summary>

# アーキテクチャ決定記録

合意した設計判断と理由は`docs/adr/`に残す。実装タスク・優先順位・依存関係・進捗はGitHub Issueで管理する。承認済みADRは合意を記録するものであり、実装や検証の完了を示さない。責務や情報の流れが明確になる場合は図を使う。

独立した計画文書・ロードマップ・実行計画の作成は非推奨とする。範囲を定めたGitHub Issueを作成し、必要な設計判断をADRへ記録・合意してから実装を始める。既存の承認済み判断が該当する場合は参照する。[ADR 0011](0011-plan-work-through-issues-and-adrs.md)を参照する。

リリース境界・タスク・依存関係・完了証跡・過去の経緯はGitHub Issueを正とする。ADRは現在有効な判断と理由だけを現在形で記録する。古い文書を削除する前に、必要な歴史をIssueへ残して参照リンクを直す。実装済みの手順は維持するガイドに置き、置換済みADR・実装経緯・古い設計のarchiveはリポジトリに残さない。

英語を本文とし、対応する日本語訳は初期状態で閉じたdetailsブロックに記載する。ADR番号は維持する。有効な記録を合意した設計へ更新し、変更の経緯はIssueに残す。承認済みは合意を示し、実装完了を意味しない。

</details>
