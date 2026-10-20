# Architecture decision records

Keep agreed architectural decisions and their rationale in `docs/adr/`. Track implementation tasks, priorities, dependencies and progress in GitHub issues. An accepted ADR records agreement; it does not establish implemented behavior or completed verification. Use diagrams when they clarify responsibilities or information flow.

Planning documents are deprecated. Do not add new planning documents or make ADRs depend on temporary planning files. The temporary v0.2 task summary has been removed after moving implementation tracking to GitHub issues. Necessary decisions remain in ADRs and operational or compatibility contracts in maintained documentation.

Before tagging v0.2, check for other temporary planning files and incoming links. Preserve any necessary content in its authoritative location before removal. Do not reintroduce duplicate issue-body copies. GitHub issues are authoritative for current implementation work: [#68](https://github.com/9renpoto/lens/issues/68) defines the v0.2 release boundary, [#184](https://github.com/9renpoto/lens/issues/184) groups ADR 0007 tasks independently of milestones, and [#138](https://github.com/9renpoto/lens/issues/138) tracks storage/recovery work. Documentation consolidation [#139](https://github.com/9renpoto/lens/issues/139) is complete.

Write English as the primary text and matching Japanese in a closed-by-default details block. Keep stable ADR numbers; extend an accepted record when clarifying the same decision, and record a replacement explicitly when the decision changes.

<details>
<summary>日本語</summary>

# アーキテクチャ決定記録

合意した設計判断と理由は`docs/adr/`に残す。実装タスク・優先順位・依存関係・進捗はGitHub Issueで管理する。承認済みADRは合意を記録するものであり、実装や検証の完了を示さない。責務や情報の流れが明確になる場合は図を使う。

Planning文書の利用は非推奨とする。新しいPlanning文書を追加せず、ADRを一時的なPlanningファイルに依存させない。一時的なv0.2タスク要約は、実装の追跡をGitHub Issueへ移した後に削除した。必要な判断はADR、運用・互換契約は維持する文書に残す。

v0.2タグ作成前に、ほかの一時的なPlanningファイルと参照リンクを確認する。削除前に、必要な内容を正となる管理先へ保持する。Issue本文の重複コピーを再導入しない。現在の実装作業はGitHub Issueを正とする。[#68](https://github.com/9renpoto/lens/issues/68)はv0.2のリリース境界、[#184](https://github.com/9renpoto/lens/issues/184)はマイルストーンと独立したADR 0007のタスク群、[#138](https://github.com/9renpoto/lens/issues/138)は保存・復旧作業を管理する。文書集約の[#139](https://github.com/9renpoto/lens/issues/139)は完了済み。

英語を本文とし、対応する日本語訳は初期状態で閉じたdetailsブロックに記載する。ADR番号を維持し、同じ判断の明確化では既存の承認済み記録を拡張する。判断自体を変更する場合は置き換えを明示する。

</details>
