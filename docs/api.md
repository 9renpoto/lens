# API reference publishing

Lens generates its OpenAPI 3.0.3 document from Phoenix controller operations
and schema modules. The generated document is the source for the static API
reference published at GitHub Pages.

The reference is available at `https://9renpoto.github.io/lens/` after GitHub
Pages is configured to publish the root of the `gh-pages` branch.

Configure this once in the repository settings: open **Settings → Pages**, set
the source to **Deploy from a branch**, select `gh-pages`, and select `/ (root)`.

## Generate locally

Generate the JSON document without starting the application:

```sh
mix openapi.spec.json --spec LensWeb.ApiSpec --pretty --start-app=false --filename openapi.json
```

Open `docs/api/index.html` beside the generated `openapi.json` to render the
reference. The HTML template uses a versioned ReDoc asset from jsDelivr.

## Publishing

The `Publish API documentation` workflow generates the document for pull
requests and for changes merged to `main`. It only pushes the generated site to
the `gh-pages` branch after a push to `main`; pull requests never receive
write permission or publish documentation.

The `gh-pages` branch is generated output. Do not edit it manually.

## Keeping the contract accurate

Each public controller action has an OpenAPI operation declaration, and
controller tests validate JSON responses against the generated schemas. Add or
update the operation and schema in the same change as every HTTP API change.
