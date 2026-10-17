# Loop `github-pr-review` 設計: PR 初回レビューの自動化

**Status:** Draft(ビルダー確認・仕様レビュー・残リスク調査を反映済み。ユーザーの承認待ち)
**Date:** 2026-10-17
**Primary consumers:** 新規 loop `github-pr-review`(`on-loop-github-pr-review.yaml`)、`github` package の新規スキル `github-pr-review`、既存スキル `github-pr-revise`(小変更)、`loop-finalize` と `ci-loop-agent.yaml`(プラットフォーム変更)
**Related:** [Loop Engineering Design](../../explanation/loop-engineering/loop-engineering-design.md)、[Loop-Capable Skills](../../explanation/loop-engineering/loop-capable-skills.md)、[Loop Engineering Checklist](../../reference/loop-engineering-checklist.md)、[Loop `github-pr-revise` Workflow Design](../../explanation/loop-engineering/workflows/loop-github-pr-revise-workflow-design.md)、[Loop Write Target & Delivery Design](2026-07-23-loop-write-target-delivery-design.md)

> 注記: `docs/superpowers/specs/` の他の spec は英語のものもあるが、本 spec は依頼により日本語で記述する。

## 背景と課題

PR に対する品質チェックのうち、lint・フォーマット・シークレット検出などの機械的なものは CI とフックが担っている。一方、次の種類の違反は機械的に検出できず、人間のレビューに依存している。

- リポジトリのエージェント向けルール(`AGENTS.md`、`CLAUDE.md` など)を無視したコード
- ドメイン別レビューの基準(ID 付きの基準)に照らして品質が低く、差し戻すべき変更

PR 修正のループとして `github-pr-revise` は既にある。ただしこれは「人間が `@loop` を付けた指摘を実装する」役割であり、**最初のレビュー自体は自動化されていない**。

## ゴール

- PR の作成時(`opened` / `ready_for_review`)に、**1 回だけ**自動レビューを行う。
- ルールやレビュー基準に違反した変更を、**根拠の原文引用つき**で指摘する。
- 汎用のバグ(正しさ)を、**差分の行引用つき**で指摘する。
- 指摘のうち、人間が対応を決めたものを `pr-revise`(`@loop`)に引き継げる。

## 非ゴール

