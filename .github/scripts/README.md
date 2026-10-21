# CI and release automation

`ci.yml` runs on pull requests, pushes to `main`, and version-tag pushes.
Other branch pushes do not start CI. New PR commits cancel older runs for that
PR; main and tag runs are not cancelled by PR concurrency.

The `checks` job runs typos, gitleaks, and the Node script tests before any
application tests. `ci-changes.js` reads GitHub's changed-file API to select jobs:

| Change | Application tests | Main image push | Workflow lint |
| --- | --- | --- | --- |
| Runtime inputs (`lib`, `config`, `priv`, `rel`, Mix files, Docker inputs) | Yes | Yes | No |
| Tests, native source, Elixir scripts, API docs, formatter/toolchain/coverage configuration | Yes | No | No |
| Workflow/action definitions and workflow lint configuration | No | No | Yes |
| `ci.yml` | Yes | Yes | Yes |
| `test-elixir.yml` | Yes | No | Yes |
| Change-selection or image-retention scripts | Yes | Yes | No |
| Other docs and automation scripts | No | No | No |
| Version tag or incomplete change detection | Yes | Yes | Yes |

The table describes changes in isolation; combined changes select the union of
jobs. Renames include both paths. At the API file limits (3,000 for PR files,
300 for push comparisons), or on API errors, all jobs are selected.
`ci.yml` calls the reusable `test-elixir.yml` workflow for Elixir setup,
PostgreSQL/RustFS services, native runner checks, formatting, compilation,
integration tests, Dialyzer, coverage generation, and API documentation artifacts.
Coverage reporting and publication stay in `ci.yml`.
`lint-actions.yml` is a reusable workflow containing actionlint and zizmor.
Tests wait for applicable workflow lint. `CI result` fails if a required job
fails or is unexpectedly skipped; it succeeds for intentionally skipped jobs.
Repository rules can require this stable check name.

Main image publication requires successful tests and an image-related change;
version tags retain the existing test-before-publication behavior. This does
not enforce test success before creating a release or tag. API documentation
is generated in the test job. Main Pages publication combines that artifact
with the coverage badge, without recompiling the application. The unused Dialyzer
cache-metadata lookup is omitted; this workflow does not restore or save PLTs.

`bump-schedule.yml` compares the latest stable release to the scheduled main
commit. `select-release-bump.js` collects the merged main PRs in that history,
deduplicates them, and reads category labels and exclusions from
`.github/release.yml`. Category titles define their version impact:

| Release category title | Increment |
| --- | --- |
| `:boom: Type: Breaking Change` | major |
| `:rocket: Type: Feature` | minor |
| Any other matching category, including `Other Changes` | patch |

The highest matching increment wins, even when a PR has several category labels.
Global and category-specific exclusions apply. No included PRs means no bump.
Missing semantic categories, missing stable releases, divergent history, and
commits without a merged-main PR association stop the scheduled job instead of
guessing. For a first release, use the manual `bump.yml` dispatch; it can use
`mix.exs` as the version baseline. YAML is read with Ruby's standard library on
`ubuntu-latest`; the selector and version increment need no npm packages or
SemVer container. The selected baseline and scheduled commit also bound the
release notes. Bump PRs remain drafts; a milestone need not already exist.

Run the automation tests with `node --test .github/scripts/*.test.js` and check
workflow definitions with `actionlint` and `zizmor .github/workflows`.

`select-release-bump.js` provides JSDoc types such as `SemverIncrement`,
`ReleaseConfig`, and `ReleaseGitHubClient`. Other files can reference them through
`import("./select-release-bump.js").ReleaseConfig`. With TypeScript available, run:

```sh
tsc --noEmit --strict --allowJs --checkJs --target ES2022 --module node16 --moduleResolution node16 --lib ES2022 .github/scripts/select-release-bump.js
```

<details>
<summary>日本語</summary>

# CIとリリースの自動化

`ci.yml` はPR、`main` へのpush、バージョンタグのpushで実行する。
他のブランチへのpushではCIを開始しない。PRに新しいコミットが追加されると、
同じPRの古い実行をキャンセルする。このPRの並行制御でmainやタグの実行はキャンセルしない。

`checks` ジョブでtypos、gitleaks、Nodeスクリプトのテストを実行してから、
アプリのテストへ進む。`ci-changes.js` はGitHubの変更ファイルAPIでジョブを選ぶ。

