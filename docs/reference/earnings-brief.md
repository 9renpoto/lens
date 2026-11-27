# Local earnings brief

Render a short, readable brief from one operator-prepared disclosure record
without starting the Lens application, collection, PostgreSQL, or a local model.
See [ADR 0019](../adr/0019-generate-local-earnings-brief-from-cited-facts.md).

## Run

From the repository root with dependencies installed, run the fictional example:

```sh
mix lens.earnings.brief test/fixtures/earnings/brief_example.json
```

The command validates the input JSON object and prints the `## 開示ファクト`
section containing the supplied resource movement, source citation, and verbatim
excerpt. Missing or blank fields, unexpected keys, invalid JSON, and invalid
`resource` or `status` values fail with an actionable error.

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

Lens アプリ本体・収集・PostgreSQL・ローカルモデルを起動せずに、担当者が用意した
1 件の開示レコードから短く読みやすいレポートを表示する。
[ADR 0019](../adr/0019-generate-local-earnings-brief-from-cited-facts.md) を参照する。

## 実行

依存関係を導入したリポジトリのルートから、架空データ例で実行する。

```sh
mix lens.earnings.brief test/fixtures/earnings/brief_example.json
```

コマンドは入力 JSON オブジェクトを検証し、資源の動き・出典・原文抜粋を含む
`## 開示ファクト` セクションを表示する。必須項目の欠落や空文字、未定義キー、
不正な JSON、不正な `resource`・`status` 値は修正可能なエラーで失敗する。

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
