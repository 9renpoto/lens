---
status: accepted
---

# Evaluate configurable document-assessment models outside the acquisition pipeline

Evaluate operator-selected models through a configurable Ollama endpoint using
labelled extracted text before using model judgments in the earnings workflow.
Model choice is an execution setting, not a project dependency. No particular
model, machine or existing personal installation is required. Strict
heading rules cover too few layouts to establish useful document coverage;
model output introduces semantic errors even when its JSON schema is valid.
Measure document-kind and reporting-identity matches, verbatim evidence,
failures and latency against explicit labels. Keep the strict presentation-heading
baseline distinct from the full existing assessors.

The experiment runs explicitly with no application startup or database access.
It sends bounded text to the configured Ollama endpoint and writes only an
evaluation report. Model results never create assessments, adopt releases or
change acquisition facts. Missing evidence, malformed output, context limits and
transport failures remain visible results, not successful classifications.
Record model digest, prompt/schema version and input hashes so runs can be
compared. Synthetic fixtures are public; operational inputs, endpoint addresses
and detailed reports stay private and untracked.

This preserves the acquisition/assessment/operator boundary in
[ADR 0007](0007-register-pilot-sources-through-an-interface.md). Production
integration requires a separate decision supported by evaluation evidence;
the experiment does not establish suitability for financial-number extraction.

<details>
<summary>日本語</summary>

# 選択可能な資料判定モデルを取得パイプライン外で評価する

決算資料の処理でモデル判断を利用する前に、設定可能なOllamaのエンドポイントを通じ、
運用者が任意に選択したモデルを正解ラベル付きの抽出本文で評価する。
モデル選択は実行時の設定であり、プロジェクトの依存関係にはしない。
特定のモデル・マシン・既存の個人環境を必須としない。厳密な見出し規則は対応する
レイアウトが少なく、有用な資料対応範囲を確立できない。一方、モデル出力は
JSON Schemaが正しくても意味を誤る。資料種類・対象期間等の識別の一致、原文にある
根拠、失敗、処理時間を明示した正解と比較する。厳密な説明資料見出しの基準は、
既存判定器全体とは区別する。

実験は明示的に実行し、アプリ起動やDBへのアクセスを行わない。上限付き本文を
設定したOllamaのエンドポイントへ送り、評価結果だけを出力する。
モデル結果は判定記録の作成、資料の採用、取得事実の変更に使わない。
根拠不足、不正な出力、コンテキスト上限、通信失敗は成功した分類と扱わず結果に残す。
比較可能にするため、モデルdigest・プロンプトとスキーマの版・入力ハッシュを記録する。
合成fixtureは公開し、運用入力・接続先アドレス・詳細結果は非公開かつGit追跡対象外に置く。

[ADR 0007](0007-register-pilot-sources-through-an-interface.md)の取得・判定・運用者判断の
境界を保持する。本番統合には評価証跡に基づく別の判断を必要とし、
この実験で財務数値の抽出への適性を確立したとは扱わない。

</details>
