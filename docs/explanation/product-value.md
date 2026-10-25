# Product value: discover changes through connected information

This is a maintained explanation of why Lens exists and what value
it aims to provide, not an implementation plan or a claim of delivered capability.
Its strengths and usefulness remain hypotheses to validate.

## Problem and intended outcome

The initial user is an individual interested in companies and industries who
is still learning how to compare them. Encountering individual announcements
does not necessarily reveal how they connect or why they matter to a company
the user follows. Repeatedly searching for material leaves that connecting work
with the user.

Lens should collect and aggregate information so the user can notice relevant
changes without first deciding what to search for. The outcome is a reason to
reconsider an investment candidate or holding and decide what to investigate
next. Understanding and learning support that outcome; they are not the sole
purpose of the product.

## Value and proposed strength

> Lens connects information about companies and related areas the user cares
> about, delivering evidence and questions that reveal the background to change
> before the user starts searching. These discoveries help the user reconsider
> investment choices.

The proposed strength is aggregation that exposes relationships, differences,
and contradictions in the context of the user's interests. The amount collected,
the length of retention, and readable summaries alone do not establish this value.
Search supports investigation after discovery rather than defining the final
user outcome.

The user does not need an existing investment thesis. Begin with observing a
company over time and noticing differences; the longer-term ambition is to
connect signals across companies and industries. Useful comparisons can help
the user understand how businesses earn money and why their profitability differs,
without making financial education the entire product definition.

## Scope and responsibility

- Prioritize sources according to the user's interests. Initially, use only
  sources whose intended collection is permitted by the publisher and which the
  user has approved for collection. Publisher permission and user approval are
  distinct conditions, not a proposed application approval workflow.
- Extend attention from selected companies and themes to related areas such as
  customers, competitors, and suppliers, within the same collection boundaries.
- Initially support investment reconsideration. The broader ambition includes
  changes in hiring and industries, and opportunities or changes in new and
  existing businesses.
- Recommend matters worth investigating, not investments to buy or sell. Initially,
  Lens is responsible for showing supported relationships and questions to check.
  The user evaluates the impact and makes the investment decision.
- Prefer discoveries whose basis can be inspected over speculative connections.
  Distinguish observed facts from interpretations; a relationship is not proof
  of causation, including when discussing market price movements.

## Illustrative situation

The discussion used a decline in AI-related stocks and its background as an
example, not as a verified account of a particular market event. The desired
value is to connect relevant company announcements and industry developments to
companies the user follows, with evidence and questions that make the background
understandable. Merely repeating that the stocks fell is insufficient. Predicting
the fall or prescribing a trade is not the initial responsibility.

## Relationship to existing Lens

