---
status: accepted
---

# Separate the README, roadmap, and execution plans

The README is the entry point for understanding, installing, and using Lens.
It follows [Standard Readme](https://github.com/RichardLitt/standard-readme/blob/main/spec.md)
as a structural reference, with English text and matching Japanese in closed
details blocks. Release scope and development direction live in
[the roadmap](../roadmap.md); GitHub issues hold task state and dependencies.
This keeps changing delivery plans out of the installation and usage guide.

Execution plans exist only while their work is active. Once execution is
complete, lasting decisions and their reasons are recorded in ADRs as current
rules, implemented procedures are maintained in operational/reference documents,
and the completed plan and its incoming links are removed. Git history retains
the old plan. Unfinished plans remain until their work is completed or explicitly
abandoned. An ADR records the chosen constraint and rationale in the present
tense; task checklists and delivery status remain in issues. Superseded decisions
retain their status and replacement links so historical constraints are not
mistaken for current rules.

<details>
<summary>日本語</summary>

# README・ロードマップ・実行計画の役割を分ける

READMEはLensの理解・導入・利用の入口とする。
[Standard Readme](https://github.com/RichardLitt/standard-readme/blob/main/spec.md)を
構成の参考にし、英語を本文、対応する日本語を閉じたdetailsブロックに記載する。
リリース範囲と開発の方向性は[ロードマップ](../roadmap.md)、タスク状態と依存関係は
GitHub Issueで管理する。変化する提供計画を導入・利用の案内から分離するためである。

実行計画は作業中だけ保持する。実行完了後は、継続して必要な決定と理由を現在の規則として
ADRに記録し、実装済み手順を操作・参照資料へ維持したうえで、完了したplanと参照リンクを削除する。
過去のplanはGit履歴に残る。未完了planは作業完了または明示的な取りやめまで保持する。
ADRは選択した制約と理由を現在形で記録し、タスクのチェックリストや進捗はIssueに置く。
引継ぎ済みの判断は状態と後継へのリンクを保持し、過去の制約を現在の規則と混同させない。

</details>