| 変更 | アプリのテスト | mainのイメージ公開 | Workflow lint |
| --- | --- | --- | --- |
| 実行時入力（`lib`、`config`、`priv`、`rel`、Mixファイル、Docker入力） | 実行 | 実行 | 省略 |
| テスト、ネイティブソース、Elixirスクリプト、API docs、formatter・toolchain・coverage設定 | 実行 | 省略 | 省略 |
| Workflow・Action定義とworkflow lint設定 | 省略 | 省略 | 実行 |
| `ci.yml` | 実行 | 実行 | 実行 |
| `test-elixir.yml` | 実行 | 省略 | 実行 |
| 変更検知・イメージ保持スクリプト | 実行 | 実行 | 省略 |
| その他のdocsと自動化スクリプト | 省略 | 省略 | 省略 |
| バージョンタグまたは変更検知が不完全な場合 | 実行 | 実行 | 実行 |

表は変更が単独の場合を示し、複数の変更では必要なジョブを合算する。
改名では変更前後のパスを対象とする。APIの件数上限（PRは3,000件、push比較は300件）
やAPIエラーの場合は、全ジョブを選択する。
`ci.yml` は再利用可能な `test-elixir.yml` を呼び出し、Elixirのセットアップ、
PostgreSQL・RustFSサービス、ネイティブrunner検査、format・compile、統合テスト、
Dialyzer、coverage生成、API docsのartifact生成を実行する。
coverageの報告と公開処理は `ci.yml` に置く。
`lint-actions.yml` はactionlintとzizmorを含む再利用可能なworkflowである。
テストは該当するworkflow lintの成功を待つ。`CI result` は必要なジョブの失敗や
意図しない省略で失敗し、意図した省略では成功する。
リポジトリのルールでは、この安定したチェック名を必須にできる。

mainのイメージ公開にはテスト成功とイメージ関連の変更を要求する。
バージョンタグは既存の公開前テストを維持する。
リリースやタグを作成する前のテスト成功を強制する仕組みは追加しない。
API docsはテストジョブで生成し、mainのPages公開ではそのartifactとcoverage badgeを
組み合わせて、アプリの再コンパイルを避ける。
未使用のDialyzerキャッシュのメタデータ照会は削除し、このworkflowではPLTを復元・保存しない。

`bump-schedule.yml` は最新の安定リリースとスケジュール実行のmainコミットを比較する。
`select-release-bump.js` はその履歴にあるマージ済みmainのPRを重複なく集め、
`.github/release.yml` のカテゴリラベルと除外設定を使う。
カテゴリのタイトルでバージョンへの影響を定める。

| リリースカテゴリのタイトル | 変更種別 |
| --- | --- |
| `:boom: Type: Breaking Change` | major |
| `:rocket: Type: Feature` | minor |
| `Other Changes` を含むその他の一致するカテゴリ | patch |

1つのPRに複数のカテゴリラベルがある場合も、最大の変更種別を採用する。
全体とカテゴリ固有の除外設定を適用し、対象PRがなければbumpを省略する。
判定用カテゴリ・安定リリースがない場合、履歴が分岐している場合、
コミットとマージ済みmainのPRとの関連がない場合は、推測せずスケジュールジョブを失敗させる。
初回リリースは `bump.yml` を手動実行し、`mix.exs` をバージョンの基準にできる。
YAMLは `ubuntu-latest` のRuby標準ライブラリで読み取り、
判定とバージョン更新にはnpmパッケージやSemVerコンテナを使わない。
リリースノートの範囲も、選択した基準タグとスケジュール実行のコミットに固定する。
bump PRはdraftのまま作成し、milestoneの事前作成は不要とする。

`node --test .github/scripts/*.test.js` で自動化のテストを実行し、
`actionlint` と `zizmor .github/workflows` でworkflow定義を確認する。

`select-release-bump.js` は `SemverIncrement`、`ReleaseConfig`、
`ReleaseGitHubClient` などのJSDocの型を提供する。他のファイルでは
`import("./select-release-bump.js").ReleaseConfig` の形式で参照できる。
TypeScriptを利用できる環境では、次のコマンドで検証する。

```sh
tsc --noEmit --strict --allowJs --checkJs --target ES2022 --module node16 --moduleResolution node16 --lib ES2022 .github/scripts/select-release-bump.js
```

</details>
