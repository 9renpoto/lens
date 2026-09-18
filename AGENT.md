# Development Instructions

Use test-driven development for production changes.

1. Write or update a test that describes the intended observable behavior before
   implementing the behavior.
2. Run the focused test and confirm that it fails for the expected reason.
3. Implement the smallest change that makes the test pass.
4. Refactor only while the relevant tests remain green.

For bugs, begin with a regression test. Keep tests focused on behavior and avoid
tests that only mirror implementation details. Run the relevant test suite before
submitting work for review.

## Documentation and code-review language

Write repository documentation and code-review artifacts in English as the
primary text. Include a matching Japanese translation in a closed-by-default
`<details>` block with `<summary>日本語</summary>`. Keep the English and
Japanese versions aligned when the content changes.

Code-review artifacts include pull-request descriptions, review summaries,
implementation notes, test reports, and follow-up items. Keep technical names,
commands, links, and code identifiers unchanged between languages where
possible.

Keep source-code comments in English. Do not add Japanese comments to
production code or tests; explain Japanese-specific behavior in the bilingual
documentation or code-review text instead.

<details>
<summary>日本語</summary>

## ドキュメントとコードレビューの言語

リポジトリのドキュメントとコードレビュー関連の成果物は、英語を本文
として記載する。対応する日本語訳は、初期状態で閉じた`<details>`ブロック
内に`<summary>日本語</summary>`を付けて記載する。内容を変更した場合は、
英語と日本語を同時に更新する。

コードレビュー関連の成果物には、プルリクエストの説明、レビュー概要、
実装メモ、テスト結果、フォローアップ項目を含める。技術用語、コマンド、
リンク、コード識別子は、可能な限り両言語で変更せずに維持する。

ソースコードのコメントは英語で残す。本番コードやテストに日本語のコメント
を追加せず、日本語固有の挙動は日英併記のドキュメントまたはコードレビュー
本文で説明する。

</details>
