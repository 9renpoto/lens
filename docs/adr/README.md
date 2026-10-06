# Architecture decision records

Keep agreed architectural decisions and their rationale in `docs/adr/`. Track implementation tasks, priorities, dependencies and progress in GitHub issues. An accepted ADR records agreement; it does not establish implemented behavior or completed verification. Use diagrams when they clarify responsibilities or information flow.

Planning documents are deprecated. Do not add new planning documents or make ADRs depend on temporary planning files. Existing `docs/planning/` material is transitional and is scheduled for removal before the v0.2 tag is created. Preserve necessary decisions in ADRs, operational or compatibility contracts in maintained documentation, and implementation work in GitHub issues before removing the temporary files. ADRs remain after that cleanup.

Before tagging v0.2, ensure temporary planning files and their incoming links have been removed after relocating required content. Do not reintroduce duplicate issue-body copies after cleanup. Existing task summaries are transitional; GitHub issues are authoritative for current implementation work. ADR 0007 uses those issues directly.

Write English as the primary text and matching Japanese in a closed-by-default details block. Keep stable ADR numbers; extend an accepted record when clarifying the same decision, and record a replacement explicitly when the decision changes.

<details>
<summary>日本語</summary>

# アーキテクチャ決定記録

合意した設計判断と理由は`docs/adr/`に残す。実装タスク・優先順位・依存関係・進捗はGitHub Issueで管理する。承認済みADRは合意を記録するものであり、実装や検証の完了を示さない。責務や情報の流れが明確になる場合は図を使う。

Planning文書の利用は非推奨とする。新しいPlanning文書を追加せず、ADRを一時的なPlanningファイルに依存させない。既存の`docs/planning/`は移行中の資料として扱い、v0.2タグを作成する前に削除する。削除前に、必要な判断はADRへ、運用・互換契約は維持する文書へ、実装作業はGitHub Issueへ移す。この整理後もADRは保持する。

v0.2タグ作成前に、必要な内容を移したうえで、一時的なPlanningファイルと参照元リンクが削除されていることを確認する。整理後にIssue本文の重複コピーを再導入しない。既存のタスク要約は移行中の資料であり、現在の実装作業はGitHub Issueを正とする。ADR 0007はそのIssueを直接参照する。

英語を本文とし、対応する日本語訳は初期状態で閉じたdetailsブロックに記載する。ADR番号を維持し、同じ判断の明確化では既存の承認済み記録を拡張する。判断自体を変更する場合は置き換えを明示する。

</details>
