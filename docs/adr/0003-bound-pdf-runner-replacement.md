---
status: accepted
---

# Preserve the PDF execution boundary when removing Python

Issue: [#91](https://github.com/9renpoto/lens/issues/91). Review date: 2026-09-28.
Reviewed source: `361e1fe6b192a5a23297c596c0032a79302ad0c0` (includes merged PR #89).
This is an accepted implementation design, not an implemented or benchmark-validated replacement.

## Decision and value

Use a small C11/POSIX Linux helper invoked through an Erlang Port. It owns
Poppler startup, pre-exec limits, deadlines, wait and process-group cleanup.
The Elixir adapter owns a private directory, bounded result parsing and the
existing `PDFExtractor.extract/2` interface. Retaining Python remains the
fallback if the implementation or release gates fail. No speed or image-size
benefit has yet been measured.
This refactor is not a prerequisite for collection, API delivery, or pilot verification
(#71, #73, #74); those tasks can use the existing runner.

Keep Poppler and `Lens.Earnings.PDFExtractor.extract/2` as the adapter boundary.
Do not change original, acquisition, release, extraction-attempt, search selection,
or retry semantics. No database migration is justified by this review.
Preserve extractor identity `Lens.Earnings.PDFExtractor` and Poppler's reported version;
the runner implementation is not a new business entity. If additional runner identity
is later required for reproducibility, propose that requirement separately before
changing persisted metadata or historical records.

## Findings requiring correction or an explicit boundary

`priv/pdf_runner.py` starts a new session and kills its process group after normal
exit and timeout. This covers descendants that remain in the group; it does not
establish containment of descendants that create another session/group, nor cleanup
after the runner itself is killed. The existing descendant test checks a normal fork,
not those cases. The replacement must preserve this baseline and document exclusions;
it must not claim a general sandbox. Broader containment would require a separate
infrastructure decision, not a domain redesign.

Limits are per-process address space/CPU and per-file size, not aggregate process-tree
memory/CPU/disk. `System.cmd` has no outer deadline for a stuck runner, and its captured
JSON is not bounded by the raw-text limit. The 8 MiB limit applies to extracted bytes,
not escaped JSON. The version probe has its own deadline. These are execution-layer
gaps to characterize at the first gate; preserve existing successful behavior and
record intentional hardening instead of silently changing failure semantics.

Do not map every resource signal to `timeout` or `output_limit`: the current runner
checks text-file overflow before nonzero exit, maps other extraction nonzero exits to
`unreadable`, and treats unsuccessful version probing as `extractor_unavailable`.
Missing output after a zero exit currently reaches `FileNotFoundError` and becomes
`extractor_unavailable`. Record such edge cases before deciding whether to preserve
or explicitly amend them. Public invalid options are rejected before an attempt;
the helper also returns `invalid_options` internally.

## Options and selection

| Option | Assessment |
| --- | --- |
| Keep Python | Proven baseline in repository tests; lowest migration cost; retains runtime dependency. |
| Plain Erlang Port / Elixir task | Useful transport, but insufficient evidence by itself for pre-exec resource limits and group cleanup. Killing a task or closing a port is not the acceptance proof. |
| Small C11/POSIX helper | **Selected.** Explicit OS limits, group cleanup and bounded file/status protocol outside BEAM; built in existing Debian builder with no new runtime package. Adds C source and ABI/build maintenance. |
| [erlexec 2.5.0](https://erlexec.hexdocs.pm/exec.html) | Maintained BSD-licensed C++ Port, argv execution and group kill, but documented options lack RLIMIT_AS/CPU/FSIZE/CORE. Its cgroup option is best-effort on permission failure. It would still need a limit-setting layer and add a larger dependency, so is not selected. |
| Shell utility chain | More dependencies and ambiguous signal/error composition; not preferred. |
| NIF inside BEAM | Not preferred for process supervision; native failures expand impact to the application VM. |

The [compatibility contract](../planning/v0.2/pdf-runner-contract.md) freezes the
failure matrix, phase limits, 256-byte status protocol with text/version files,
outer deadline, owner-death policy, Linux amd64 release target and benchmark
gate. The helper is a separate OS process, never an in-VM NIF. #93 must test
that Port cancellation actually causes group cleanup; if it cannot, an explicit
group-signal control path is required before Python removal. There is no
unrestricted fallback when the helper or required limits are unavailable.

## Evidence and consequences

Source inspection covered `priv/pdf_runner.py`, `lib/lens/earnings/pdf_extractor.ex`,
`processing.ex`, `extractions.ex`, `test/pdf_runner_test.py`, processing tests,
`Dockerfile`, CI and `docs/earnings-extraction.md`. Existing nine runner tests
passed in offline Linux x86_64; a disposable probe confirmed exact-size and
overflow precedence, missing output, malformed text and version failure.
No replacement implementation, benchmark or new regression suite was performed.

The [OTP 27 Port API](https://www.erlang.org/docs/27/apps/erts/erlang.html#open_port/2)
documents process transport; it is not evidence of this application's complete boundary.
Python documents [process-group signalling](https://docs.python.org/3/library/os.html#os.killpg)
and [per-process resource limits](https://docs.python.org/3/library/resource.html).
The gap assessment above is an inference from those APIs and the inspected code.
The [erlexec API](https://erlexec.hexdocs.pm/exec.html) documents its available
options and best-effort cgroup behavior; absence of RLIMIT options there is
an API-documentation observation, not a claim about every possible extension.

See the [compatibility contract](../planning/v0.2/pdf-runner-contract.md) for
requirements and stop conditions. #92 records the handoff to #93 and #94. Keep Python until replacement and release tests pass.
An optional ReportLab fixture-authoring tool may remain Python-based, but extraction,
routine CI and release verification must not depend on it.

<details>
<summary>日本語</summary>

# Python削除時もPDFの実行境界を維持する

対象は [#91](https://github.com/9renpoto/lens/issues/91)。2026-09-28に、PR #89を含む
`361e1fe6b192a5a23297c596c0032a79302ad0c0` を確認した。これは採用した実装設計であり、
置換の実装や性能検証が完了したという意味ではない。

## 判断と価値

小さいLinux用C11/POSIXヘルパーをErlang Portから呼び出す方式を選ぶ。
Poppler起動、実行前の上限、期限、wait、プロセス群終了はヘルパーが担当する。
Elixirアダプターは非公開ディレクトリ、有界の結果解析、既存の
`PDFExtractor.extract/2` を担当する。実装・releaseゲートを通らなければPythonを維持する。
速度・イメージサイズの改善は未計測。
#71・#73・#74の収集・API・パイロット検証の前提条件にはせず、既存ランナーを使える。

Popplerと `Lens.Earnings.PDFExtractor.extract/2` を境界に保ち、原本・取得・短信・
抽出試行・検索選択・再試行の意味を変えない。本検証からDB変更の必要性は認められない。
抽出器名 `Lens.Earnings.PDFExtractor` とPopplerの版を維持する。ランナーは新しい
業務エンティティではない。再現性のためにランナー識別も必要なら、保存メタデータや
過去履歴を変える前に別途要件を提案する。

## 修正または境界の明示が必要な点

`priv/pdf_runner.py` は新しいセッションを作り、通常終了とタイムアウトでその
プロセス群を終了する。同じ群に残る子孫は対象だが、別セッション・別群へ移った
子孫の隔離や、ランナー自体が強制終了した場合の後始末を保証しない。既存テストは
通常のforkを検証している。この水準を維持し、対象外を明記する。一般的なサンドボックス
とは呼ばない。広範な隔離は実行基盤の別判断であり、ドメインの再設計ではない。

アドレス空間・CPUはプロセス単位、サイズはファイル単位の制限であり、子孫全体の
メモリ・CPU・ディスク総量の上限ではない。`System.cmd` には停止したランナーへの
外側の期限がなく、取得するJSONの大きさも本文上限では制限されない。8 MiBは本文
バイト数であり、エスケープ後のJSONサイズではない。版確認には別の期限がある。
第1ゲートでこれらを分類し、正常動作を維持しながら強化点を明記する。

資源上限によるシグナルを一律に `timeout` や `output_limit` へ変えない。
現行は本文ファイルの上限超過を非ゼロ終了より先に判定し、その他の抽出非ゼロ終了は
`unreadable`、版確認の非ゼロ終了は `extractor_unavailable` とする。終了0で本文が
ない場合も `FileNotFoundError` により `extractor_unavailable` になる。
こうした端点を記録してから互換維持か明示的修正かを決める。公開操作の不正引数は
試行作成前に拒否され、ヘルパー内部にも `invalid_options` がある。

## 選択肢と判断

| 方式 | 評価 |
| --- | --- |
| Python維持 | リポジトリの既存テストがある基準。移行負担は最小だが依存は残る。 |
| Erlang Port / Elixir taskのみ | 通信には使えるが、実行前の資源制限と群終了の根拠には不足。task終了やport閉鎖だけでは合格にしない。 |
| 小さいC11/POSIXヘルパー | **選定。** BEAM外でOS制限・群終了を実行し、有界のファイル・状態通信を使う。既存Debian builderで作りruntimeパッケージは増やさないが、CソースとABI・ビルド保守が増える。 |
| [erlexec 2.5.0](https://erlexec.hexdocs.pm/exec.html) | BSDライセンスの保守中C++ Portで、argv実行と群終了がある。ただし文書化された設定にはRLIMIT_AS/CPU/FSIZE/COREがなく、cgroupは権限失敗時にbest-effort。別の制限層が要り依存も増えるため選ばない。 |
| シェルツールの連結 | 依存とシグナル・エラー合成の曖昧さが増えるため優先しない。 |
| BEAM内NIF | プロセス監督には優先しない。ネイティブ障害の影響がVMへ広がる。 |

[互換契約](../planning/v0.2/pdf-runner-contract.md)に失敗表、各段階の上限、
本文・版ファイルと256-byte状態通信、外側期限、呼出元終了、Linux amd64、測定ゲートを
定めた。ヘルパーは別OSプロセスでありBEAM内NIFではない。#93ではPort取消が実際に群を
終了するか試験し、不足ならPython削除前に明示的な群シグナル経路を追加する。
ヘルパーや必要上限が使えない場合に無制限実行へ切り替えない。

## 根拠と影響

`priv/pdf_runner.py`、`lib/lens/earnings/pdf_extractor.ex`、
`processing.ex`、`extractions.ex`、`test/pdf_runner_test.py`、processing tests、
`Dockerfile`、CI、`docs/earnings-extraction.md` を読んだ。Linux x86_64のoffline環境で既存ランナー9試験が成功し、
使い捨てprobeで本文上限・超過優先・本文なし・不正本文・版確認失敗を確認した。
置換実装、性能測定、新規回帰試験は行っていない。
[OTP 27 Port API](https://www.erlang.org/docs/27/apps/erts/erlang.html#open_port/2)は通信の説明であり、
アプリ全体の境界保証ではない。Pythonの[群シグナル](https://docs.python.org/3/library/os.html#os.killpg)と
[プロセス資源制限](https://docs.python.org/3/library/resource.html)も参照した。
上記の不足点はAPIとコードからの推論である。[erlexec API](https://erlexec.hexdocs.pm/exec.html)
には利用できる設定とbest-effortのcgroupが記載される。RLIMIT設定が文書化されて
いないという観察であり、あらゆる拡張が不可能という主張ではない。

[互換契約](../planning/v0.2/pdf-runner-contract.md)に要件・停止条件を示す。
#92に#93・#94への引継ぎを記録する。
置換とreleaseの検証が成功するまではPythonを残す。任意のReportLab固定データ生成器は
Pythonのままでもよいが、抽出・通常CI・release検証の依存にはしない。

</details>
