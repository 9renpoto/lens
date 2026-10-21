# Lens

![coverage](https://9renpoto.github.io/lens/coverage.svg)

A self-hosted, single-user Personal Web Observatory.

Lens collects feeds and operator-selected earnings PDFs, preserves provenance,
and provides a JSON API for searching retained information and retrieving
original PDFs. It runs as one Elixir/OTP application with Phoenix, PostgreSQL,
and RustFS for newly collected earnings PDFs.

<details>
<summary>日本語</summary>

セルフホストで使う、個人向けのWeb観測基盤。

Lensはフィードと運用者が選んだ決算PDFを収集し、出典を保持する。
保存情報の検索と原本PDFの取得をJSON APIから利用できる。
Elixir/OTP・Phoenix・PostgreSQLを使用し、新たに収集する決算PDFはRustFSに保存する。

</details>

## Table of Contents

- [Install](#install)
- [Usage](#usage)
- [Documentation](#documentation)
- [API](#api)
- [Maintainers](#maintainers)
- [Contributing](#contributing)
- [License](#license)

<details>
<summary>日本語</summary>

目次：

- [導入](#install)
- [利用方法](#usage)
- [文書](#documentation)
- [API](#api)
- [メンテナー](#maintainers)
- [貢献](#contributing)
- [ライセンス](#license)

</details>

## Install

### Dependencies

Requires Elixir 1.18 / Erlang-OTP 27 and PostgreSQL 18. From a checkout:

```sh
mix setup
```

See [development setup](docs/development.md) for prerequisites and local
configuration, or [runtime contract](docs/deployment.md) for container configuration and commands.

<details>
<summary>日本語</summary>

Elixir 1.18 / Erlang-OTP 27とPostgreSQL 18が必要。
チェックアウトしたリポジトリで`mix setup`を実行する。
前提ソフトウェアとローカル設定は[開発手順](docs/development.md)、
コンテナの設定とコマンドは[実行契約](docs/deployment.md)を参照する。

</details>

## Usage

Start the local API and check readiness:

```sh
mix phx.server
```

```sh
curl --fail http://127.0.0.1:4000/api/ready
curl --get http://127.0.0.1:4000/api/search --data-urlencode 'q=example'
```

Register feeds using the [source operations guide](docs/operations.md#configure-and-inspect-sources).
For earnings PDFs, follow the [bounded collection and original-comparison guide](docs/reference/earnings-value-validation.md).
Keep the unauthenticated API behind a private access boundary; report
vulnerabilities according to the [security policy](SECURITY.md).

### CLI

```sh
mix lens.ingest SOURCE_ID
mix lens.earnings.extract --original ORIGINAL_ID
mix lens.search.rebuild
```

Use an existing source or original ID. See [ingestion](docs/ingestion.md),
[PDF extraction](docs/earnings-extraction.md), and [search](docs/search.md)
for command behavior and limits.

<details>
<summary>日本語</summary>

`mix phx.server`でローカルAPIを起動し、`GET /api/ready`で接続可能か確認する。
`GET /api/search`の`q`に検索語を指定する。
フィード登録は[取得先の運用手順](docs/operations.md#configure-and-inspect-sources)、
決算PDFは[上限付き収集・原本照合手順](docs/reference/earnings-value-validation.md)を参照する。
認証を持たないAPIは非公開のアクセス境界内で使い、脆弱性は[セキュリティ方針](SECURITY.md)に従って報告する。

CLIは既存の取得先ID・原本IDを指定して使う。
`mix lens.ingest SOURCE_ID`はフィードを取得し、
`mix lens.earnings.extract --original ORIGINAL_ID`は保持したPDFを抽出し、
`mix lens.search.rebuild`は検索用データを再構築する。
挙動と上限は[取り込み](docs/ingestion.md)・[PDF抽出](docs/earnings-extraction.md)・
[検索](docs/search.md)を参照する。

</details>

## Documentation

See the [documentation index](docs/README.md) for operational guides,
product background, development direction, and architecture decisions.
Shared terminology is defined in the [domain glossary](CONTEXT.md) and the
[preservation glossary](GLOSSARY.md).

<details>
<summary>日本語</summary>

操作手順、プロダクトの背景、開発の方向性、設計判断は[文書索引](docs/README.md)から参照する。
共通の用語は[ドメイン用語集](CONTEXT.md)と[保持・復旧の用語集](GLOSSARY.md)に定義する。

</details>

## API

The generated [API reference](docs/api.md) describes the HTTP contract.

<details>
<summary>日本語</summary>

HTTP契約は生成した[API参照資料](docs/api.md)に記載する。

</details>

## Maintainers

[@9renpoto](https://github.com/9renpoto)

## Contributing

Questions and bug reports belong in [GitHub issues](https://github.com/9renpoto/lens/issues).
Pull requests are welcome. Follow [AGENTS.md](AGENTS.md) and the
[development guide](docs/development.md): use regression tests for behavior
changes, and write documentation and GitHub content in English with matching
Japanese in closed details blocks.

<details>
<summary>日本語</summary>

質問と不具合は[GitHub Issue](https://github.com/9renpoto/lens/issues)へ報告する。
Pull Requestも受け付ける。[AGENTS.md](AGENTS.md)と[開発手順](docs/development.md)に従い、
挙動変更には回帰テストを用意する。文書とGitHubの内容は英語を本文とし、
対応する日本語訳を閉じたdetailsブロックに記載する。

</details>

## License

[MIT](LICENSE) © 2026 9renpoto. This license covers Lens code and documentation.
Collected third-party materials remain subject to their copyright holders'
terms. Review publisher conditions before acquisition and preserve required
copyright notices; see the [earnings validation guide](docs/reference/earnings-value-validation.md).

<details>
<summary>日本語</summary>

[MIT](LICENSE) © 2026 9renpoto。Lensのコードと文書に適用する。
収集した第三者の資料には各著作権者の利用条件が適用される。
取得前に発行元の条件を確認し、必要な著作権表示を保持する。
[決算検証手順](docs/reference/earnings-value-validation.md)を参照する。

</details>
