# Architecture decision records

Keep agreed architectural decisions and their rationale in `docs/adr/`. Track implementation tasks, priorities, dependencies and progress in GitHub issues. An accepted ADR records agreement; it does not establish implemented behavior or completed verification. Use diagrams when they clarify responsibilities or information flow.

Creating standalone planning documents, roadmaps, and execution plans is discouraged. Define scoped work in GitHub issues, record and agree on relevant design decisions in ADRs, and then begin implementation. Reference existing accepted decisions where applicable. See [ADR 0011](0011-plan-work-through-issues-and-adrs.md).

GitHub issues are authoritative for release boundaries, tasks, dependencies, and completion evidence. ADRs describe current decisions and rationale in the present tense; do not duplicate issue checklists or delivery status. Move lasting information from existing plans into issues, ADRs, and maintained guides before deleting completed plans and their incoming links. Migrate active plans to issues and ADRs rather than extending a separate planning system.

Write English as the primary text and matching Japanese in a closed-by-default details block. Keep stable ADR numbers; extend an accepted record when clarifying the same decision, and record a replacement explicitly when the decision changes.

<details>
<summary>日本語</summary>

# アーキテクチャ決定記録

合意した設計判断と理由は`docs/adr/`に残す。実装タスク・優先順位・依存関係・進捗はGitHub Issueで管理する。承認済みADRは合意を記録するものであり、実装や検証の完了を示さない。責務や情報の流れが明確になる場合は図を使う。

独立した計画文書・ロードマップ・実行計画の作成は非推奨とする。範囲を定めたGitHub Issueを作成し、必要な設計判断をADRへ記録・合意してから実装を始める。既存の承認済み判断が該当する場合は参照する。[ADR 0011](0011-plan-work-through-issues-and-adrs.md)を参照する。

リリース境界・タスク・依存関係・完了証跡はGitHub Issueを正とする。ADRは現在の判断と理由を現在形で記録し、Issueのチェックリストや進捗を重複させない。既存planの継続して必要な情報をIssue・ADR・維持するガイドへ残してから、完了したplanと参照リンクを削除する。作業中のplanも独立した計画管理として拡張せず、IssueとADRへ移す。

英語を本文とし、対応する日本語訳は初期状態で閉じたdetailsブロックに記載する。ADR番号を維持し、同じ判断の明確化では既存の承認済み記録を拡張する。判断自体を変更する場合は置き換えを明示する。

</details>
