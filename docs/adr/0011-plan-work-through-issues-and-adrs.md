---
status: accepted
---

# Plan work through issues and ADRs before implementation

The README is the entry point for understanding, installing, and using Lens.
It follows [Standard Readme](https://github.com/RichardLitt/standard-readme/blob/main/spec.md)
as a structural reference, with English text and matching Japanese in closed
details blocks. Release scope, tasks, priorities, dependencies, and completion
evidence belong in GitHub issues.

Creating standalone planning documents, roadmaps, and execution plans is
discouraged. Before implementation, create a scoped issue and record and agree
on the relevant design decisions and rationale in ADRs. Reference an existing
accepted ADR when it already covers the decision rather than duplicating it.
Begin concrete development after the issue and applicable ADRs are in place.
Use actual sub-issues for independently reviewable implementation units.

ADRs describe current decisions in the present tense; they do not duplicate
task checklists or delivery status. Preserve superseded status and replacement
links when decisions change. Implemented procedures and contracts belong in
maintained operational/reference documents. Preserve lasting information from
existing plans in issues, ADRs, or those maintained guides before deleting
completed plans and their incoming links. Git history retains the removed
documents. Active plans are migrated to issues and ADRs, rather than extended
as a parallel planning system.

<details>
<summary>日本語</summary>

# IssueとADRで計画を定めてから実装する

READMEはLensの理解・導入・利用の入口とする。
[Standard Readme](https://github.com/RichardLitt/standard-readme/blob/main/spec.md)を
構成の参考にし、英語を本文、対応する日本語を閉じたdetailsブロックに記載する。
リリース範囲・タスク・優先順位・依存関係・完了証跡はGitHub Issueで管理する。

独立した計画文書・ロードマップ・実行計画の作成は非推奨とする。
実装前に範囲を定めたIssueを作成し、必要な設計判断と理由をADRへ記録して合意する。
既存の承認済みADRが判断を扱っている場合は、重複作成せず参照する。
Issueと該当するADRを用意した後に具体的な開発へ入る。
独立してレビュー可能な実装単位には、実際のサブIssueを使う。

ADRは現在の決定を現在形で記録し、タスクのチェックリストや進捗は重複させない。
判断が変わる場合は、引継ぎ済みの状態と後継へのリンクを保持する。
実装済みの手順・契約は維持する操作・参照文書に置く。
既存planの継続して必要な情報をIssue・ADR・維持するガイドへ残したうえで、
完了したplanと参照リンクを削除する。削除した文書はGit履歴に残る。
作業中のplanも並行した計画管理として拡張せず、IssueとADRへ移す。

</details>
