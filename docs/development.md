# Development

Lens uses Elixir 1.18 / Erlang-OTP 27 and PostgreSQL 18. On macOS, install and
start PostgreSQL before creating the development database:

```sh
brew install postgresql@18
brew services start postgresql@18
mix setup
mix phx.server
```

`POSTGRES_HOST`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `PORT`,
and `POOL_SIZE` override local defaults. PostgreSQL minor images are pinned
in Compose and CI; a PostgreSQL major upgrade requires a compatibility review.
See the [runtime contract](deployment.md#earnings-pdf-storage) for RustFS configuration
when collecting earnings PDFs.

## Before implementation

Create a scoped GitHub issue, record and agree on the relevant design decisions
in ADRs, and then begin implementation. Reference existing accepted ADRs when
they already cover the work. Standalone planning documents and roadmaps are
discouraged; see [ADR 0011](adr/0011-plan-work-through-issues-and-adrs.md).

## Checks

Use TDD for behavior changes: reproduce a bug with a failing regression test,
implement the smallest fix, then run the relevant suite.

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test --warnings-as-errors
```

The native PDF runner requires Linux and Poppler. See the
[extraction checks](earnings-extraction.md) for the Linux validation environment;
macOS-only results do not verify the native runner.

## Git hooks

Local hooks are optional. CI runs the corresponding checks independently.
Install hk 2.7.1 and run:

```sh
hk install --mise
hk run pre-commit --all
```

Use `hk install` without mise. The project adds `actionlint`, `mix-format`,
and `retention-tests`; hooks require actionlint, Elixir/Erlang, and Node.js on
`PATH`. Repository documentation and GitHub content follow the bilingual
requirements in [AGENTS.md](../AGENTS.md).

<details>
<summary>日本語</summary>

# 開発

Elixir 1.18 / Erlang-OTP 27とPostgreSQL 18を使う。macOSではPostgreSQLを
インストール・起動してから開発用DBを作る。

```sh
brew install postgresql@18
brew services start postgresql@18
mix setup
mix phx.server
```

`POSTGRES_HOST`・`POSTGRES_USER`・`POSTGRES_PASSWORD`・`POSTGRES_DB`・`PORT`・
`POOL_SIZE`でローカルの既定値を変更できる。ComposeとCIのPostgreSQL minor imageは
固定し、major更新には互換性レビューが必要。
決算PDFを収集する場合のRustFS設定は[実行契約](deployment.md#earnings-pdf-storage)を参照する。

## 実装前

範囲を定めたGitHub Issueを作成し、必要な設計判断をADRに記録・合意してから実装を始める。
既存の承認済みADRが作業を扱っている場合は参照する。独立した計画文書やロードマップの
作成は非推奨とし、[ADR 0011](adr/0011-plan-work-through-issues-and-adrs.md)に従う。

## 検証

挙動変更はTDDで進める。不具合を回帰テストで再現して失敗を確認し、最小の修正後に
対象スイートを実行する。

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test --warnings-as-errors
```

ネイティブPDFランナーにはLinuxとPopplerが必要。
Linuxでの検証環境は[抽出の検証](earnings-extraction.md)を参照する。
macOS上の結果だけではネイティブランナーを検証したことにはならない。

## Gitフック

ローカルフックは任意。CIは対応する検証を独立して実行する。
hk 2.7.1をインストールして次を実行する。

```sh
hk install --mise
hk run pre-commit --all
```

miseを使わない場合は`hk install`を使う。プロジェクトは`actionlint`・`mix-format`・
`retention-tests`を追加する。フックには`PATH`上のactionlint・Elixir/Erlang・Node.jsが必要。
リポジトリ文書とGitHubの内容は[AGENTS.md](../AGENTS.md)の日英併記要件に従う。

</details>
