---
status: accepted
---

# Run workflow lint independently from application CI

Workflow lint uses GitHub Actions native `paths` filters on pull requests and
pushes to `main`. `lint-actions.yml` owns actionlint and zizmor execution for
workflow/action definitions and their lint configuration. This boundary follows
the explicit decision in #207 to keep workflow lint loosely coupled to application CI.

`ci-changes.js` selects only application tests and image publication. `ci.yml`
does not call, wait for, or aggregate workflow lint; lint failures are reported
by the independent workflow and do not prevent application CI from running.
Path-filtered lint jobs are not part of the stable `CI result` contract and
must not be required unconditionally, because GitHub can omit their runs.

<details>
<summary>日本語</summary>

# Workflow lintをアプリCIから独立させる

Workflow lintはPRと`main`へのpushでGitHub Actions標準の`paths`フィルターを使う。
`lint-actions.yml`がworkflow・action定義およびlint設定に対するactionlintと
zizmorの実行を担当する。この責務境界は、workflow lintとアプリCIを疎結合にする
#207の明示的な決定に従う。

`ci-changes.js`はアプリのテストとイメージ公開だけを選択する。`ci.yml`はworkflow
lintの呼出し・待機・結果集約を行わない。lint失敗は独立したworkflowで報告し、
アプリCIの実行を妨げない。パスでフィルターするlintジョブは安定した`CI result`の
契約に含めず、GitHubが実行を省略できるため無条件の必須チェックにしない。

</details>