Lens follows Collect → Preserve → Search → Discover. The [README](../../README.md)
introduces the application and its usage; [GitHub issues](https://github.com/9renpoto/lens/issues)
track release boundaries and future discovery experiments. This direction makes the
intended discovery value explicit rather than claiming that discovery is a
newly invented project goal.

| Aspect | Existing definition or checkpoint | Proposed value emphasis |
| --- | --- | --- |
| Starting point | Search for material; later monitor saved searches | Receive relevant discoveries before forming a query |
| Information delivered | Search matches or newly published matching material | Supported connections and differences relevant to the user's interests |
| User outcome | Find material and inspect its original | Understand the background to change and reconsider investment choices |
| Attention | Selected targets, sources, and search conditions | Interest-based priorities, extending into related areas |
| Value evidence | Run the search/original comparison and discuss usefulness | Discover a connection the user had not made and wants to investigate |

Lens supports bounded manual collection, Japanese search, and exact-original
comparison for one issuer through the [validation procedure](../reference/earnings-value-validation.md).
These operations help inspect retained material; they do not by themselves
establish the discovery value described here.

The RSS publication design exposes retained earnings information
for the selected issuer using existing generated titles, full extracted text and
retained-original links. [ADR 0014](../adr/0014-publish-retained-earnings-through-rss.md)
records this boundary without manual candidate authoring or editorial selection.
The [RSS reference](../reference/earnings-feed.md) describes the implemented
output and read-only consumer check. [#185](https://github.com/9renpoto/lens/issues/185)
and [#186](https://github.com/9renpoto/lens/issues/186) track the release boundary
and verification evidence. Reading the actual retained result provides a basis for discussing
value and limitations; RSS publication alone does not establish usefulness or
automatic discovery.

Saved-search matching identifies material that meets retained search conditions.
It does not by itself provide the relationships and investigation questions
central to the product-value hypothesis.

The existing directions for
[preserved analytical evidence #50](https://github.com/9renpoto/lens/issues/50)
and [primary-evidence review #53](https://github.com/9renpoto/lens/issues/53)
support inspectability, but do not claim an implemented discovery engine.
Publisher-condition review and operator-selected sources also align with
[ADR 0007](../adr/0007-register-pilot-sources-through-an-interface.md).

## Success, failure, and review questions

The first value to demonstrate is discovery quality: the user can say,
"I had not connected these pieces of information; this is worth investigating."
The eventual outcome remains a reasoned next action or investment reconsideration;
an interesting question alone does not establish that full outcome. These are
qualitative hypotheses, not measured results or a numeric release gate.

A restatement of already known information fails the central value hypothesis,
even if it is convenient to read. An unfamiliar connection also needs relevance
to the user's interests and an inspectable basis.

Review should assess whether:

- The problem and intended outcome describe a useful, coherent product.
- Connecting information to personal interests is a credible strength beyond
  search, summaries, and saved-search alerts; differentiation is not yet proven.
- The initial boundary between supported relationships and user judgment is clear.
- The distinction between implemented behavior, the publication design, and
  the product-value hypothesis is explicit enough.

Automatic collection methods, analytical techniques, delivery beyond the RSS
publication boundary, notification frequency, and UI need separate decisions.
This explanation selects no implementation for them; use release issues for
scope and ADRs for the agreed architecture.

<details>
<summary>日本語</summary>

# プロダクトの価値：情報のつながりから変化に気づく

Lensがなぜ存在し、何を提供したいかを継続して説明する文書であり、実装計画や
提供済み機能の主張ではない。強みと有用性は、今後検証する仮説である。

## 課題と目指す成果

最初の利用者は、企業や業界に関心があり、比較の仕方を学んでいる個人である。
個々の発表に触れていても、それらの関係や、自分が追う企業にとっての意味まで
分かるとは限らない。繰り返し資料を検索するだけでは、情報をつなぐ作業は利用者に残る。

Lensは情報を収集・集約し、何を検索するかを先に決めなくても、関係する変化に
気づけるようにする。成果は、投資候補や保有先を再検討し、次に何を調べるかを
判断するきっかけを得ることである。理解や学びはその成果を支えるが、それだけを
プロダクトの目的とはしない。

## 価値と強みの仮説

> Lensは、関心のある企業と関連領域の情報を結びつけ、検索を始める前に、
> 変化の背景に気づける根拠と問いを届ける。その気づきが投資先を再検討する
> きっかけになる。

強みの仮説は、自分の関心に沿って、情報同士の関係・違い・矛盾が見えるように
集約することである。収集量、保存期間、読みやすい要約だけではこの価値を示せない。
検索は気づいた後の調査を支えるもので、最終的な成果の中心には置かない。

利用者が既に投資上の前提を持っている必要はない。同一企業の定点観測から違いに
気づくことを入口とし、長期的には企業・業界をまたぐ兆しを結びつける。
比較を通じて稼ぎ方や収益性の違いを理解できることも役立つが、金融教育だけを
プロダクト全体の定義にはしない。

## 範囲と責任

- 利用者の関心に応じて情報源に優先度を持たせる。初期は、予定する収集が
  発信元に認められ、利用者も収集対象として承認した情報源に限る。発信元の許可と
  利用者の承認は別の条件であり、アプリ内の承認フローの提案ではない。
- 選んだ企業・テーマを起点に、顧客・競合・取引先などの関連領域へ注意を広げる。
  収集の境界は同じ条件に従う。
- 初期は投資先の再検討を支える。将来は採用・業種の変化、新規・既存ビジネスの
  機会や変化にも広げる。
- 推薦するのは調べる価値のある論点であり、売買する投資先ではない。初期のLensは
  根拠のある関係と確かめるべき問いを示すところまでを担う。影響の評価と投資判断は
  利用者が行う。
- 推測的なつながりより、根拠を確かめられる気づきを優先する。観測事実と解釈を
  分ける。株価の動きを扱う場合も、関係があることだけでは因果関係の証明にならない。

## 具体的な場面

議論ではAI関連株の下落とその背景を例にした。特定の市場イベントを検証した説明ではない。
欲しい価値は、企業発表や業界動向を自分が追う企業に結びつけ、根拠と問いを通じて
背景を理解できることである。株価が下がったという既知の情報を繰り返すだけでは足りない。
下落の予測や取引の指示は、初期の責任範囲ではない。

## 既存Lensとの関係

LensはCollect → Preserve → Search → Discoverを掲げる。
[README](../../README.md)はアプリと使い方の入口とし、[GitHub Issue](https://github.com/9renpoto/lens/issues)で
リリース境界と将来の発見の実験を追跡する。今回の方向性は、発見を新しい目標として
発明したものではなく、そこで届けたい価値を具体化するものである。

| 観点 | 既存の定義・区切り | 今回重視する価値 |
| --- | --- | --- |
| 起点 | 資料の検索、後続で保存検索の監視 | 検索語を考える前に関係する気づきが届く |
| 届く情報 | 検索への一致、新たに公開された一致資料 | 自分の関心に関係する、根拠のあるつながりや違い |
| 利用者の成果 | 資料を見つけ原本を確かめる | 変化の背景を理解し投資先を再検討する |
| 注意の向け先 | 選んだ対象・情報源・検索条件 | 関心に沿った優先度と関連領域への広がり |
| 価値の証拠 | 検索・原本照合を実行し有用性を議論する | 自分では結びつけられず、調べたいと思える関係への気づき |

Lensは[検証手順](../reference/earnings-value-validation.md)を通じて、1社の
上限付き手動収集、日本語検索、正確な原本照合を提供する。保存資料を確かめるための
操作であり、それだけでは今回の発見価値を証明しない。

RSS公開の設計では、保存した検証対象企業の決算情報を、既存の生成済み表題・
抽出本文の全文・保存原本リンクを使って取得可能にする。
[ADR 0014](../adr/0014-publish-retained-earnings-through-rss.md)に、手動候補作成や
人間による公開対象の選別を含めない境界を記録する。実装済みの出力と読み取り専用の
購読側検証は[RSS参照資料](../reference/earnings-feed.md)に記載する。
[#185](https://github.com/9renpoto/lens/issues/185)と
[#186](https://github.com/9renpoto/lens/issues/186)でリリース境界と検証証跡を追跡する。
実際の保存済み結果を読むことで価値や不足を議論できるようにする。RSS公開だけで
有用性や自動的な発見を実証するものではない。

保存検索への一致は、保持した検索条件を満たす資料を見つけるものである。
それだけでは、プロダクト価値の仮説の中心である関係や調査の問いを提供できない。

既存の[分析根拠の保持#50](https://github.com/9renpoto/lens/issues/50)と
[一次根拠のレビュー#53](https://github.com/9renpoto/lens/issues/53)は根拠の確認を
支える方向だが、発見エンジンが実装済みであるとは主張していない。
発信元の条件確認と利用者による情報源の選定は、
[ADR 0007](../adr/0007-register-pilot-sources-through-an-interface.md)とも整合する。

## 成功・失敗とレビュー論点

最初に示したい価値は気づきの質であり、利用者が「自分ではつなげられなかった。
これは調べたい」と言えること。最終的な成果は、理由のある次の行動や投資先の
再検討であり、面白い問いだけでは全体の成果を示したことにはならない。
これらは定性的な仮説であり、測定結果や数値によるリリース条件ではない。

既知の情報の言い換えに留まる場合、読みやすくても中心の価値仮説を満たさない。
新しいつながりにも、自分の関心との関連と確認できる根拠が必要である。

レビューでは次を確認する。

- 課題と目指す成果が、有用で一貫したプロダクトを表しているか。
- 自分の関心に情報を結びつけることが、検索・要約・保存検索の通知を超える
  強みになり得るか。差別化はまだ実証されていない。
- 初期の責任範囲として、根拠のある関係の提示と利用者の判断の境界が明確か。
- 実装済みの挙動、公開設計、プロダクト価値の仮説の違いが十分明確か。

自動収集の方法、分析手法、RSS公開の境界を超える配信、通知頻度、UIは別途判断する。
この説明文書ではそれらの実装を選定せず、範囲はリリースIssue、合意済みの構成はADRを参照する。

</details>
