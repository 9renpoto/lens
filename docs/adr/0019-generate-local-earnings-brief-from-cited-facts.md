---
status: accepted
---

# Generate a local earnings brief from one cited disclosure fact

Render a local earnings brief from one operator-prepared JSON record representing
a single resource movement selected from a retained disclosure
([ADR 0017](0017-build-earnings-search-from-feed-updates.md)). This record acts
as the explicit intermediate contract between future automatic evidence
extraction and downstream brief rendering or hypothesis generation.

## Intermediate input contract

The local command `mix lens.earnings.brief <input.json>` reads one JSON object
without starting the Lens application, collection, or PostgreSQL. Every field is
required and must be non-empty:

- `excerpt`: verbatim excerpt selected from a retained disclosure.
- `resource`: controlled enum (`people`, `capital`, or `equipment`).
- `activity`: business activity the resource moves toward or away from.
- `action`: free-text description of the resource movement; any direction enum
  is deferred until automatic extraction is designed against retained material.
- `status`: controlled enum (`actual` or `planned`).
- `source_locator`: single human-verifiable citation string; structured source
  provenance is deferred until HTML and PDF extraction locator rules settle.

Missing or blank fields, unexpected keys, unreadable files, and invalid enum
values fail visibly with actionable errors.

## Facts and hypothesis boundary

Code owns validation and display of disclosure facts (`## 開示ファクト`),
including the verbatim excerpt and `source_locator`, as short Markdown. A model
never rewrites or invents citations.

In the hypothesis layer (following the local-model execution boundary in
[ADR 0016](0016-evaluate-self-hosted-document-assessment-offline.md)), the
command sends only the validated record to an operator-configured Ollama model
(`LENS_OLLAMA_ENDPOINT`, `LENS_OLLAMA_MODEL`, optional `LENS_OLLAMA_THINK`).
Using structured JSON output in the input's language, the model proposes one
job-demand hypothesis (`## 仕事の需要仮説（推測）`), one primary-source check
(`## 一次情報での確認方法`), and an optional concrete next step
(`## 任意の次の一歩`). Passing `--facts-only` skips model invocation. When model
configuration or inference fails, the command still displays the validated facts
section alongside a visible failure notice and exits non-zero.

Repository examples stay wholly fictional; real disclosures, operational inputs,
and review outputs remain private and untracked. Automatic extraction,
period comparisons, recruitment ingestion, and publication remain separate
future decisions.

<details>
<summary>日本語</summary>

# 出典付き開示ファクト1件からローカル決算レポートを生成する

保存済み決算資料（[ADR 0017](0017-build-earnings-search-from-feed-updates.md)）から
担当者が手動で選んだ 1 件の資源の動きを JSON レコードとして受け取り、ローカル決算レポートを
表示する。このレコードを、将来の自動根拠抽出と下流のレポート表示・仮説生成の間をつなぐ
中間契約とする。

## 中間入力の契約

ローカルコマンド `mix lens.earnings.brief <input.json>` は、Lens アプリ本体・収集・
PostgreSQL を起動せずに単一の JSON オブジェクトを読み込む。すべての項目を必須かつ非空とする。

- `excerpt`: 保存済み開示から選んだ原文抜粋。
- `resource`: 固定候補（`people`・`capital`・`equipment`）。
- `activity`: 資源の投入先または引き揚げ元となる事業活動。
- `action`: 資源の動きを表す自由記述文字列。方向を示す固定候補の導入は、保存済み資料を
  確認して自動抽出を設計する段階で判断する。
- `status`: 固定候補（`actual`・`planned`）。
- `source_locator`: 人が一次資料へ辿れる 1 本の出典文字列。出典の構造化は、HTML・PDF の
  自動抽出における参照仕様が固まってから判断する。

必須項目の欠落・空文字、未定義キー、ファイル読込失敗、不正な候補値は、修正できるエラーで
明示的に失敗させる。

## ファクトと仮説の境界

開示ファクト・根拠文・出典（`## 開示ファクト`）の検証と短い Markdown 表示はコード側が担い、
モデルにファクトや出典を書き換えさせない。

仮説生成層では（[ADR 0016](0016-evaluate-self-hosted-document-assessment-offline.md) の
ローカルモデル実行境界に倣い）、検証済みレコードだけを運用者が設定した Ollama モデル
（`LENS_OLLAMA_ENDPOINT`・`LENS_OLLAMA_MODEL`・任意の `LENS_OLLAMA_THINK`）へ渡す。
入力と同じ言語の構造化 JSON 出力を受け、仕事の需要仮説 1 件（`## 仕事の需要仮説（推測）`）、
一次情報での確認方法 1 件（`## 一次情報での確認方法`）、具体的な接点がある場合の任意の一歩
（`## 任意の次の一歩`）を整形表示する。`--facts-only` 指定時はモデルを呼ばない。
モデル設定の不備や推論失敗時は、検証済みの開示ファクトと失敗理由を並べて表示し、非 0 で終了する。

リポジトリ内の例は完全な架空データとし、実資料・実運用の入力・レビュー結果は非公開かつ
Git 追跡対象外に置く。自動抽出、期間比較、求人収集、外部公開は後続の別判断とする。

</details>
