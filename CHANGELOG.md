## v0.2.0 (2026-10-20)
<!-- Release notes generated using configuration in .github/release.yml at main -->

## What's Changed
### :memo: Documentation
* docs: scope bilingual policy to GitHub and documentation by @9renpoto in https://github.com/9renpoto/lens/pull/102
### Other Changes
* Deploy API docs with GitHub Pages by @9renpoto in https://github.com/9renpoto/lens/pull/77
* docs: define bilingual documentation and review guidance by @9renpoto in https://github.com/9renpoto/lens/pull/78
* Delete labels.yaml by @9renpoto in https://github.com/9renpoto/lens/pull/79
* build(deps): bump zizmorcore/zizmor-action from 0.6.2 to 0.6.4 by @dependabot[bot] in https://github.com/9renpoto/lens/pull/84
* build(deps): bump actions/deploy-pages from 5.0.0 to 5.0.1 by @dependabot[bot] in https://github.com/9renpoto/lens/pull/81
* build(deps): bump phoenix from 1.8.13 to 1.8.14 by @dependabot[bot] in https://github.com/9renpoto/lens/pull/80
* feat: expose paginated document provenance through JSON API by @9renpoto in https://github.com/9renpoto/lens/pull/85
* feat: manage attributed analysis targets and Nikkei 225 membership over time (#43) by @9renpoto in https://github.com/9renpoto/lens/pull/86
* Preserve immutable earnings originals and acquisition history by @9renpoto in https://github.com/9renpoto/lens/pull/87
* Persist earnings extraction attempts and select release text by @9renpoto in https://github.com/9renpoto/lens/pull/88
* Extract retained earnings PDFs with bounded offline reprocessing by @9renpoto in https://github.com/9renpoto/lens/pull/89
* Search selected earnings text and rebuild derived data by @9renpoto in https://github.com/9renpoto/lens/pull/90
* build(deps): bump codecov/codecov-action from 7.0.0 to 7.1.1 by @dependabot[bot] in https://github.com/9renpoto/lens/pull/82
* build(deps): bump crate-ci/typos from 1.50.1 to 1.50.2 by @dependabot[bot] in https://github.com/9renpoto/lens/pull/101
* build(deps): bump reviewdog/action-actionlint from 1.73.4 to 1.76.0 by @dependabot[bot] in https://github.com/9renpoto/lens/pull/99
* build(deps): bump docker/setup-buildx-action from 4.3.0 to 4.4.1 by @dependabot[bot] in https://github.com/9renpoto/lens/pull/98
* build(deps): bump docker/build-push-action from 7.3.0 to 7.4.0 by @dependabot[bot] in https://github.com/9renpoto/lens/pull/97
* build(deps): bump debian from bookworm-20260824-slim to bookworm-20260918-slim by @dependabot[bot] in https://github.com/9renpoto/lens/pull/100
* Decide bounded PDF runner replacement for #92 by @9renpoto in https://github.com/9renpoto/lens/pull/95
* Hand off PDF runner implementation after #92 decision by @9renpoto in https://github.com/9renpoto/lens/pull/96
* Add bounded native PDF runner and Port adapter by @9renpoto in https://github.com/9renpoto/lens/pull/103
* Remove PDF extraction Python dependency after release proof by @9renpoto in https://github.com/9renpoto/lens/pull/104
* Clarify bilingual output for GitHub code reviews by @9renpoto in https://github.com/9renpoto/lens/pull/108
* Publish earnings source catalog and discovery fixtures by @9renpoto in https://github.com/9renpoto/lens/pull/105
* Map pilot PDF identity and select initial regular release by @9renpoto in https://github.com/9renpoto/lens/pull/106
* Discover bounded PDF links from reviewed pilot listings by @9renpoto in https://github.com/9renpoto/lens/pull/107
* Bound earnings HTTP bytes, redirects and total duration by @9renpoto in https://github.com/9renpoto/lens/pull/109
* Persist immutable earnings HTTP check history by @9renpoto in https://github.com/9renpoto/lens/pull/110
* Bound HTTP requests across earnings collection runs by @9renpoto in https://github.com/9renpoto/lens/pull/111
* docs(adr): record earnings preservation decisions by @9renpoto in https://github.com/9renpoto/lens/pull/112
* docs(v0.2): publish earnings pilot planning packet by @9renpoto in https://github.com/9renpoto/lens/pull/113
* ci: limit Elixir PR checks to relevant file changes by @9renpoto in https://github.com/9renpoto/lens/pull/114
* docs: retain earnings PDFs for reprocessing by @9renpoto in https://github.com/9renpoto/lens/pull/115
* docs: choose RustFS and define storage recovery by @9renpoto in https://github.com/9renpoto/lens/pull/116
* docs: register pilot targets and sources through an API by @9renpoto in https://github.com/9renpoto/lens/pull/118
* docs: revise v0.2 tasks around agreed ADRs by @9renpoto in https://github.com/9renpoto/lens/pull/119
* build(deps): bump phoenix from 1.8.14 to 1.8.15 by @dependabot[bot] in https://github.com/9renpoto/lens/pull/121
* build(deps): bump crate-ci/typos from 1.50.2 to 1.50.3 by @dependabot[bot] in https://github.com/9renpoto/lens/pull/122
* build(deps): bump reviewdog/action-actionlint from 1.76.0 to 1.77.0 by @dependabot[bot] in https://github.com/9renpoto/lens/pull/123
* docs: consolidate v0.2 decisions and remove obsolete plans by @9renpoto in https://github.com/9renpoto/lens/pull/120
* docs: define source assessment boundaries and ADR management by @9renpoto in https://github.com/9renpoto/lens/pull/132
* Persist registered earnings sources and preserve HTTP history by @9renpoto in https://github.com/9renpoto/lens/pull/133
* Manage earnings sources through the analysis target API by @9renpoto in https://github.com/9renpoto/lens/pull/134
* Consolidate earnings source contracts in ADR and OpenAPI by @9renpoto in https://github.com/9renpoto/lens/pull/135
* Collect registered earnings candidates independently of assessment by @9renpoto in https://github.com/9renpoto/lens/pull/137
* Move v0.2 task references to authoritative issues by @9renpoto in https://github.com/9renpoto/lens/pull/140
* Remove the relocated temporary v0.2 task summary by @9renpoto in https://github.com/9renpoto/lens/pull/141
* feat(earnings): add immutable RustFS storage client by @9renpoto in https://github.com/9renpoto/lens/pull/148
* feat(earnings): add durable RustFS write recovery by @9renpoto in https://github.com/9renpoto/lens/pull/149
* feat(earnings): track original storage locations by @9renpoto in https://github.com/9renpoto/lens/pull/150
* ci: migrate coverage reporting to Octocov by @9renpoto in https://github.com/9renpoto/lens/pull/153
* refactor(earnings): remove unused storage rollback controls by @9renpoto in https://github.com/9renpoto/lens/pull/154
* ci: fetch full history for Octocov badge push by @9renpoto in https://github.com/9renpoto/lens/pull/155
* ci: publish Octocov coverage badge through GitHub Pages by @9renpoto in https://github.com/9renpoto/lens/pull/156
* Record RustFS integration decisions for #146 by @9renpoto in https://github.com/9renpoto/lens/pull/157
* Verify retained originals before creating extraction attempts by @9renpoto in https://github.com/9renpoto/lens/pull/161
* Connect collection to durable RustFS storage completion by @9renpoto in https://github.com/9renpoto/lens/pull/167
* build(deps): bump crate-ci/typos from 1.50.3 to 1.51.1 by @dependabot[bot] in https://github.com/9renpoto/lens/pull/165
* build(deps): bump debian from bookworm-20260918-slim to bookworm-20261005-slim by @dependabot[bot] in https://github.com/9renpoto/lens/pull/166
* build(deps): bump reviewdog/action-actionlint from 1.77.0 to 1.79.1 by @dependabot[bot] in https://github.com/9renpoto/lens/pull/163
* build(deps): bump req from 0.7.4 to 0.7.5 by @dependabot[bot] in https://github.com/9renpoto/lens/pull/162
* Expose bounded storage-work views and verified original PDFs by @9renpoto in https://github.com/9renpoto/lens/pull/168
* build(deps): bump actions/download-artifact from 7.0.0 to 8.0.1 by @dependabot[bot] in https://github.com/9renpoto/lens/pull/164
* Defer backups while Lens development data remains disposable by @9renpoto in https://github.com/9renpoto/lens/pull/174
* Prioritize value validation before backups by @9renpoto in https://github.com/9renpoto/lens/pull/175
* feat: record earnings assessment outcomes and evidence by @9renpoto in https://github.com/9renpoto/lens/pull/176
* Assess correction PDFs with evidence-backed release relationships by @9renpoto in https://github.com/9renpoto/lens/pull/177
* Assess registered earnings-release PDFs with retained evidence by @9renpoto in https://github.com/9renpoto/lens/pull/178
* docs: define earnings-search value-validation procedure by @9renpoto in https://github.com/9renpoto/lens/pull/179
* docs: clarify rights for collected earnings materials by @9renpoto in https://github.com/9renpoto/lens/pull/180
* docs: define Lens discovery value and product direction by @9renpoto in https://github.com/9renpoto/lens/pull/183
* fix(search): show readable earnings release titles by @9renpoto in https://github.com/9renpoto/lens/pull/182
* Allow bounded collection from long PDF listings by @9renpoto in https://github.com/9renpoto/lens/pull/188
* chore: migrate optional project hooks from lefthook to hk by @9renpoto in https://github.com/9renpoto/lens/pull/191
* Restructure README and refresh release documentation by @9renpoto in https://github.com/9renpoto/lens/pull/192
* docs: retire interrupted storage recovery for bounded validation by @9renpoto in https://github.com/9renpoto/lens/pull/196
* refactor!: retire earnings storage recovery by @9renpoto in https://github.com/9renpoto/lens/pull/197
* build(deps): bump actions/download-artifact from 8.0.1 to 8.0.2 by @dependabot[bot] in https://github.com/9renpoto/lens/pull/189
* build(deps): bump reviewdog/action-actionlint from 1.79.1 to 1.80.0 by @dependabot[bot] in https://github.com/9renpoto/lens/pull/190


**Full Changelog**: https://github.com/9renpoto/lens/compare/v0.1.0...v0.2.0
