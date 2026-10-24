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

ADRs describe only active decisions and rationale in the present tense; they do
not duplicate task checklists, delivery status or historical implementation
details. Keep history and superseded decisions in GitHub issues. Before removing
obsolete repository content, preserve useful historical context in issues and
repair incoming links. Do not keep superseded ADRs or repository archives solely
to explain past designs; retain stable numbers for the active ADRs. Implemented
procedures and contracts belong in maintained operational/reference documents.
Move active plans to issues and agreed decisions to ADRs rather than maintaining
a parallel planning system.

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

ADRは現在有効な判断と理由だけを現在形で記録し、タスクのチェックリスト・進捗・
過去の実装詳細を重複させない。歴史と置換済みの判断はGitHub Issueに残す。
古い内容をリポジトリから削除する前に、必要な経緯をIssueへ残し、参照リンクを直す。
過去の設計を説明するためだけの置換済みADRやリポジトリ内のarchiveは維持しない。
有効なADRの番号は維持する。実装済みの手順・契約は維持する操作・参照文書に置く。
作業中のplanはIssue、合意した判断はADRへ移し、別の計画管理を維持しない。

</details>
