# Compare configurable earnings-document assessment models

This explicitly invoked experiment evaluates extracted text with an arbitrary
operator-selected model available through Ollama. Model and endpoint selection
are execution settings; Lens has no dependency on a particular personal model
installation or machine. It does not start Lens, access PostgreSQL,
create assessments, adopt releases or change acquisitions. See
[ADR 0016](../adr/0016-evaluate-self-hosted-document-assessment-offline.md).

## Run

Set `LENS_OLLAMA_ENDPOINT` to the selected Ollama server's base URL in your private
shell environment. Set `LENS_OLLAMA_MODEL` explicitly to an available model name;
there is no default model and no model is downloaded. The selected model/server
must support [`/api/chat` structured outputs](https://docs.ollama.com/capabilities/structured-outputs).
Thinking is omitted by default. Optionally set `LENS_OLLAMA_THINK` to `true`,
`false` or a thinking level supported by that model, such as `low`. The report
records the requested setting; `null` means the model's default behavior.
See [Ollama thinking controls](https://docs.ollama.com/capabilities/thinking).

From the repository root, with dependencies installed:

```sh
MIX_ENV=dev mix run --no-start scripts/evaluate_earnings_ollama.exs \
  test/fixtures/earnings/assessment_experiment.json \
  /private/tmp/earnings-assessment-report.json
```

The output file must not already exist. Each run makes sequential requests,
with no retries or redirects. Per-request bounds are 300 seconds, 12,000 input
bytes and 1 MiB of response bytes. Oversized text is an explicit failure, never
silently truncated. The request uses temperature/seed `0`, context `8192`, output
limit `1024`. These settings do not guarantee determinism or
accuracy. Use labelled, bounded excerpts for larger originals; do not claim
coverage of omitted pages.

The input is a JSON array of 1–100 objects with unique `id`, `text` and `expected`.
`expected` has exactly four fields: `document_kind`, `issuer_code`,
`fiscal_year_end` and `period`. Follow the synthetic fixture's format.
Document kinds are `earnings_release`, `correction`, `earnings_presentation`,
`other`, `unknown` and `mixed`. Other fields may be `null`; periods are
`q1`, `q2`, `q3` and `full_year`. Only `text` is supplied to the model; labels and
case IDs are not included in the prompt.

## Read the report

The report records model name/digest, prompt/schema versions and hashes, request
settings, input hashes, expected/predicted fields, quotations and per-case
latency. Model inventory is checked before and after the run; `model_stable`
is false if the tag changes or the final check fails. The command exits `2` for
that condition, and `1` for invalid input, unavailable model or report errors.
Per-case model failures remain in the report; command success does not mean
that every prediction succeeded or was correct. The printed summary is counts,
not a quality threshold or deployment approval.

Every case, including failures, contributes to the denominator `total`.
`exact_matches` requires all four fields to match, including explicit nulls.
`field_matches` counts each field separately. `verbatim_evidence_matches`
checks only whether non-null fields quote text actually present in the input
(and null fields have no quote). It does **not** establish that the quote supports
the interpretation. Reasoning traces and HTTP error bodies are not retained.

The regex baseline measures only whether a strict Japanese presentation heading
matches the presentation/non-presentation label. `regex_presentation_matches`
and `model_presentation_matches` are a binary detection comparison, separate
from the model's six-kind and identity scores. This baseline is not execution
of the complete ordinary-release, correction or presentation assessor.

The public fixture is eight short, wholly synthetic cases, including a wrapped
presentation title, missing period, conflicting issuers and a prose reference.
It tests the evaluation path and cannot establish publisher or long-document
accuracy. Model-generated self-confidence is not used as a correctness score.
Financial numbers and production integration remain outside this experiment.

Keep real input files and detailed reports private and untracked: labels and
quotations can identify evaluation targets. Do not commit endpoint addresses,
operational identifiers or raw reports. Public PR evidence should contain only
synthetic case results and aggregate checks.

<details>
<summary>日本語</summary>

# 選択可能な決算資料判定モデルを比較する

この実験は明示的に実行し、Ollamaを通じて利用できる、運用者が任意に選択したモデルで
抽出本文を評価する。モデルと接続先は実行時の設定であり、特定の個人環境のモデルや
マシンをLensの依存関係にしない。
Lensの起動、PostgreSQLへのアクセス、判定記録の作成、資料の採用、取得事実の変更は
行わない。[ADR 0016](../adr/0016-evaluate-self-hosted-document-assessment-offline.md)を参照する。

## 実行

非公開のシェル環境で`LENS_OLLAMA_ENDPOINT`に選択したOllamaサーバーのベースURLを設定する。
`LENS_OLLAMA_MODEL`には利用できるモデル名を明示する。既定モデルはなく、
モデルはダウンロードしない。選択したモデル・サーバーには
[`/api/chat`の構造化出力](https://docs.ollama.com/capabilities/structured-outputs)への対応を必要とする。
thinkingは既定で指定しない。任意で`LENS_OLLAMA_THINK`に`true`・`false`、または
`low`など選択モデルが対応するレベルを指定できる。要求した設定を結果へ記録し、
`null`はモデル既定の動作を意味する。
[Ollamaのthinking制御](https://docs.ollama.com/capabilities/thinking)を参照する。

依存関係を導入したリポジトリのルートから実行する。

```sh
MIX_ENV=dev mix run --no-start scripts/evaluate_earnings_ollama.exs \
  test/fixtures/earnings/assessment_experiment.json \
  /private/tmp/earnings-assessment-report.json
```

出力ファイルは未作成である必要がある。リクエストは逐次実行し、再試行やリダイレクトを
行わない。1リクエストの上限は300秒、入力12,000バイト、応答1 MiBとする。
過大な本文は黙って切り詰めず、失敗として記録する。temperatureとseedは`0`、
コンテキスト`8192`、出力上限`1024`を使う。これらは決定性や正確性を
保証しない。大きな原本にはラベル付きの上限内の抜粋を使い、除外したページへの
対応を断定しない。

入力は一意な`id`、`text`、`expected`を持つ1〜100件のJSON配列とする。
`expected`の項目は`document_kind`、`issuer_code`、`fiscal_year_end`、`period`の
4項目だけとし、合成fixtureの形式に従う。資料種類は`earnings_release`、`correction`、
`earnings_presentation`、`other`、`unknown`、`mixed`とする。他項目は`null`を許容し、
期間は`q1`、`q2`、`q3`、`full_year`とする。モデルへ送るのは`text`だけであり、
正解やケースIDはプロンプトに含めない。

## 結果の読み方

モデル名・digest、プロンプトとスキーマの版・ハッシュ、リクエスト設定、入力ハッシュ、
正解・予測項目、引用、ケース別処理時間を記録する。実行前後でモデル一覧を確認し、
タグが変わるか最後の確認が失敗すると`model_stable`をfalseにする。この場合コマンドは
終了コード`2`、不正入力・モデル不在・出力エラーでは`1`を返す。個別ケースの失敗は
レポートに残すため、コマンド成功はすべての予測の成功・正解を意味しない。
標準出力の要約は件数であり、品質閾値や配備承認ではない。

失敗を含む全ケースを分母`total`に含める。`exact_matches`は明示的なnullも含めた
4項目すべての一致、`field_matches`は項目別の一致を数える。
`verbatim_evidence_matches`は値のある項目の引用が実際の入力に存在し、null項目に
引用がないことだけを検証する。引用が解釈を裏付けることまでは保証しない。
推論過程やHTTPエラー本文は保存しない。

正規表現の基準は、厳密な日本語の説明資料見出しが説明資料／その他のラベルに
一致するかだけを測る。`regex_presentation_matches`と`model_presentation_matches`は
二値の検出比較であり、モデルの6種類分類や識別の成績とは分ける。
通常短信・訂正・説明資料の判定器全体を実行する基準ではない。

公開fixtureは完全に合成した短い8例で、改行された説明資料タイトル、期間の欠落、
企業コードの矛盾、本文中の参照を含む。評価経路の検証用であり、実際の公開元や
長文の正確性を確立しない。モデルが出す自己評価を正確性のスコアとして使わない。
財務数値や本番統合は実験の範囲外とする。

正解や引用から評価対象を識別できるため、実入力と詳細結果は非公開かつGit追跡対象外に
置く。接続先アドレス、運用識別子、生レポートをコミットしない。公開するPRの証跡は
合成ケースの結果と集計した検証結果に限定する。

</details>
