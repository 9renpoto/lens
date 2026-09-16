# API reference publishing

Lens generates its OpenAPI 3.0.3 document from Phoenix controller operations
and schema modules. The generated document is the source for the static API
reference published at GitHub Pages.

The reference is available at `https://9renpoto.github.io/lens/` after GitHub
Pages is configured to publish through GitHub Actions.

Configure this once in the repository settings: open **Settings → Pages** and
set the source to **GitHub Actions**.

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
