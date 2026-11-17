# API reference publishing

Lens generates its OpenAPI 3.0.3 document from Phoenix controller operations
and schema modules. The generated document is the source for the static API
reference published at GitHub Pages.

The reference is available at `https://9renpoto.github.io/lens/` after GitHub
Pages is configured to publish through GitHub Actions.

Configure this once in the repository settings: open **Settings → Pages** and
set the source to **GitHub Actions**.

## Analysis target API

Operators use the target registry to manage configured issuers.

- `GET /api/targets`: List active and inactive targets in security-code order.
- `GET /api/targets/:id`: Retrieve a target by its UUID.
- `POST /api/targets`: Create an analysis target with security code, market, display name, sector, and optional tags.
- `PATCH /api/targets/:id`: Update target attributes.
- `POST /api/targets/:id/deactivate`: Non-destructively deactivate a target.

Historical index membership has been retired. The former
`/api/targets/:target_id/memberships` routes and their detail operations return
404. Target responses omit `memberships`. Remove `as_of` from list requests.
Clients still sending that parameter receive the full, unfiltered registry.
See [database initialization](deployment.md#database-initialization) for the
schema transition.

## Retired earnings listing-source API

`/api/targets/:target_id/earnings-sources` and its detail operations are removed.
Use `/api/sources` to register feeds and `/api/targets` to manage analysis targets.

## Retained earnings RSS

`GET /feeds/earnings.rss` publishes eligible input updates and confirmed earnings releases through the service feed. See the [RSS reference](reference/earnings-feed.md) for eligibility, GUIDs, links and the read-only consumer check.

## Generate locally

Generate the JSON document without starting the application:

```sh
mix openapi.spec.json --spec LensWeb.ApiSpec --pretty --start-app=false --filename openapi.json
```

Open `docs/api/index.html` beside the generated `openapi.json` to render the
reference. The HTML template uses a versioned ReDoc asset from jsDelivr.

## Publishing

The `Elixir CI` workflow generates the API document and Octocov coverage badge
after tests pass for pull requests and changes merged to `main`. It deploys both
in one GitHub Pages site only after a push to `main`; pull requests build the site
without publishing it. The README badge uses the published `coverage.svg`.

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

## 分析対象 API

運用者は対象台帳を使って設定対象の発行元を管理する。

- `GET /api/targets`: 有効・無効の両方の分析対象を証券コード順で取得する。
- `GET /api/targets/:id`: UUID で分析対象を取得する。
- `POST /api/targets`: 証券コード、市場、表示名、セクター、任意のタグを指定して分析対象を作成する。
- `PATCH /api/targets/:id`: 分析対象の属性を更新する。
- `POST /api/targets/:id/deactivate`: 分析対象を非破壊的に無効化する。

指数の所属履歴を廃止した。旧 `/api/targets/:target_id/memberships` ルートと詳細操作は
404 を返す。対象の応答から `memberships` を削除した。一覧リクエストから `as_of` を
削除する。このパラメータを送信し続けるクライアントには絞り込みなしで台帳全体を返す。
スキーマの移行手順は [DB 初期化](deployment.md#database-initialization) を参照する。

## 廃止した決算一覧取得先 API

`/api/targets/:target_id/earnings-sources` とその詳細操作は廃止した。
フィードの登録には `/api/sources`、分析対象の管理には `/api/targets` を使う。

## 保存済み決算情報のRSS

`GET /feeds/earnings.rss` で、掲載条件を満たした入力更新と確定済み決算リリースをサービス共通フィードから取得できる。掲載条件、GUID、リンク、読み取り専用の購読側検証は [RSS 参照資料](reference/earnings-feed.md) を参照する。

## ローカルでの生成

アプリケーションを起動せずにJSONドキュメントを生成します：

```sh
mix openapi.spec.json --spec LensWeb.ApiSpec --pretty --start-app=false --filename openapi.json
```

生成された `openapi.json` の隣にある `docs/api/index.html` を開いてリファレンスを描画します。HTMLテンプレートはjsDelivrのバージョン指定されたReDocアセットを使用します。

## 公開

`Elixir CI` ワークフローは、プルリクエストおよび `main` へのマージ時にテストが成功した後、APIドキュメントとOctocovカバレッジバッジを生成します。`main` へのプッシュ時のみ両方を1つのGitHub Pagesサイトとして公開します。プルリクエストではサイトを生成し、公開は行いません。READMEのバッジは公開された `coverage.svg` を参照します。

GitHub Pagesは生成されたデプロイ成果物を保持し、`gh-pages` ブランチの作成や維持は行われません。

## 契約の正確性維持

公開コントローラアクションにはそれぞれOpenAPI操作宣言があり、コントローラテストで生成されたスキーマに対するJSON応答の検証を行います。すべてのHTTP API変更において、同一変更内で操作とスキーマを追加・更新してください。

</details>
