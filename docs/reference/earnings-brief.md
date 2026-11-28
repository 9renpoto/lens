# Local earnings brief

Render a short, readable brief from one operator-prepared disclosure record
without starting the Lens application, collection, or PostgreSQL.
See [ADR 0019](../adr/0019-generate-local-earnings-brief-from-cited-facts.md).

## Run

### Facts and local-model hypothesis

Configure an Ollama endpoint and model (such as `gpt-oss:20b`) in your shell:

```sh
LENS_OLLAMA_ENDPOINT=http://127.0.0.1:11434 \
LENS_OLLAMA_MODEL=gpt-oss:20b \
mix lens.earnings.brief test/fixtures/earnings/brief_example.json
```

Optional environment variables:

- `LENS_OLLAMA_THINK`: `true`, `false`, or a model-supported level such as `low`.
- `LENS_OLLAMA_TIMEOUT_MS`: per-request timeout in milliseconds (1–300000).

Code renders `## 開示ファクト` directly from the validated input record. Only the
validated facts and excerpt are sent to the configured local model, which drafts
one job-demand hypothesis (`## 仕事の需要仮説（推測）`), one primary-source
check (`## 一次情報での確認方法`), and an optional concrete next step
(`## 任意の次の一歩`). If model configuration is missing/invalid or inference
fails, the command prints the validated facts section together with a visible
failure notice under `## 仕事の需要仮説（推測）` and exits non-zero.

### Facts only (without a model)

```sh
mix lens.earnings.brief --facts-only test/fixtures/earnings/brief_example.json
```

## Input record contract

Provide one UTF-8 JSON object with exactly six required non-empty string fields:

| Field | Allowed value |
| --- | --- |
| `excerpt` | Verbatim excerpt selected from a retained disclosure |
| `resource` | `people`, `capital`, or `equipment` |
| `activity` | Business activity the resource moves toward or away from |
| `action` | Free-text description of the resource movement |
| `status` | `actual` or `planned` |
| `source_locator` | Human-verifiable citation to the source disclosure |

Keep real disclosure inputs and outputs private and untracked. Repository
fixtures and documentation examples must remain wholly fictional.

<details>
<summary>日本語</summary>

# ローカル決算レポート

Lens アプリ本体・収集・PostgreSQL を起動せずに、担当者が用意した 1 件の開示レコードから
短く読みやすいレポートを表示する。
[ADR 0019](../adr/0019-generate-local-earnings-brief-from-cited-facts.md) を参照する。

## 実行

### 開示ファクトとローカルモデルによる仮説生成

シェルで Ollama の接続先とモデル名（例: `gpt-oss:20b`）を設定して実行する。

```sh
LENS_OLLAMA_ENDPOINT=http://127.0.0.1:11434 \
LENS_OLLAMA_MODEL=gpt-oss:20b \
mix lens.earnings.brief test/fixtures/earnings/brief_example.json
```

任意の環境変数:

- `LENS_OLLAMA_THINK`: `true`・`false`、またはモデルが対応するレベル（例: `low`）。
- `LENS_OLLAMA_TIMEOUT_MS`: 1 リクエストあたりのタイムアウト（ミリ秒、1〜300000）。

`## 開示ファクト` は検証済みの入力レコードからコード側で直接表示する。モデルには
検証済みファクトと抜粋のみを渡し、仕事の需要仮説 1 件（`## 仕事の需要仮説（推測）`）、
一次情報での確認方法 1 件（`## 一次情報での確認方法`）、具体的な接点がある場合の
任意の一歩（`## 任意の次の一歩`）を生成する。モデル設定の不備や推論失敗時は、
検証済みの開示ファクトと失敗理由を並べて表示し、非 0 で終了する。

### ファクトのみ表示（モデルなし）

```sh
mix lens.earnings.brief --facts-only test/fixtures/earnings/brief_example.json
```

## 入力レコードの契約

次の 6 項目をすべて持つ UTF-8 の JSON オブジェクトを 1 件渡す。すべて非空文字列とする。

| 項目 | 許容する値 |
| --- | --- |
| `excerpt` | 保存済み開示から選んだ原文抜粋 |
| `resource` | `people`・`capital`・`equipment` のいずれか |
| `activity` | 資源の投入先または引き揚げ元となる事業活動 |
| `action` | 資源の動きを表す自由記述 |
| `status` | `actual` または `planned` |
| `source_locator` | 一次資料へ辿れる出典箇所 |

実資料の入力と出力は非公開かつ Git 追跡対象外に置く。リポジトリ内の fixture と
ドキュメント例には完全な架空データを使う。

</details>
