# Publishing a release

Lens publishes container images to `ghcr.io/9renpoto/lens` through CI.
Release tags use `vMAJOR.MINOR.PATCH`; prerelease and build metadata are not
supported. See the [runtime contract](deployment.md) for running an image and
[GitHub release issues](https://github.com/9renpoto/lens/issues) for release scope.

## Prepare and tag

Run the repository's version-bump workflow to prepare a release PR. After a
maintainer merges that PR, record its merge commit and the version in `mix.exs`.
Create an annotated tag on that exact commit, then push the tag. For example,
set `RELEASE_TAG` and `RELEASE_COMMIT` to the prepared version and commit.
`v0.2.0` is already published and must not be reused:

```sh
git fetch origin main
git tag --list 'v*.*.*'
: "${RELEASE_TAG:?Set the prepared release tag}" "${RELEASE_COMMIT:?Set the release merge commit}"
git tag -a "$RELEASE_TAG" "$RELEASE_COMMIT" -m "Release $RELEASE_TAG"
git push origin "$RELEASE_TAG"
```

Do not reuse an existing release tag. A tag push runs CI; the matching image
is published only after tests pass. The release tag, `latest`, and the
commit-specific `sha-...` tag come from the same image build. Successful
`main` pushes and release-tag publication can both advance `latest`.

## Package retention

GHCR cleanup retains the two newest tagged image versions. Untagged manifests
referenced by retained multi-platform indexes are preserved. Environments that
need older images must arrange their own retention.

<details>
<summary>日本語</summary>

# リリースの公開

LensはCIから`ghcr.io/9renpoto/lens`へコンテナイメージを公開する。
リリースタグは`vMAJOR.MINOR.PATCH`とし、prerelease・build metadataは対象外。
イメージの実行は[実行契約](deployment.md)、リリース範囲は[GitHubのリリースIssue](https://github.com/9renpoto/lens/issues)を参照する。

## 準備とタグ作成

リポジトリのversion-bump workflowでリリースPRを準備する。
メンテナーがそのPRをmergeした後、merge commitと`mix.exs`のversionを記録する。
そのcommitに注釈付きタグを作成してpushする。次の例では`RELEASE_TAG`と`RELEASE_COMMIT`に
準備したversionとcommitを設定する。`v0.2.0`は公開済みのため再利用しない。

```sh
git fetch origin main
git tag --list 'v*.*.*'
: "${RELEASE_TAG:?Set the prepared release tag}" "${RELEASE_COMMIT:?Set the release merge commit}"
git tag -a "$RELEASE_TAG" "$RELEASE_COMMIT" -m "Release $RELEASE_TAG"
git push origin "$RELEASE_TAG"
```

既存のリリースタグは再利用しない。タグpushでCIを実行し、テスト成功後だけ対応する
イメージを公開する。リリースタグ・`latest`・コミット固有の`sha-...`タグは同じbuildから作る。
`main`へのpush成功とリリースタグの公開は、どちらも`latest`を更新し得る。

## パッケージの保持

GHCRのcleanupはタグ付きイメージの最新2版を保持し、保持するmulti-platform indexが
参照するタグなしmanifestも保持する。古いイメージが必要な環境は別途保持を用意する。

</details>
