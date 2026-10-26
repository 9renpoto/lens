---
status: accepted
---

# Register collection targets through an operator interface

Operators choose analysis targets and register their earnings listing sources
through APIs. Reuse `analysis_targets` as the security registry and associate
multiple `earnings_sources` with each target. This avoids a second registry and
allows collection configuration to change without code changes or deployment.

## Registration and collection boundary

Automatic earnings subscription discovery follows
[ADR 0017](0017-build-earnings-search-from-feed-updates.md). The listing-page
registration and bounded collector below describe the manual acquisition path;
they do not define a separate automatic subscription update detector.

A source has a fixed target, a listing-page URL and independent enablement.
Target activity does not control source enablement. New sources default to
enabled; operators can explicitly disable them. Reject duplicate listing URLs
within a target. Registration neither starts collection nor establishes a
document's issuer, kind or reporting identity.

Keep publisher-condition review in the operator procedure. It supplies no
application approval state or permission inferred from registration. Collection
uses a bounded run and an explicit URL policy for initial requests and redirects,
including published links on external document hosts. Apply transport and size
bounds independently of document assessment.

## Assessment boundary

Keep acquired originals and acquisition facts separate from automated document
assessments and explicit operator decisions. Record an assessment's outcome,
identity and supporting evidence using the shared assessment contract. Unknown
or contradictory identity stays pending and does not block other candidates.
Operator adoption must not invent missing identity, silently merge releases or
rewrite acquisition facts. Use APIs as the operator interface; a web UI is not
required by this decision.

Configuration edits do not rewrite retained acquisition or assessment history.
Use the [current schema initialization contract](0010-defer-backups-for-disposable-development-data.md)
for disposable databases and [RustFS](0005-store-pdfs-in-rustfs.md) for PDFs.
Keep exact API schemas in [OpenAPI](../api.md), procedures in the maintained
guides and task state in GitHub issues.

<details>
<summary>日本語</summary>

# 操作インターフェースから収集対象を登録する

運用者は分析対象を選び、その決算資料の一覧取得先をAPIから登録する。
銘柄台帳には`analysis_targets`を再利用し、各対象へ複数の`earnings_sources`を関連付ける。
二つ目の台帳を作らず、コード変更や配備なしで収集設定を変更できるようにする。

## 登録と収集の境界

決算購読の自動更新検知には[ADR 0017](0017-build-earnings-search-from-feed-updates.md)を適用する。
以下の一覧ページ登録と上限付き収集は手動取得の経路を記述し、独立した自動購読の更新検知を
定義しない。

取得先は固定の対象、一覧ページURL、独立した有効状態を持つ。
対象のactiveは取得先の有効状態を制御しない。新規取得先は有効を既定とし、
明示的に無効化できる。同じ対象内の一覧URLの重複を拒否する。
登録だけでは収集を開始せず、資料の発行元・種類・対象期間を確定しない。

公開元の条件確認は運用手順に置く。アプリ内の承認状態や、登録による取得許可の
推定は導入しない。収集は上限付きの実行と明示的なURLポリシーを使い、
初期リクエストと各リダイレクト先、公開された外部ホスト上の資料リンクにも適用する。
通信・サイズの上限は資料判定と独立して適用する。

## 判定の境界

取得原本と取得事実を、自動の資料判定と明示的な運用者判断から分ける。
共通の判定契約で結果・識別情報・根拠を記録する。不明・矛盾する識別は確認待ちにし、
他の候補の処理を止めない。運用者の採用で不足する識別を作ったり、
黙ってリリースを統合したり、取得事実を書き換えたりしない。
運用者のインターフェースにはAPIを使い、この判断でWeb UIを必須としない。

設定編集で保持した取得・判定履歴を書き換えない。破棄可能なDBには
[現行スキーマの初期化契約](0010-defer-backups-for-disposable-development-data.md)、
PDFには[RustFS](0005-store-pdfs-in-rustfs.md)を使う。
正確なAPIスキーマは[OpenAPI](../api.md)、手順は維持するガイド、
タスク状態はGitHub Issueに置く。

</details>
