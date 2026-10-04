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

## Documentation and GitHub language

Write repository documentation and GitHub pull-request and issue content in
English as the primary text. Include a matching Japanese translation in a closed-by-default
`<details>` block with `<summary>日本語</summary>`. Keep the English and
Japanese versions aligned when the content changes.

GitHub content includes pull-request and issue titles, descriptions, comments,
reviews, implementation notes, test reports, and follow-up items. For titles,
use English; put the Japanese translation in the corresponding description.
Keep technical names, commands, links, and code identifiers unchanged between
languages where possible.

Chat messages are outside this bilingual requirement. Use the language preferred
by the user; a matching translation or `<details>` block is not required in chat.

Keep source-code comments in English. Do not add Japanese comments to
production code or tests; explain Japanese-specific behavior in the bilingual
documentation or code-review text instead.

## Code Review Rules

### Review language

Write every authored GitHub review finding, review summary, and follow-up in
English, followed by a matching Japanese translation in that same comment's
closed-by-default `<details>` block with `<summary>日本語</summary>`. Apply this
to each inline comment individually; a bilingual PR description or a separate
summary does not substitute for translating the comment itself.

Keep finding titles in English and include their Japanese translation inside
the corresponding details block. Preserve the same severity, trigger, impact,
recommended action, code identifiers, and links in both languages. Before
submitting a review, check each authored comment and summary for both versions,
including a written no-findings summary. Do not invent findings to satisfy the
language format.

<details>
<summary>日本語</summary>

## ドキュメントとGitHubの言語

リポジトリのドキュメントとGitHubのプルリクエスト・Issueの内容は、英語を本文
として記載する。対応する日本語訳は、初期状態で閉じた`<details>`ブロック
内に`<summary>日本語</summary>`を付けて記載する。内容を変更した場合は、
英語と日本語を同時に更新する。

GitHubの内容には、プルリクエスト・Issueのタイトル、説明、コメント、レビュー、
実装メモ、テスト結果、フォローアップ項目を含める。タイトルは英語とし、
対応する日本語訳は説明本文に記載する。技術用語、コマンド、
リンク、コード識別子は、可能な限り両言語で変更せずに維持する。

チャット上のメッセージは、この日英併記ルールの対象外とする。ユーザーが希望する
言語を使い、チャットでは対応する翻訳や`<details>`ブロックを要求しない。

ソースコードのコメントは英語で残す。本番コードやテストに日本語のコメント
を追加せず、日本語固有の挙動は日英併記のドキュメントまたはコードレビュー
本文で説明する。

## コードレビュー規則

### レビューの言語

GitHubに投稿する各レビュー指摘・総評・追記は英語を本文とし、同じコメントの
初期状態で閉じた`<details>`ブロック（`<summary>日本語</summary>`）に対応する
日本語訳を付ける。各インラインコメントに個別に適用し、PR本文や別の総評が
日英併記であっても、そのコメント自身の翻訳の代わりにはしない。

指摘のタイトルは英語とし、対応するdetailsブロック内に日本語訳を含める。
重要度・発生条件・影響・推奨対応・コード識別子・リンクは両言語で揃える。
レビュー投稿前に、指摘なしと記述する総評も含め、各投稿コメントと総評に
両言語があることを確認する。言語形式を満たすために指摘を作り出さない。

</details>
