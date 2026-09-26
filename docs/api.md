# API reference publishing

Lens generates its OpenAPI 3.0.3 document from Phoenix controller operations
and schema modules. The generated document is the source for the static API
reference published at GitHub Pages.

The reference is available at `https://9renpoto.github.io/lens/` after GitHub
Pages is configured to publish through GitHub Actions.

Configure this once in the repository settings: open **Settings → Pages** and
set the source to **GitHub Actions**.

## Target and Membership Management API

Operators can manage analysis targets and effective-dated Nikkei 225 membership intervals:

- `GET /api/targets`: List targets (supports optional `as_of=YYYY-MM-DD` query parameter for active membership lookup).
- `GET /api/targets/:id`: Retrieve a target with its membership intervals.
- `POST /api/targets`: Create an analysis target with security code, market, display name, sector, and optional tags.
- `PATCH /api/targets/:id`: Update target attributes.
- `POST /api/targets/:id/deactivate`: Non-destructively deactivate a target.
- `GET /api/targets/:target_id/memberships`: List membership intervals for a target.
- `POST /api/targets/:target_id/memberships`: Add an effective-dated membership interval for a target.
- `PATCH /api/targets/:target_id/memberships/:id`: Update or close a membership interval while preserving its history.

## Generate locally

Generate the JSON document without starting the application:

```sh
mix openapi.spec.json --spec LensWeb.ApiSpec --pretty --start-app=false --filename openapi.json
```

Open `docs/api/index.html` beside the generated `openapi.json` to render the
reference. The HTML template uses a versioned ReDoc asset from jsDelivr.

## Publishing

The `Publish API documentation` workflow generates the document for pull
requests and for changes merged to `main`. It only deploys the generated site to
GitHub Pages after a push to `main`; pull requests never publish documentation.

GitHub Pages stores the generated deployment artifact; no `gh-pages` branch is
created or maintained.

## Keeping the contract accurate

Each public controller action has an OpenAPI operation declaration, and
controller tests validate JSON responses against the generated schemas. Add or
update the operation and schema in the same change as every HTTP API change.

<details>
<summary>日本語</summary>

# APIリファレンスの公開

LensはPhoenixコントローラの操作とスキーマモジュールからOpenAPI 3.0.3ドキュメントを生成します。生成されたドキュメントは、GitHub Pagesで公開される静的APIリファレンスのソースとなります。

GitHub Actions経由で公開するようGitHub Pagesを設定すると、リファレンスは `https://9renpoto.github.io/lens/` で閲覧可能になります。

リポジトリ設定の **Settings → Pages** でソースを **GitHub Actions** に設定してください。

## 分析対象および所属期間管理API

運用者は分析対象および適用期間付きの日経225所属期間を管理できます：

- `GET /api/targets`: 分析対象の一覧を取得します（`as_of=YYYY-MM-DD` クエリパラメータで指定日時点で有効な所属を抽出可能）。
- `GET /api/targets/:id`: 指定された分析対象とその所属期間を取得します。
- `POST /api/targets`: 証券コード、市場、表示名、セクター、タグを指定して分析対象を作成します。
- `PATCH /api/targets/:id`: 分析対象の属性を更新します。
- `POST /api/targets/:id/deactivate`: 分析対象を非破壊的に無効化します。
- `GET /api/targets/:target_id/memberships`: 分析対象の所属期間一覧を取得します。
- `POST /api/targets/:target_id/memberships`: 分析対象に適用期間付きの所属期間を追加します。
- `PATCH /api/targets/:target_id/memberships/:id`: 履歴を保持したまま所属期間を更新または終了します。

## ローカルでの生成

アプリケーションを起動せずにJSONドキュメントを生成します：

```sh
mix openapi.spec.json --spec LensWeb.ApiSpec --pretty --start-app=false --filename openapi.json
```

生成された `openapi.json` の隣にある `docs/api/index.html` を開いてリファレンスを描画します。HTMLテンプレートはjsDelivrのバージョン指定されたReDocアセットを使用します。

## 公開

`Publish API documentation` ワークフローは、プルリクエストおよび `main` へのマージ時にドキュメントを生成します。`main` へのプッシュ時のみ生成されたサイトをGitHub Pagesにデプロイし、プルリクエストでは公開されません。

GitHub Pagesは生成されたデプロイ成果物を保持し、`gh-pages` ブランチの作成や維持は行われません。

## 契約の正確性維持

公開コントローラアクションにはそれぞれOpenAPI操作宣言があり、コントローラテストで生成されたスキーマに対するJSON応答の検証を行います。すべてのHTTP API変更において、同一変更内で操作とスキーマを追加・更新してください。

</details>
