# Lens

![coverage](https://9renpoto.github.io/lens/coverage.svg)

Lens is a self-hosted, single-user Personal Web Observatory. It accumulates
useful information over time through a simple flow:

```text
Collect → Preserve → Search → Discover
```

Version 0.1 concentrates on the first three steps: scheduled RSS 2.0, Atom,
and RDF/RSS 1.0 feed collection (including output from an existing RSSHub
endpoint), normalization to canonical plain text, PostgreSQL persistence, and
PostgreSQL full-text search through a JSON API.

Lens is independent from the experimental offline-first RSS reader. A future
integration, if useful, will use a loose API boundary rather than a shared
application model.

## Status

The project is under active initial development. The v0.1 plan is tracked in
[GitHub milestone v0.1](https://github.com/9renpoto/lens/milestone/1).

It intentionally excludes LLMs, embeddings, vector databases, external search
engines, browser automation, custom web crawling, multi-tenancy, and
distributed deployment. Proactive discovery and recommendations are future
experiments, not v0.1 requirements.

## Architecture

Lens runs as one Elixir/OTP application with Phoenix as its JSON API layer and
PostgreSQL as its canonical datastore. The application owns source scheduling;
RSSHub is only a replaceable feed acquisition endpoint.

Canonical data consists of Sources, Documents, and Observations. PostgreSQL
full-text vectors are derived data and can be rebuilt without fetching sources
again. The initial content representation is meaningful plain text with
paragraph breaks, not raw HTML or a complex content AST.

## Development setup

Requirements: Elixir 1.18 / Erlang-OTP 27 and the latest supported PostgreSQL
major version (currently PostgreSQL 18). For the initial development
environment, install PostgreSQL with Homebrew:

```sh
brew install postgresql@18
brew services start postgresql@18
```

Lens supports the latest PostgreSQL major version supported by the PostgreSQL
project. Compose and CI use a fixed current minor release and digest for
reproducibility; Dependabot tracks Docker image updates. A new PostgreSQL major
version requires a separately reviewed compatibility update.

Install dependencies and create the development database:

```sh
mix setup
```

Local Git hooks are optional; CI runs `actionlint`,
`mix format --check-formatted`, and retention tests independently of hk.
To enable local hooks, install hk 2.7.1 and run
`hk install --mise` (or `hk install` without mise). Run them manually with
`hk run pre-commit --all`. The project configuration adds `actionlint`,
`mix-format`, and `retention-tests`, requiring `actionlint`, Elixir/Erlang,
and Node.js on `PATH`.

<details>
<summary>日本語</summary>

ローカルの Git フックは任意です。CI は hk に依存せず `actionlint`、
`mix format --check-formatted`、retention tests を実行します。
ローカルで有効にする場合は hk 2.7.1 をインストールし、
`hk install --mise`（mise を使わない場合は `hk install`）を実行してください。
`hk run pre-commit --all` で手動実行できます。プロジェクト設定には
`mix-format`、`retention-tests` を定義し、`PATH` 上に
Elixir/Erlang、Node.js が必要です。

</details>

Start the API:

```sh
mix phx.server
```

The initial health endpoint is available at `GET /api/health`.

Run the checks used by CI:

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test --warnings-as-errors
```

`POSTGRES_HOST`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `PORT`,
and `POOL_SIZE` can override local defaults.

## Operations

See [production deployment](docs/deployment.md) for the Kustomize deployment
contract and [single-node operations](docs/operations.md) for local Compose
operation, backups, restores, and failure recovery. See the [search
API](docs/search.md) for PostgreSQL FTS behavior, its current Japanese/CJK
limitations, and search data rebuilds.

The generated [API reference](docs/api.md) describes the HTTP JSON contract.

## Next release planning

The [documentation index](docs/README.md) links agreed ADRs and operational
references. See the [ADR maintenance policy](docs/adr/README.md) and
[domain glossary](CONTEXT.md) for decision management and shared terms.
Planning documents are deprecated. Required content from the temporary v0.2 task
summary is maintained in ADRs, operational references and GitHub issues; the
summary has been removed. Check for other temporary planning files and their
links before creating the v0.2 tag. Planned capabilities remain distinct from
existing implementation behavior.

Delivery is tracked in [milestone v0.2](https://github.com/9renpoto/lens/milestone/2)
and [issue #68](https://github.com/9renpoto/lens/issues/68).

<details>
<summary>日本語</summary>

## 次のリリースの計画

[文書一覧](docs/README.md)から合意したADR・操作資料を参照できます。判断の管理と共通の用語は[ADR管理方針](docs/adr/README.md)と[用語集](CONTEXT.md)を参照してください。Planning文書は非推奨とします。一時的なv0.2タスク要約の必要な内容はADR・操作資料・GitHub Issueへ移し、要約を削除しました。v0.2タグ作成前に、ほかの一時的なPlanningファイルと参照リンクがないか確認します。計画中の機能と既存実装の挙動を区別しています。

実施状況は[v0.2マイルストーン](https://github.com/9renpoto/lens/milestone/2)と[issue #68](https://github.com/9renpoto/lens/issues/68)で管理します。

</details>

## License

Lens is licensed under the [MIT License](LICENSE). This license applies to
Lens code and its accompanying documentation; it does not grant rights to
third-party materials collected by Lens. Those materials remain subject to
their copyright holders' terms. Keep publisher copyright notices and review
the applicable conditions before acquisition, even for personal,
non-commercial use without redistribution. See the
[earnings-search value-validation procedure](docs/reference/earnings-value-validation.md).

<details>
<summary>日本語</summary>

## ライセンス

Lens のコードと付属文書には [MIT License](LICENSE) が適用されます。
このライセンスは、Lens が取得する第三者の資料の利用権を付与するものではありません。
取得資料には各著作権者の利用条件が適用されます。個人・非商用・再配布なしの
利用でも、発行元の著作権表示を保持し、取得前に適用される条件を確認してください。
[決算検索の価値検証手順](docs/reference/earnings-value-validation.md)を参照してください。

</details>