- 修正の実装(`pr-revise` の担当)。本 loop はソースコードを編集しない。
- 2 回目以降の自動レビュー(`synchronize` では起動しない)。
- 初期段階での PR のブロック(Request changes)。
- lint・フォーマット・シークレット検出の再実行(フックと CI が実行済み)。
- fork PR、draft PR、bot が作成した PR、loop が作成した PR のレビュー。
- 回答言語の LE 全体への導入([別課題](#別課題)。本 loop はその仕組みが入れば従う)。

## アンチゴール(技術的に動いても失敗とみなすもの)

- ルールにも基準にも根拠がない指摘。
- 「経緯なし」の指摘。つまり、PR の意図や関連する Issue / spec を確認せずに出した指摘。
- PR がもともと持っていた問題(Pre-existing)の指摘。
- 同じ指摘の繰り返しや、nit の大量投稿。
- PR 自身が書き換えたルール・基準・設定でレビューが行われること。

## 設計原則

1. **根拠は機械的に検証できる形で出す。** 引用したルールが base に実在し原文が一致すること、指摘した行が差分に含まれることを、投稿前にスクリプトで検証する。LLM の判断だけに頼らない。
2. **ルール・レビュー基準・エージェント設定は、PR の base で固定する。** PR の head のファイルは「レビュー対象のデータ」としてのみ読み、実行も設定としての読み込みもしない。

## 調査: 外部事例

| パターン                        | 代表例                                                                                                               | 要点                                                                                                                            |
| ------------------------------- | -------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| ルール準拠の引用つき指摘        | [Anthropic `/code-review`](https://github.com/anthropics/claude-code/blob/main/plugins/code-review/README.md)        | ルールが CLAUDE.md に明示されているかを検証し、原文と SHA 付き行リンクを添える。信頼度 0〜100 で採点し、80 未満は捨てる         |
| 「指摘しないこと」の明記        | [Cloudflare](https://blog.cloudflare.com/ai-code-review/)                                                            | 各レビュアーのプロンプトに "What NOT to Flag" を書く。判定役が重複と憶測を落とす。1 レビューあたり約 1.2 件                     |
| 重大度と Pre-existing の区別    | [Anthropic のチーム](https://claude.dev/blog/solving-code-review-at-anthropic/)                                      | Important / Nit / Pre-existing のタグ。反応(直した・誤りと返された・意図的と返された)でノイズを測る                             |
| 再レビューの収束                | 同上                                                                                                                 | 3 回で打ち切る上限、差分のみの再レビュー、同じ指摘の再掲禁止。最初の 1 回だけ自動にして以降を人間に任せる本設計の方針と整合する |
| コメントのみ / ブロックの両系統 | [gh-aw](https://github.github.com/gh-aw/gallery/automated-pr-review/)(COMMENT のみ)、Cloudflare(重大でブロック)      | ブロックには解除の仕組み(再レビューで承認を取り消し直す等)が前提になる                                                          |
| ルールの読み込み元              | [Copilot コードレビュー](https://docs.github.com/copilot/using-github-copilot/code-review/using-copilot-code-review) | ルールを PR の head から読む。PR がルールを書き換えて弱められるため、本設計では base から読む                                   |

## 決定事項

| #   | 決定                                                                                                                                                                                                                                                                                                                                                                                 | 理由                                                                                                                                                                                                                                                                                                                           |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| D1  | 新規 loop `github-pr-review` を **L2** で作る。ソースは編集せず、レビュー案を `write_target: report` のレポートファイルに書く                                                                                                                                                                                                                                                        | L1 は Checker を持たず(LE の定義: 読み取り専用の 1 セッション)、`agent-l1` ジョブには `pull-requests: write` もない。L2 でもファイル変更がないと Checker は走らない(`loop.sh` の `NO_CHANGES_VERDICT`)ため、レポートファイルを変更として Checker に渡す。LE の「新しいパターンは L1 から」の原則からは外れる(ユーザー確認済み) |
| D2  | トリガーは `pull_request_target: [opened, ready_for_review]` と `workflow_dispatch`。`synchronize` は含めない                                                                                                                                                                                                                                                                        | 初回のみ自動。以降は人間が `@loop` で `pr-revise` に渡す。`pull_request_target` はワークフロー定義と checkout が base になる(D5)                                                                                                                                                                                               |
| D3  | **最初は `COMMENT` のレビューのみ**。Request changes は評価期間後に段階導入する                                                                                                                                                                                                                                                                                                      | bot の Request changes は、1 回きりの設計では自動解除できず、誤指摘のコストが大きい                                                                                                                                                                                                                                            |
| D4  | 指摘は **根拠つきのものだけ** 出す。根拠は次の 3 種類に限る: (a) エージェント向けルールファイルの原文、(b) ドメイン別レビューの基準(`references/category-*.md` の ID 付き項目)の原文、(c) バグの場合は差分の行と、問題が起きる具体的な入力・状態                                                                                                                                     | アンチゴール「根拠がない指摘」を防ぐ。(b) を含めることで「品質が劣るコード」も根拠つきで指摘できる                                                                                                                                                                                                                             |
| D5  | ルール、レビュー基準、スキル、エージェント設定(`.claude/settings.json` 等)は **PR の base ブランチ** から読む。`pull_request_target` では `GITHUB_SHA` / `GITHUB_REF_NAME` が base ブランチを指し、`ci-loop-caller-entity` はそれを作業ツリーの起点(`from.ref`)にする。checkout は base を明示し、head のコードは実行しない。差分と head の内容は `gh pr diff` / `gh api` で取得する | PR がルールや hooks を書き換えて、レビューを回避したりトークンのある環境でコードを実行したりすることを防ぐ。前例: `on-loop-state-promote.yaml`(`pull_request_target` + base ref を明示した checkout)                                                                                                                           |
| D6  | `.apm` 側のスキル `github-pr-review` は、エンジン非依存かつリポジトリ非依存で書く。特定エンジンの組み込みスキル(`/code-review`)や、このリポジトリ固有のパス・ルールは書かない                                                                                                                                                                                                        | `.apm/packages/**` は他リポジトリに配布されるため、可搬な表現しか書けない(`CLAUDE.md`)。固有の事項は on-loop 側の `agent_maker_instructions` に置く                                                                                                                                                                            |
| D7  | Claude エンジンでは、on-loop 側の指示で `/code-review` を汎用のバグ検出に併用する。`--comment` は付けない。結果は材料としてのみ使い、D4 の形式にできないものは捨て、スキルの指摘と重複するものは 1 件にまとめる                                                                                                                                                                      | ローカルで非対話実行(`claude -p "/code-review ..."`)が動くことを確認済み。`--comment` を付けると、マーカーも Meta もない別のコメントが投稿される                                                                                                                                                                               |
| D8  | 対象外: fork PR、draft PR、bot が作成した PR(renovate 等)、`no-loop` ラベル、`loop-automation` ラベル(loop が作成した PR)                                                                                                                                                                                                                                                            | `ci-loop-caller-entity` には `pr_exclude` がないため、on-loop の `if:` と detect でラベルを判定する(D21)。loop の PR は Checker を通過済み。評価期間の後に対象化を再検討する(ユーザー確認済み)                                                                                                                                 |
| D9  | 冪等性: マーカー付きのレビューが PR に既にあれば、スキップする                                                                                                                                                                                                                                                                                                                       | draft と ready の往復で `ready_for_review` が再発火したときや、手動再実行での重複投稿を防ぐ                                                                                                                                                                                                                                    |
| D10 | 重大度は `Critical` / `Warning` / `Suggestion` の 3 段階                                                                                                                                                                                                                                                                                                                             | Cloudflare / Anthropic の分類を踏襲                                                                                                                                                                                                                                                                                            |
| D11 | PR の意図確認(PR 本文、リンクされた Issue、関連 spec)を、レビューの前提として必須にする                                                                                                                                                                                                                                                                                              | アンチゴール「経緯なし」の指摘を防ぐ                                                                                                                                                                                                                                                                                           |
| D12 | `pr-revise` への引き継ぎは、**人間**が指摘に `@loop` を付けて返信またはコメントする。指摘には通し番号を付ける                                                                                                                                                                                                                                                                        | `pr-revise` は bot のコメントに反応しない。人間が対応を決める設計                                                                                                                                                                                                                                                              |
| D13 | `workflow_dispatch` には `pr_number` と `force`(既定 `false`)を設ける。`force: true` のときだけ D9 のマーカー判定を無視する                                                                                                                                                                                                                                                          | 実機確認、取りこぼし(予算超過・失敗)の再実行、再レビューのため                                                                                                                                                                                                                                                                 |
| D14 | Pre-existing の問題は指摘しない                                                                                                                                                                                                                                                                                                                                                      | 初回レビューは、PR の差分が原因の問題だけを扱う(ユーザー確認済み)                                                                                                                                                                                                                                                              |
| D15 | レビューの投稿は、他の `on-loop-*` と同じ App トークンで `pulls/<n>/reviews` に `COMMENT` として行う。投稿は Checker の APPROVE 後に finalize の `domain_persistence_script` が行う                                                                                                                                                                                                  | maker が投稿すると、Checker の REJECT 前に投稿済みになり、再試行で重複する。finalize は `VERDICT` を受け取る                                                                                                                                                                                                                   |
| D16 | レビュー本文に「確認した前提」の節(見出しは `### Premises checked`)を設け、PR の意図の確認結果を書く。Checker はこの節で APPROVE 条件を検証する                                                                                                                                                                                                                                      | Checker は存在するものしか検証できない                                                                                                                                                                                                                                                                                         |
| D17 | 差分に含まれる行への指摘は**インラインコメント**(`path` / `line` / `side`、範囲は `start_line`)で付ける。差分に含まれない箇所への指摘は、レビュー本文に書く                                                                                                                                                                                                                          | 人間が行に返信して `@loop` を付けると、`pr-revise` が `path` / `line` / `diff_hunk` を受け取れる                                                                                                                                                                                                                               |
| D18 | Meta は既存の共通ブロック(`.github/actions/lib/loop/loop_meta.sh` の `build_loop_meta_block`、折りたたみの `Field` / `Value` 表)に統一する。Meta の追記はプラットフォーム(`finalize-l2`)が行う。L1 の `entity_meta.sh` と同じく、マーカー付きの PR レビューを探して本文に追記する(P2)                                                                                                | PR 本文、`loop-notify-pr`、Issue コメントと出力の統一感を保つ(ユーザー確認済み)。`domain_persistence_script` には使用量・エンジン・実行 URL が渡らず、配布先ではスキルから `loop_meta.sh` を読み込めないため、スキル側では描画しない                                                                                           |
| D19 | `pr-revise` に「PR 全体の文脈を読む」手順を加える。インラインへの返信なら、そのコード行とスレッド全体(親コメントを含む)を読む。それ以外なら、PR 本文とコメント全体を読む                                                                                                                                                                                                             | 人間が「@loop 対応して」とだけ返信した場合、現状は親コメント(bot の指摘本文)が渡らず、何を直すか分からない                                                                                                                                                                                                                     |
| D21 | caller は `ci-loop-caller-entity` を使う                                                                                                                                                                                                                                                                                                                                             | L2、`domain_persistence_script`、`write_target` に対応済み(調査済み)。`pr_exclude` と `report_file` の入力はないため、除外は on-loop の `if:` と detect で、レポートのパスは detect の JSON(`result.report_path`)で渡す                                                                                                        |
| D22 | プラットフォーム変更 P1〜P3([プラットフォーム変更](#プラットフォーム変更)を参照)を本 spec の範囲に含める                                                                                                                                                                                                                                                                             | 調査の結果、現状の `loop-finalize` では L2 + `delivery: none` が成立しないため(ユーザー確認済み)                                                                                                                                                                                                                               |
| D23 | スキル本体は英語で書く。投稿は、見出し・フィールド名・固定の案内文を英語、エージェントが書く文面を回答言語にする。回答言語は `## Constraints` の `response_language` > PR の言語 > 英語の順で決める                                                                                                                                                                                  | 日本語・韓国語など、さまざまな言語の利用者を想定する。固定部分を英語にすることで、出力の形をそろえ、機械でも読めるようにする(ユーザー確認済み)                                                                                                                                                                                 |
| D24 | GitHub に投稿する文面では、リンクできるものは極力リンクにする。行はコミット SHA で固定した `blob/{full-sha}/{path}#L<start>-L<end>`、ルールの引用は base の SHA、差分の行は head の SHA を使う。バッククォートのパスも、実在するファイルなら ``[`path`](url)`` にする。PR / Issue は `#N`、コミットは `/commit/{sha}`                                                                | 読み手がすぐ根拠に飛べるようにする。ブランチを指すと後のコミットで行がずれる。既存スキルの統一は[別課題](#別課題)とし、本 loop は先に従う(ユーザー確認済み)                                                                                                                                                                    |
| D20 | エージェント向けルールファイルのパスはスキルに列挙しない。スキルには「変更されたファイルを、base をチェックアウトした作業ツリーで開いて読む」と書き、各エンジンのルール自動読み込みに任せる                                                                                                                                                                                          | ルートの `CLAUDE.md` は自動で読まれるが、ネストした `CLAUDE.md` やパス限定のルール(Cursor の globs も同様)は、そのファイルを読んだときに読み込まれる。差分だけを読むと読み込まれない                                                                                                                                           |

## アーキテクチャ

### 全体の流れ

1. `pull_request_target` で起動し、`if:` ゲートと detect で対象外を除く(D8)。
2. Detect(`detect_pr_review.sh`)が機械的な事実を出す。マーカーがあればスキップする(D9、D13)。
3. Maker(L2、base の作業ツリー)がレビュー案をレポートファイルに書く。
4. Checker(`loop-verifier`)がレポートファイルを検証する。REJECT なら maker が書き直す(最大 `agent_loop_max_attempts` 回)。
5. APPROVE なら、finalize の `domain_persistence_script`(`post_review.sh`)が機械的な検証を行い、レビューを投稿する。REJECT のまま終われば投稿しない。
6. `finalize-l2` が Meta を追記し(P3)、作業ブランチを削除する(P2)。

### プラットフォーム変更

調査で判明した、本 loop の前提となる変更。いずれも配布物(`.github/actions/**`、`ci-*`)の変更で、Bats テストと SHA ピンの更新を伴う(`.github/workflows/CLAUDE.md`)。

| #   | 対象                                                                             | 現状                                                                                                                                                                                                                                                    | 変更                                                                                                 |
| --- | -------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| P1  | `loop-finalize`(「Push to Target Branch」)                                       | 条件が `finalize_strategy != 'open_pr'` のため、`delivery: none`(`finalize: none`)でも APPROVE 時に作業ブランチを `to.branch` にマージして push する(`action.yml:248-257`)。現行の L2 loop に `delivery: none` を使うものはなく、表面化していない不具合 | `finalize_strategy` が `none` のときは push しない                                                   |
| P2  | `loop-finalize`(作業ブランチの削除)                                              | 削除は REJECT のときのみ(`should_delete_rejected_branch.sh`)。P1 の後は、APPROVE + `none` で作業ブランチが残る                                                                                                                                          | `finalize_strategy` が `none` のときは、`domain_persistence_script` の実行後に作業ブランチを削除する |
| P3  | `ci-loop-agent.yaml` の `finalize-l2`、`.github/actions/lib/loop/entity_meta.sh` | Meta の追記は L1 の Issue コメントのみ対応                                                                                                                                                                                                              | マーカー付きの PR レビュー本文に Meta を追記する処理を追加し、`finalize-l2` から呼ぶ(D18)            |

`domain_persistence_script` は push より前に実行され(`action.yml:233`)、作業ブランチは `loop-execute` の時点で push 済み(`loop-execute/lib/push.sh`)のため、`post_review.sh` は `git fetch origin "$EXECUTE_BRANCH"` でレポートを読める。

### 層ごとの責務

| 層                                            | 責務                                                                                                                                                                                |
| --------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `on-loop-github-pr-review.yaml`               | トリガー、`if:` ゲートによる除外、権限、このリポジトリ固有の除外対象、エンジン固有の指示(D7)                                                                                        |
| `detect_pr_review.sh`                         | 機械的な事実のみ: PR 番号、base/head の SHA、変更ファイル一覧、投稿済みマーカーの有無、`force`、除外ラベルの有無、レポートのパス(`result.report_path`)。`result.handoff_key` も出す |
| スキル `github-pr-review`                     | レビューの手順、指摘の形式、「指摘しないこと」のリスト。エンジン非依存・リポジトリ非依存                                                                                            |
| レポートファイル                              | maker の出力(レビュー案の JSON)。Checker の検証対象、かつ投稿スクリプトの入力                                                                                                       |
| `agent_checker_instructions`                  | Checker の基準([Checker の基準](#checker-の基準)を参照)                                                                                                                             |
| `post_review.sh`(`domain_persistence_script`) | `VERDICT` が APPROVE のときだけ、作業ブランチからレポートを読み、根拠の機械的検証(設計原則 1)を行ってから投稿する。検証に落ちた指摘は捨て、捨てた件数を本文に書く                   |
| `finalize-l2`(P3)                             | 投稿されたレビューに Meta を追記する                                                                                                                                                |

Detect はセマンティックな指摘を出さない(チェックリストの「Detect vs Execute」)。

### スキル `github-pr-review` の手順

1. detect JSON を読む。`skip: true` なら理由を報告して終了する。
2. PR の意図を確認する: PR 本文、リンクされた Issue、関連する spec(D11)。
3. 変更されたファイルを、base の作業ツリーで開いて読む(D20)。head の内容は `gh pr diff` / `gh api` で読む。
4. 適用するルールを集める: エンジンが読み込んだエージェント向けルールと、変更ファイルの種類に対応するドメイン別レビューの基準(D4 (b))。
5. 指摘を、D4 の 3 種類の根拠に限って作る。Pre-existing は除く(D14)。
6. 根拠を示せない指摘、信頼度が低い指摘を捨てる。
7. レビュー案をレポートファイルに書く。投稿はしない(D15)。

### レポートファイル(レビュー案)

パスは detect が `result.report_path` で渡す(例: `.loop/review/pr-<n>.json`)。形式(案):

```json
{
  "pr_number": 123,
  "head_sha": "<full sha>",
  "base_sha": "<full sha>",
  "response_language": "ja",
  "premises": { "pr_body": "checked", "linked": ["#120"] },
  "summary": "<レビュー本文の冒頭(回答言語)>",
  "findings": [
    {
      "id": 1,
      "severity": "Critical",
      "title": "<一行の要約>",
      "evidence": { "kind": "rule", "path": "<base のファイルパス>", "quote": "<原文>" },
      "location": { "path": "<path>", "line": 42, "start_line": 40, "side": "RIGHT", "in_diff": true },
      "impact": "<放置した場合に何が起きるか>"
    }
  ]
}
```

`evidence.kind` は `rule` / `criteria` / `bug` のいずれか。`rule` と `criteria` は `path` と `quote` が必須で、`post_review.sh` が base の該当ファイルに `quote` が含まれることを検証する。`location.in_diff: true` の指摘は、行が差分に含まれることを検証する。

### 投稿の形式

スキル本体(`SKILL.md`、`references/`、`assets/`)は英語で書く。投稿の言語は次の規則に従う(D23)。

| 部分                                                                     | 言語                         |
| ------------------------------------------------------------------------ | ---------------------------- |
| 見出し、フィールド名、重大度、固定の案内文、マーカー、Meta               | 英語(テンプレートの固定表記) |
| エージェントが書く文面(要約、影響、確認した前提の内容、レビューの冒頭文) | 回答言語                     |
| 引用(ルール原文)、コード、パス、識別子、コマンド                         | 原文のまま                   |

回答言語は次の順で決める。

1. `## Constraints` の `response_language`(LE 共通化の[別課題](#別課題)で導入。導入後は MUST として従う)
2. PR のタイトルと本文の言語
3. 判定できない場合は英語

レビュー本文(`COMMENT`)。`<...>` はエージェントが回答言語で書く部分:

```markdown
<!-- github-pr-review:v1 -->

## Code review

Findings: N (Critical: a / Warning: b / Suggestion: c)

<one or two sentences: what the PR does and the overall assessment. When there are no findings, say so explicitly.>

### Premises checked

- PR body: <checked | none>
- Linked Issue / spec: <#number or path | none>

### Findings

1. **[Critical]** <one-line summary> — inline: [`<path>#L<line>`](https://github.com/<owner>/<repo>/pull/<n>/files)
2. **[Warning]** <one-line summary>
   - Evidence: [`<path>#L<n>`](https://github.com/<owner>/<repo>/blob/<base-sha>/<path>#L<n>) — "<verbatim quote>"
   - Location: https://github.com/<owner>/<repo>/blob/<head-sha>/<path>#L<start>-L<end>
   - Impact: <what happens if left as is>

<Meta block (D18)>
```

インラインコメント(差分内の指摘。本文の番号と対応させる):

```markdown
**#1 [Critical]** <one-line summary>

- Evidence: [`<path>#L<n>`](https://github.com/<owner>/<repo>/blob/<base-sha>/<path>#L<n>) — "<verbatim quote>"
- Impact: <what happens if left as is>

To request a fix, reply to this comment with `@loop`.
```

本文の一覧では、インラインの指摘は要約と位置だけを書き、詳細はインラインに置く。差分外の指摘は、本文に詳細を書く。実装時は、上記を `assets/review-body-template.md` と `assets/inline-comment-template.md` に置き、既存スキルの `assets/pr-body-template.md` と同じく、冒頭の HTML コメントに読み込み時機と言語規則、各節に GOOD / BAD の例を書く。

### 「指摘しないこと」(スキルに書く、可搬な表現のみ)

- 生成ファイル、ロックファイル、ツールが再生成した差分
- フックと CI が検出する項目(lint、フォーマット、シークレット)
- ルールにも基準にも明記されていない好み
- 理論上のリスクで、成立に非現実的な前提が必要なもの
- PR がもともと持っていた問題(D14)

このリポジトリ固有の除外(例: `apm install` の同期先、`apm.lock.yaml`)は、on-loop 側の `agent_maker_instructions` に書く(D6)。

### Checker の基準

APPROVE の条件(すべて満たすこと):

1. すべての指摘に D4 の根拠がある
2. 指摘が「指摘しないこと」のリストに該当しない
3. 「確認した前提」(レポートの `premises`、本文の `### Premises checked`)に PR の意図の確認結果が書かれている
4. レポートファイル以外のファイルが変更されていない

REJECT の条件(いずれかに該当):

- 根拠のない指摘、または実在しないルール・基準を引用した指摘
- 差分に含まれない行を `in_diff: true` とした指摘
- head から読んだルール・基準を根拠にした指摘
- レポートファイル以外のファイル変更

### Caller `on-loop-github-pr-review.yaml`(骨子)

- `on: pull_request_target: types: [opened, ready_for_review]`、`workflow_dispatch`(`pr_number`、`force`)
- checkout は base を明示する。head のコードは実行しない(D5)
- `permissions`: `contents: write`(`.loop/` の状態を push するため)、`pull-requests: write`、その他は他の `on-loop-*` に合わせる
- `concurrency`: PR 番号ごとに直列化、`cancel-in-progress: false`
- 除外(D8): `if:` ゲートで fork、draft、bot 作成、`no-loop` / `loop-automation` ラベルを除く。`workflow_dispatch` の経路は detect が同じ条件で判定する
- `uses: ./.github/workflows/ci-loop-caller-entity.yaml`(D21)
- `level: L2`、`may_edit: true`、`write_target: report`、`delivery: none`
- `agent_maker_skill_name: github-pr-review`、`agent_checker_skill_name: loop-verifier`
- `domain_persistence_script: .agents/skills/github-pr-review/scripts/post_review.sh`
- `agent_allowed_tools`: `gh pr view`、`gh pr diff`、`gh api`(読み取り用)
- `agent_maker_instructions`: D7 の `/code-review` の使い方、このリポジトリ固有の除外対象

## 影響範囲と変更チェックリスト

新規:

- `.apm/packages/github/.apm/skills/github-pr-review/`(`SKILL.md`、`references/`、`scripts/detect_pr_review.sh`、`scripts/post_review.sh`、`evals/`)
- `.github/workflows/on-loop-github-pr-review.yaml`
- `docs/explanation/loop-engineering/workflows/loop-github-pr-review-workflow-design.md`

更新(プラットフォーム、D22):

- `.github/actions/loop-finalize/action.yml` と `lib/`(P1、P2)
- `.github/actions/lib/loop/entity_meta.sh`(P3)と `.github/workflows/ci-loop-agent.yaml` の `finalize-l2`
- リリース時の SHA ピン更新(`ci-*`、`example/`)。dogfood 期間は `on-*` からローカルパスで参照できる

更新(その他):

- `.apm/packages/github/.apm/skills/github-pr-revise/`(D19: PR 全体の文脈を読む手順。`detect_pr_revise.sh` で親コメントを渡すかは実装時に決める)
- `docs/reference/loop-engineering-checklist.md` に基づく項目(loop 一覧、`loop-capable-skills.md`、`loop-caller-inputs-reference.md` 等)
- `apm install` による同期先(`.agents/`、`.claude/` 等)の再生成とコミット
- 権限を追加する場合は、`CLAUDE.md` の Permission parity に従い 4 ファイルを同時に更新する

テスト・検証(`AGENTS.md` の test-first に従う):

- `detect_pr_review.sh` の Bats テスト(skip 条件、マーカー判定、`force`)
- `post_review.sh` の Bats テスト(APPROVE 以外で投稿しない、引用の不一致で指摘を捨てる、差分外の行を本文に回す、Meta の付与)
- `pr-revise` の変更に対応する Bats / evals の更新
- P1: `finalize: none` で push しないこと、`open_pr` / `push` / `push_head` の挙動が変わらないことの Bats テスト
- P2: `none` + APPROVE で作業ブランチを削除し、REJECT の既存挙動が変わらないことの Bats テスト
- P3: PR レビューへの Meta 追記(マーカーがない場合は何もしない、追記済みなら二重に追記しない)の Bats テスト
- スキルの `evals/`(`basic`、`skip-detect`、ルール違反の引用、根拠なし指摘の抑制、Pre-existing の除外)
- Actions 上の実機確認: `workflow_dispatch` で検証用の PR に対して実行し、投稿内容を確認する

## リスクと緩和

| リスク                                                                    | 緩和                                                                                                                              |
| ------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| 誤指摘で PR がノイズだらけになる                                          | D4、Checker、`post_review.sh` の機械的検証。評価期間で、直された/誤りと返された割合を測る                                         |
| PR がルールや設定を書き換えてレビューを回避する、またはコードを実行させる | D5: `pull_request_target` と base の checkout。head はデータとしてのみ読む                                                        |
| `pull_request_target` によるトークンの露出                                | head のコードを checkout・実行しない。fork PR は除外(D8)。`zizmor` の `dangerous-triggers` は理由を書いて無視する(前例に合わせる) |
| PR 本文・コメントによるプロンプトインジェクション                         | 読み取りのツール許可のみ。投稿は検証済みのレポートからスクリプトが行う                                                            |
| 大きな差分で、見落としや高コストが発生する                                | 生成物の除外。初期は変更量による段階分けを行わない(未決事項)                                                                      |
| `/code-review` が Actions 上で動かない                                    | Actions 上の実機確認を最初の検証項目にする。動かない場合は D4 のスキルのみで運用する                                              |
| 予算超過や失敗で、初回レビューが取りこぼされる                            | `workflow_dispatch` で再実行できる(D13)                                                                                           |
| P1 の変更が、`delivery: none` を使う他の loop の挙動を変える              | 現行で L2 + `none` の loop はない(調査済み)。`open_pr` / `push` / `push_head` は変更しないことを Bats で固定する                  |
| CLI のバージョンが `latest` で、挙動が変わる                              | 既存の `loop-install-cli` の設定に従う。変更はスコープ外                                                                          |

## 段階導入

1. **第 1 段階(本 spec の実装範囲)**: `COMMENT` のみ。`workflow_dispatch` で実機確認してから、`pull_request_target` トリガーを有効にする。
2. **評価期間(数週間)**: 指摘ごとに「直された/誤りと返された/意図的と返された」を記録し、ノイズ率を確認する。
3. **第 2 段階(本 spec の範囲外、別 spec)**: 根拠を引用できる `Critical` のみ、Request changes にする。解除の仕組みは、その spec で設計する。

## 別課題

本 spec の範囲外とし、別の spec / Issue で扱う。

1. **回答言語の LE 共通化。** caller 入力(例: `response_language`)で回答言語を指定し、`## Constraints` に MUST として注入する。テンプレートのうちエージェントが書く部分はその言語で書き、固定のキーと見出しは英語のままにする。全ループのコメント・PR 本文に適用する。
2. **GitHub リンク規則の統一。** 各スキルの `references/category-pr-body-links.md` は内容がばらばら(8 ファイル中 3 つだけ同一)で、行番号リンクの規則がない。D24 の規則を全スキル(`github-issue-triage`、`github-pr-body` を含む)に共通化し、`check_loop_pr_body_contract.sh` で共通部分の一致を検査する。
3. **L1 の checker 入力の扱い。** `agent-l1` は checker を実行しないが、`ci-loop-caller-entity` は `agent_checker_instructions` を必須にしている。そのため `on-loop-github-issue-triage.yaml`(L1)の APPROVE/REJECT 基準は実行されない。L1 で checker 入力が渡されたら警告を出し、L1 では任意入力にする案。

## 調査済み事項(2026-10-17)

| 項目                                      | 結果                                                                                                               |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| caller の型                               | `ci-loop-caller-entity` を使う(D21)。L2 に対応し、`pull_request_target` では base ブランチが作業ツリーの起点になる |
| `delivery: none` + `write_target: report` | 現状は不可。APPROVE 時にレポートが base ブランチに push される。P1、P2 で対応する                                  |
| `agent-l2` / `finalize-l2` の権限         | 両ジョブに `pull-requests: write` がある(`ci-loop-agent.yaml`)。変更不要                                           |
| Meta の使用量                             | `domain_persistence_script` には渡らない。P3 でプラットフォームが追記する                                          |

## 未決事項(実装時に確認する)

1. **冪等性のマーカー。** 本文のマーカー(`<!-- github-pr-review:v1 -->`)で判定する案。bot 名義の確認も加えるか。
2. **作業ブランチ名の衝突。** 複数の PR を同時にレビューしたとき、`loop-worktree-setup` のブランチ名(`<prefix>/<skill>/<date>`)が衝突しないかを確認する。
3. **変更量による段階分け。** 小さい PR は軽く、大きい PR は深く、とするか(初期は行わない案)。
4. **ブランチ保護の現状。** レビュー必須の設定を確認する(第 2 段階の前提)。
