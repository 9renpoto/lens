# Ingestion error reporting

`Lens.ErrorReporter.report/2` reports an expected error result or an exception
from `:discovery`, `:acquisition`, `:association`, `:extraction` or `:indexing`.
Call it at the boundary that handles a failed operation. It returns `:ok` even
when reporting fails, so independent items can continue. The reporting interface
does not itself implement acquisition, extraction, indexing or retry behavior.

Set `SENTRY_DSN` through private runtime configuration to enable Sentry delivery.
Omit it to leave delivery disabled. Never put the value in repository files,
commands committed as examples, or public reports. No Logger or Phoenix automatic
capture integration is installed. Use the reporting interface explicitly.

The SDK's `before_send` callback rebuilds recognized ingestion events from an
allowlist. Events contain a fresh event ID, timestamp, fixed message, processing
stage and `error`/`exception` kind, with a stage/kind fingerprint. Unrecognized
events are discarded. Raw exceptions, stacktraces, bodies, attachment bytes,
source/target identifiers, URLs, credentials, breadcrumbs, requests, user context,
module lists, hostnames and release/environment metadata are not sent. This
intentionally limits diagnosis to the failing stage and kind. Error details and
handling status belong in Sentry; no database error inbox is introduced.

The SDK uses background delivery in ordinary operation. Acceptance by the local
SDK does not prove receipt by Sentry. An unavailable reporter does not add
failed-material replay or a recovery queue. Tests use the SDK with an in-memory
HTTP transport and inspect the serialized envelope without contacting Sentry.
Live service receipt must be verified separately with synthetic data and private
configuration before claiming operational delivery.

<details>
<summary>日本語</summary>

# 取り込みエラーの記録

`Lens.ErrorReporter.report/2`は`:discovery`・`:acquisition`・`:association`・
`:extraction`・`:indexing`の想定済みエラー戻り値または例外を報告する。
失敗した操作を処理する境界から呼び出す。報告が失敗しても`:ok`を返し、独立した項目の
処理を継続できる。報告インターフェース自体は取得・抽出・検索登録・再試行を実装しない。

Sentry配送を有効にするには、非公開の実行時設定で`SENTRY_DSN`を設定する。
省略時は配送しない。値をリポジトリのファイル、コミットするコマンド例、公開レポートに
記載しない。Logger・Phoenixの自動捕捉は導入せず、報告インターフェースを明示的に使う。

SDKの`before_send`コールバックは、認識した取り込みイベントを許可リストから再構築する。
イベントには新たなイベントID・日時・固定メッセージ・処理段階・`error`/`exception`種別と、
段階・種別に基づくfingerprintを含める。認識できないイベントは破棄する。生の例外・
スタックトレース・本文・添付バイト列・取得先や対象の識別子・URL・認証情報・breadcrumb・
リクエスト・ユーザー情報・モジュール一覧・ホスト名・リリースや環境のメタデータは送らない。
診断情報を失敗した段階・種別に意図的に限定する。詳細と対応状況はSentryで管理し、
DBのエラー管理一覧は導入しない。

通常運用ではSDKがバックグラウンド配送する。ローカルSDKの受け付けはSentryでの受信を
証明しない。報告先が使えなくても失敗資料の再処理・復旧キューは追加しない。テストは
インメモリHTTP transportを使ってSDKが直列化したenvelopeを確認し、Sentryへ接続しない。
実運用の配送を主張する前に、架空データと非公開設定で実サービス受信を別途検証する。

</details>
