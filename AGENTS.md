# Development Instructions

## Public repository and operational target privacy

This is an OSS repository. Treat committed files and GitHub artifacts as public.
Never commit or publish identifying information about actual evaluation,
collection, or monitoring targets. This includes real company names, securities
or issuer codes, source URLs or domains, target/source IDs, private environment
information, and combinations of values that reveal the target. Mentioning a
target in a conversation does not authorize publishing its identity.

Apply this rule to code, documentation, ADRs, comments, filenames, fixtures,
expected test data, commit messages, PR and issue content, review replies, logs,
and attached artifacts. Use neutral placeholders or wholly fictional examples;
labeling real identifiers as synthetic does not anonymize them. Keep actual target
configuration and operational evidence in private, untracked locations.

Inspect the complete staged diff and all outgoing GitHub content for these
identifiers before publishing. Remove or anonymize existing violations rather
than copying them into new work. If identifying data has already been committed,
remove it from the affected branch history within the authorized scope and scrub
editable public descriptions; a later deletion commit does not remove earlier
public versions. Do not claim that old copies or caches have been erased without
verification.

<details>
<summary>日本語</summary>

## 公開リポジトリと実運用対象の秘匿

このリポジトリはOSSであり、コミットするファイルとGitHub上の情報を公開情報として扱う。
実際の検証・収集・監視対象を識別できる情報は、絶対にコミット・公開しない。
実在企業名、証券コード・発行元コード、取得元URL・ドメイン、対象・取得先ID、
非公開環境の情報、および対象を推測できる値の組み合わせを含む。
会話中で対象が言及されても、その識別情報の公開が許可されたとは扱わない。

コード、文書、ADR、コメント、ファイル名、fixture、テスト期待値、コミットメッセージ、
PR・Issue本文、レビュー返信、ログ、添付資料のすべてに適用する。
中立的なプレースホルダーか完全な架空データを使う。実在の識別子をsyntheticと呼んでも
匿名化したことにはならない。実際の対象設定や運用証跡は、非公開かつGit追跡対象外の
場所で管理する。

公開前にステージ済み差分全体とGitHubへ送信する内容を確認する。既存の違反は新しい
作業へコピーせず、除去・匿名化する。識別情報をコミット済みの場合は、許可された範囲で
該当ブランチの履歴から取り除き、編集可能な公開説明も修正する。後続の削除コミットだけ
では過去の公開版から消えない。古いコピーやキャッシュの消去を確認なしに断言しない。

</details>

Use test-driven development for production changes.

1. Write or update a test that describes the intended observable behavior before
   implementing the behavior.
2. Run the focused test and confirm that it fails for the expected reason.
3. Implement the smallest change that makes the test pass.
4. Refactor only while the relevant tests remain green.

For bugs, begin with a regression test. Keep tests focused on behavior and avoid
tests that only mirror implementation details. Run the relevant test suite before
submitting work for review.

## Planning before implementation

Standalone planning documents, roadmaps, and execution plans are discouraged.
Define scoped work in GitHub issues and record and agree on relevant design
decisions and their rationale in ADRs before starting implementation. Reference an
existing accepted ADR when it already covers the decision. Keep task state and
dependencies in issues, current decisions in ADRs, and implemented procedures in
maintained guides. Follow [ADR 0011](docs/adr/0011-plan-work-through-issues-and-adrs.md).

<details>
<summary>日本語</summary>

独立した計画文書・ロードマップ・実行計画の作成は非推奨とする。
具体的な実装を始める前に、範囲を定めたGitHub Issueを作成し、必要な設計判断と理由を
ADRへ記録して合意する。既存の承認済みADRが判断を扱っていれば参照する。
タスク状態・依存関係はIssue、現在の決定はADR、実装済みの手順は維持するガイドに置く。
[ADR 0011](docs/adr/0011-plan-work-through-issues-and-adrs.md)に従う。

</details>

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
