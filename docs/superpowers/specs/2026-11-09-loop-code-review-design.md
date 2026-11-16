# code-review loop(L2、Issue の起票)

**Status:** Draft(独立レビュー第1〜5回を反映。第5回で High・Medium なし。Low 3件も反映済み)
**Date:** 2026-11-09
**Related:** [全体構想と論点](2026-11-09-loop-improvement-handoff-overview.md)、[Loop Engineering Design — Design Principles](../../explanation/loop-engineering/loop-engineering-design.md#design-principles)、[Loop 配信設計](2026-10-17-loop-delivery-plan-design.md)、[Loop の投稿の配信](2026-10-18-loop-delivery-message-design.md)、[PR review loop](2026-10-17-loop-pr-review-design.md)(L2 でレポートを投稿に変える既存の形)

## 0. 準拠する設計原則

### 0.1 原則と決定の対応

| 原則                                         | この spec での決定                                                                                                                                                                                                                                                                                            |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Maker-Checker Separation**                 | Issue の起票は、maker とは別セッションの checker が APPROVE した結果だけで行う。checker は既定で却下。checker のモデルは maker より強いか別の系統。偽の APPROVE への備えとして、`finalize_script` が根拠を機械的に再検証する(第5節)                                                                           |
| **Graduated Autonomy**                       | `issue_create` は報告を超える行動なので、`pr_create` と同じく L2/L3 だけで許す。L1 では拒否する。**code-review loop 自体は L2 から始める(第0.2節)**                                                                                                                                                           |
| **Design Stop Conditions First**             | 止まり方を先に決める(第7節)                                                                                                                                                                                                                                                                                   |
| **Phase Contract**                           | 変えない。finalize は Issue を作るだけで、下流のワークフローを起動しない。後続のループへの引き継ぎはこの spec の範囲外(全体構想を参照)                                                                                                                                                                        |
| **Intake Gating**                            | code-review は `schedule` と `workflow_dispatch` だけで起動し、Webhook を使わない。自己起動の経路がない。作った Issue のイベントは、既存の triage と autofix の Webhook の `if` で拒否される(Bot の送信者。`autofix` 以外のラベル)。不変条件10で、起票時に Webhook の intake のラベルを付けないことを保証する |
| **Multi-loop Coordination**                  | `concurrency.group: loop-state-main` で他の定期 loop と直列にする                                                                                                                                                                                                                                             |
| **Token Budget**                             | `.loop/loop-budget.json` に `code-review` の上限を足す(第6節)                                                                                                                                                                                                                                                 |
| **不変条件1〜6、Agent Credential Isolation** | エージェントは worktree でだけ書き、書き込みの認証情報を持たない。起票は App トークンを持つ finalize が行う。state は finalize でだけ進む                                                                                                                                                                     |
| **Component Design Principles**              | プラットフォームの変更(組み込みの範囲検出、`issue_create`)は汎用。code-review 固有のもの(checker の基準、レポートの変換)は caller と、リポジトリ専用の `finalize_script` に置く                                                                                                                               |
| **State cursor の一般規則**                  | 新しい規則を作らない。`issue_create` は「API で配信する L2」として、checker の APPROVE(と配信の成功)で同じ finalize で進む。REJECT は進めず失敗回数を数える                                                                                                                                                   |

### 0.2 原則からの変更(ユーザー承認済み)

1. **code-review loop を L1 での観察なしに L2 から始める。** Graduated Autonomy は「新しいパターンは L1 から始める」と定めている。ユーザーの決定(2026-11-09)で L2 から始める。代わりに、第7節の Slow Down / Kill の条件と、`finalize_issue_limit` の小さい初期値で、品質が悪いときに早く止める。

L1 を飛ばすので、L1 → L2 の移行チェックリスト(design の Graduated Autonomy)を開始の時点で満たす必要がある。各項目の扱い:

| 項目 | 扱い |
| --- | --- |
| State file schema is documented | 既存の state のスキーマ(`integration:main` のキー)を使う。workflow 設計書に記載する |
| SKILL.md includes build / test commands | **該当しない(第0.2節の変更に含む)。** maker の skill は Claude Code の組み込み `code-review` で、リポジトリに SKILL.md がない。レビューの loop でビルドやテストを走らせないので、代わりに CLI の版を固定して挙動の変化を防ぐ(第4節) |
| Maker and checker are separate sessions | 満たす(L2 の `loop-execute`) |
| Denylist explicitly includes auth, payments, secrets, infrastructure | **代替で満たす。** maker が書けるのは `.loop-code-review/findings.json` だけ(1ファイルの allowlist)。プラットフォームの既定の denylist も効く |
| Auto-merge eligible paths are restricted | 該当しない(PR を作らない) |
| Daily token cap and maximum sub-agent count | 予算を足す(第6節)。sub-agent は `agent_tool_denylist` で `Agent` を禁止する(第4節) |

Maker-Checker の「Prompt must include CI test output and lint results」は、コードを変えないレビューの loop には該当しない(pr-review と同じ)。

これ以外に原則から外れる決定はない。

## 1. 目的と範囲

- マージ済みのコードから、定期的にバグを見つけて Issue にする。後続の triage / autofix の自動の取り込みは別の設計書で扱う(全体構想)。それまでは、起票された Issue は人間が見て、必要なら既存の `autofix` ラベルで修正を依頼する。
- この spec で作るもの:
  1. `ci-loop-caller` の `detect_script` の省略(組み込みの範囲検出)(第2節)
  2. `delivery: issue_create`(L2/L3、integration のターゲット)(第3節)
  3. 汎用の入力 `agent_tool_denylist`(caller が禁止するツール。第4節)
  4. `finalize_script` への範囲の受け渡し(`target_json.from.since`。第5節)
  5. `on-loop-code-review.yaml` と、リポジトリ専用の `finalize_script`(第4節、第5節)

## 2. 組み込みの範囲検出(`detect_script` の省略)

- `ci-loop-caller.yaml` と `loop-detect` の `detect_script` を `required: false`、既定 `""` にする。`ci-loop-caller-entity` は必須のまま。
- 空の `DETECT_SCRIPT` を止めている2か所(`loop-detect/lib/detect.sh` の `main` 先頭の `: "${DETECT_SCRIPT:?}"` と `resolve_detect_script_path`)を、省略時は迂回する。
- 空のとき、ターゲットごとに `last_sha` から `HEAD` までの変更ファイルを `list_diff_paths`(`.github/actions/lib/loop/edit_paths.sh`。`-z`、`core.quotePath=false`)で取る。
  - プラットフォームが書くパス(`.loop/` 配下、解決済みの `state_file` と `run_log_file`)を除く。除かないと、毎回の state と run-log のコミットで「変更0件でスキップ」が起きない。
  - 0件 → `{"skip": true}`。
  - 1件以上 → `{"skip": false, "result": {"since": <last_sha>, "head": <current_sha>, "changed_count": <n>}, "verifier_context": <文字列>}`。`target_json` に `from.since`(`last_sha`)を入れる(第5節の再検証が使う。detect が作る信頼できる値)。`verifier_context` には範囲(`<since>..<head>`)と変更ファイルの一覧(上限付き)を入れる。checker が「根拠がこの範囲の差分にあるか」を確かめるのに使う(`build_verifier_context_from_result` は明示の `verifier_context` をそのまま使う)。
  - `.loop/` などの除外は、出力の後で落とすのではなく、`git diff` の pathspec(`-- . ':!.loop/' ...`)で行う。`list_diff_paths` は rc 2(安全でないパス)のとき何も出力しないため、後からは除外も数えもできない。rc 2 → 実行する(`verifier_context` には範囲だけを書き、一覧は書かない)。rc 1 → detect のステップを非0で終える。rc は `set -e` に頼らず明示的に確かめる(範囲検出は `$(...)` の中で動く)。
- **到達できない `last_sha`:** この経路でだけ、`target_last_sha` で到達を確かめ(`git cat-file -e <sha>^{commit}`)、見つからなければ警告を標準エラーに出して `HEAD~10` を返す。プロンプトの `Last SHA` と範囲検出が同じ基点を使う。既存の `detect_script` の caller には適用しない。
- 既存の `detect_script` を指定した caller の挙動は変えない。

## 3. `delivery: issue_create`

### 3.1 位置づけと検証

- `issue_create` を予約値から実装済みにする。L2/L3 だけで許可し、L1 では拒否する。ターゲットは integration に限る(`validate_delivery_target`、`validate_delivery_detect_config`、`parse_target.sh`)。
- `issue_create` では `finalize_script` と `finalize_label_allowlist` を必須にする(`validate_loop_write_contract`、`validate_finalize_label_allowlist`)。
- `issue_create` では `agent_unchanged_verdict: REJECT` を必須にする(`validate_loop_write_contract`)。APPROVE を許すと、maker が何も書かなかったときに `issues.json` がないまま配信が失敗し続け、state も失敗回数も変わらないまま止まらなくなるため。
- 設定の段階でも拒否する: `validate_delivery_detect_config` で、`issue_create` と `detect_pr_enabled: true`、または空の `detect_branch_match` の組み合わせを拒否する(ターゲットごとの実行時の失敗にしない)。
- 配信設計の検証表(`2026-10-17-loop-delivery-plan-design.md`)の L2/L3 の行に `issue_create` を足し、使えるターゲットを integration にする。

### 3.2 流れ(pr-review の L2 と同じ形)

1. maker が worktree にレポートを書く。指摘0件でも空の配列を書く。
2. checker がレポートを検証し、APPROVE / REJECT する。
3. finalize(Push Agent Branch)がエージェントのブランチを push する(既存どおり verdict によらず push し、REJECT なら Delete Agent Branch が消す)。APPROVE のときだけ、`finalize_script` が `origin/<branch>` からレポートを読み、再検証して(第5節)、`LOOP_MESSAGE_DIR/issues.json` を書く。
4. Deliver Message が Issue を作る。`if` は、delivery の一覧(`issue_comment || pr_review`)に `issue_create` を足し、既存の条件のうち `verdict != 'REJECT'` だけを `issue_create` では `verdict == 'APPROVE'` に置き換え、`agent_result == 'success'` と push の失敗なし(`steps.agent_push.outputs.failed != 'true'`)は保つ。
5. エージェントのブランチを削除する(Delete Agent Branch の delivery の一覧と `should_delete_rejected_branch` に `issue_create` を足す)。

### 3.3 Deliver Message の `issue_create`

- **`issues.json`:** `[{"title", "body", "fingerprint"}]`。0件は `[]`。ない、または検証(配列、必須キー、型、長さの上限)に失敗 → 配信の失敗。
- 手順:
  1. 検証する。`[]` なら何も作らず成功。
  2. 指紋を `sha256(loop_name + "\n" + fingerprint)` の先頭16桁にする。
  3. **重複を先に除く。** `finalize_label_allowlist` の全ラベルが付いた Issue を、open と closed の両方から全件取り(`gh api --paginate "repos/{o}/{r}/issues?labels=<全ラベルのカンマ区切り>&state=all"`。GitHub の `labels` は AND で、順番に依存しない)、本文の marker `<!-- <loop_name>:fp:<hash> -->` をローカルで照合する。同じ実行の中の重複も除く。
  4. 残りを `finalize_issue_limit` で切る。切った指摘は捨て、題名と指紋を step summary に記録する(run-log には件数を残す欄がないので書かない。次回に回すと cursor が止まり範囲が広がり続けるため)。
  5. 1件ずつ、本文中の既存の marker と `@` メンションを無害化し、先頭に marker、末尾に Meta(`build_loop_meta_block`)を付けて、`gh issue create --title --body-file --label <allowlist の全ラベル>` で作る。
  6. 失敗したらその時点で止め、作成済みの番号を `loop_failure_record` と step summary に記録する。
- ラベルは `finalize_label_allowlist` の全ラベルを付ける(エージェントの出力からは取らない)。`issue_create` での `finalize_label_allowlist` の意味は「作る Issue に付けるラベル(と重複判定の絞り込み)」で、`issue_comment` / `pr_review` の「付け外ししてよいラベル」とは異なる。`loop-caller-inputs-reference.md` に明記する。ラベルは事前にリポジトリに作っておく(前提条件)。
- **ラベルを外さない:** 重複の判定はこれらのラベルで一覧を取るので、人間がラベルを外すとその Issue は判定から漏れ、同じ指摘が再び起票されうる。workflow 設計書に運用の注意として書く。
- outcome: 1件以上作れば `issue_created`(新設。`determine_outcome`。`delivery == issue_create` かつ `verdict == APPROVE` のときだけ `issue_created`。それ以外は既存の分岐に任せる)、0件なら `unchanged`。
- **入力:** `finalize_issue_limit`(number、既定 `5`。`ci-loop-caller.yaml` → `ci-loop-agent.yaml` → `loop-finalize`。契約の検証のため `loop-detect` にも)。

### 3.4 不変条件10(新設)

`issue_create` が付けるラベルに、どの Webhook の intake のラベル(dogfood では `autofix`、`needs-triage`、`triage:needs-info`)も含めない。autofix の Webhook は送信者を見ずに `autofix` ラベルで起動するため。強制は caller の `finalize_label_allowlist` で行い、このリポジトリでは bats で全 caller を検査する。

### 3.5 state

既存の state の意味を変えない(第1回レビュー H1)。

- `resolve_state_write_mode` に `issue_create` の分岐を足す: checker が APPROVE し、エージェントのブランチの push に成功したら **advance**。既存の「API で配信する L2 は checker の APPROVE で同じ finalize で進む」に当たる。指摘0件(outcome `unchanged`)でも APPROVE なら advance(State cursor の表に `issue_create` の行として足す。既存の「unchanged → 進めない」は、エージェントが差分を作らなかった場合の規則で、ここではレポートの差分がある)。
- Write State は既存どおり、前のステップが成功したときだけ動く(`always()` を付けない)。次の場合は state を書かず、cursor は進まない。次の実行で同じ範囲を再実行し、重複の判定で二重起票を減らす(指紋はモデルが出すので保証ではない)。
  - `finalize_script` の失敗(Run Finalize Hook が失敗し、Deliver Message 以降が飛ぶ)。
  - (Push Agent Branch の失敗は別の扱い: 既存どおり Write State は動き、`metadata` モード・outcome `error` で書く。cursor は進まず、`consecutive_failures` も変わらない。全 delivery で共通の既存の経路なので変えない。)
  - Deliver Message の失敗。
- REJECT → 既存どおり `metadata`、outcome `rejected`。`consecutive_failures` が増え、circuit breaker と却下内容の持ち越しが働く。
- 配信の失敗は `consecutive_failures` を増やさない(既存の `error` と同じ。Retry Policy を変えない)。同じ原因で失敗し続ける場合は、予算、run-log の `error`、第7節の Kill で止める。
- outcome の流れ: `determine_outcome` は APPROVE かつ `issue_create` で予定の outcome を `issue_created` にする。Deliver Message は、0件なら `unchanged` を出力する(失敗時は Write State が飛び、run-log の outcome は既存の Resolve Run Outcome が `error` にする)。`issue_created` は `loop-run-log` の outcome の説明に足す(`normalize_outcome` は旧名の変換だけなので変更不要)。`finalize_outcome_override` は、caller の入力とエージェントのジョブの出力のどちらから来ても、`issue_create` では無視する(Credential Isolation の残るリスクを広げないため)。

## 4. `on-loop-code-review.yaml`

| 設定                                                                | 値                                                                                                                                                                                                                                                                   |
| ------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| トリガー                                                            | `schedule`(週1回。他の定期 loop と重ならない時刻)、`workflow_dispatch`                                                                                                                                                                                               |
| `concurrency`                                                       | `group: loop-state-main`、`cancel-in-progress: false`、`queue: max`                                                                                                                                                                                                  |
| `uses`                                                              | `./.github/workflows/ci-loop-caller.yaml`(他の on-loop と同じ dogfood)                                                                                                                                                                                               |
| `level` / `delivery`                                                | `L2` / `issue_create`                                                                                                                                                                                                                                                |
| `detect_script`                                                     | 省略(第2節)                                                                                                                                                                                                                                                          |
| `detect_branch_match` / `state_branch`                              | `main` / `main`                                                                                                                                                                                                                                                      |
| `loop_name`                                                         | `code-review`                                                                                                                                                                                                                                                        |
| `agent_engine` / `agent_maker_skill_name`                           | `claude` / `code-review`(Claude Code の組み込み skill)                                                                                                                                                                                                               |
| `agent_edit_target` / `agent_edit_allowlist`                        | `report` / `.loop-code-review/findings.json` だけ                                                                                                                                                                                                                    |
| `agent_maker_instructions`                                          | `code-review` を effort `medium`、基点 `Last SHA` で実行する。検証済みの指摘だけを、題名・本文・指紋(`<path>:<関数名または行の要約>:<不具合の種類>`)・根拠(パスと行の範囲)の形で `.loop-code-review/findings.json` に書く。0件でも空の配列を書く。ソースは修正しない |
| `agent_checker_instructions`                                        | 既定で却下。指摘ごとに、根拠のパスと行が verifier context の範囲の差分に実在するか、不具合の筋道が成り立つか(推測や好みの指摘ではないか)、指紋が位置と種類から決まっているかを確かめる。`findings.json` が JSON の配列でない、または必須キーが欠けていれば REJECT。1件でも根拠のない指摘があれば REJECT。`findings.json` 以外の変更は REJECT    |
| `agent_checker_model`                                               | maker より強いモデルか、別の系統                                                                                                                                                                                                                                     |
| `agent_unchanged_verdict`                                           | `REJECT`(レポートを書かなかった)                                                                                                                                                                                                                                     |
| `agent_tool_allowlist` | 読み取りの git コマンドなど、`code-review` が使う範囲(初回の実行で確かめる) |
| `agent_tool_denylist`(新設) | `Agent`。sub-agent の数の上限を設定する手段がないため、使わせない(L1 → L2 のチェックリストの「maximum sub-agent count」)。`Agent` ツールは許可なしで使えるので、allowlist から外すだけでは止まらない。新しい汎用の入力で `--disallowedTools` に足す(`loop-execute/lib/agent.sh` の `append_claude_permission_args`。プラットフォームの固定の deny に caller の値を加える)。**fail closed:** `agent_engine` が `claude` 以外で空でなければ、detect の契約の検証で拒否する(他のエンジンには allowlist と同じ「警告して無視」の経路しかなく、禁止が黙って外れるため)。L1(`loop-agent-once`)と `ci-loop-caller-entity` には足さず、指定されたら拒否する(この spec では L2/L3 の branch caller で使う)。配線: `ci-loop-caller.yaml` → `loop-detect`(契約の検証のため。`agent_engine` も渡す)と、`ci-loop-caller.yaml` → `ci-loop-agent.yaml` → `loop-execute` |
| `agent_cli_version` | 固定する(既定の `latest` にしない)。maker の skill がリポジトリの外(CLI に組み込み)にあるので、版の更新で挙動が黙って変わるのを防ぐ。既存の Renovate のカスタムマネージャは入力の宣言(`<x>_version:` の `default:`)しか追わないので、`on-loop-code-review.yaml` の `agent_cli_version` を追う regex マネージャを、配布物の `renovate/` ではなくこのリポジトリ専用の `.github/renovate.json` に足す。CLI の版の更新は自動マージせず、人間がレビューする |
| `finalize_script`                                                   | 第5節のスクリプト                                                                                                                                                                                                                                                    |
| `finalize_label_allowlist`                                          | `loop:code-review`(事前に作る。どの intake のラベルでもない)                                                                                                                                                                                                         |
| `finalize_issue_limit`                                              | `3`(L2 から始めるので小さく始める。第0.2節)                                                                                                                                                                                                                          |
| `agent_maker_model`、`agent_*_max_turns`、`agent_loop_max_attempts` | 既存の定期 loop に合わせる                                                                                                                                                                                                                                           |

- **確認済みの事実:** 組み込みの `code-review` に基点のコミットを渡すと、そのコミットから HEAD までの差分をレビューする。ローカルで `claude -p` に CI と同じ権限(`--permission-mode dontAsk`、読み取りの git コマンドだけ)を与えて `low HEAD~1` と `medium HEAD~1` で実行し、`git diff HEAD~1 HEAD` を読んで指摘を返すことを確かめた(2026-11-09)。
- **確認済みの事実の限界:** ローカルの確認は `dontAsk`(checker の権限のモード)で行った。CI の maker は `acceptEdits` で動く。実装の前に、`acceptEdits`、`Agent` の禁止、固定する CLI の版で、`medium` がレポートを書けることをローカルで確かめる。動かなければ effort を下げる。

## 5. `finalize_script`(リポジトリ専用、偽の APPROVE への備え)

- 置き場所: `scripts/self/loop/render_code_review_issues.sh`(code-review はこのリポジトリの skill ではないので、配布物の `.apm/packages/` には置かない)。bats を対にする。
- 処理:
  0. `VERDICT` が `APPROVE` でなければ、何も書かずに成功で終わる(`render_review.sh` と同じ)。REJECT で失敗すると Write State が飛び、`rejected` が書かれず circuit breaker が効かなくなるため。以下の fail closed は APPROVE のときだけ。
  1. `origin/<branch>` から `.loop-code-review/findings.json` を読む。ブランチがない(push されていない)ときは何もしない(pr-review の `render_review.sh` と同じ扱い)。
  1a. `findings.json` を検証する。JSON の配列でない、または必須キーや型が合わなければ、非0で終わる(fail closed。checker がこれを承認した異常な場合)。
  2. 各指摘を決定的に再検証する。範囲は `TARGET_JSON` の `from.since`(detect が入れた `last_sha`)と `from.ref`(detect の HEAD)で決める。finalize の checkout(トリガーのコミット)や state ファイルからは取らない(第1回レビュー H2)。根拠のパスと行の範囲が、`git diff <since> <ref>` の変更行に重なること。重ならない指摘は落とす。`from.since` か `from.ref` がない、または到達できない場合は `issues.json` を書かずに失敗する(fail closed)。題名と本文の長さの上限を超えるものも落とす。
  3. 落とした件数と理由を step summary に出す。
  4. 残りを `LOOP_MESSAGE_DIR/issues.json` に書く(題名、本文(根拠のパスと行を本文に含める)、指紋)。
- `verdict` はエージェントのジョブの自己申告で、偽の APPROVE が届きうる(design の Credential Isolation の残るリスク)。この再検証で、差分と関係のない Issue が作られることを防ぐ。

## 6. 予算

- `.loop/loop-budget.json` に `code-review` を足す。既存の定期 loop(例: tech-debt の `max_runs_per_day: 2`、`max_tokens_per_day`、`max_cost_usd_per_day`)を参考に、週1回の実行に見合う値にする(値は builder)。上限がないと `budget_exceeded` は常に「超えていない」を返す。

## 7. 止まり方(Design Stop Conditions First)

| 止める仕組み                         | 内容                                                                                                                     |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------ |
| checker の REJECT と circuit breaker | 根拠のない指摘があれば起票しない。続けば止まる                                                                           |
| `finalize_script` の再検証           | 差分と関係のない指摘を落とす                                                                                             |
| `finalize_issue_limit`(初期値3)      | 1回の起票数                                                                                                              |
| 指紋の重複判定(open と closed)       | 同じ指摘の再起票                                                                                                         |
| 予算                                 | 1日の実行数、トークン、費用                                                                                              |
| 配信の失敗の扱い | cursor を進めないので、次の実行で同じ範囲を再実行する(重複の判定で二重起票を減らす。指紋はモデルが出すので保証ではない)。失敗回数は増やさない(Retry Policy は変えない)。続く場合は予算と Kill で止める |
| **Pause** | 大きな移行や障害の対応中は、人間が workflow を無効にする(`gh workflow disable`) |
| **Slow Down**                        | 起票した Issue のうち「not planned」で閉じた率が30%を超えたら、`finalize_issue_limit` を下げるか、実行の間隔を広げる     |
| **Kill**                             | 2週続けて、起票した Issue に人間が手を付けず(修正もクローズもない)予算だけを使った、または not planned の率が50%を超えた |

- 率は人間が週に1回、`loop:code-review` の Issue の一覧で確かめる(この spec では自動の集計は作らない)。

## 8. 状態遷移とイベントの対応

| 状態     | きっかけ                                  | 次の状態                                              |
| -------- | ----------------------------------------- | ----------------------------------------------------- |
| 変更なし | 範囲に変更ファイルがない(`.loop/` を除く) | スキップ                                              |
| 実行     | checker が APPROVE、再検証の後に指摘あり  | Issue を作る(重複を除き上限の範囲で)。cursor を進める |
|          | checker が APPROVE、指摘0件               | 何も作らない。cursor を進める                         |
|          | checker が REJECT                         | 作らない。cursor を進めない。失敗回数が増える         |
|          | `finalize_script` または Deliver Message の失敗 | 作成済みは残る。state を書かず cursor を進めない(失敗回数も変えない) |
|          | Push Agent Branch の失敗 | 既存どおり `metadata`・`error` で state を書く。cursor は進まず、失敗回数も変えない |
|          | 失敗回数が上限                            | circuit breaker で止まる(人間)                        |

| イベント(送信者)                             | code-review | triage    | autofix              |
| -------------------------------------------- | ----------- | --------- | -------------------- |
| schedule / workflow_dispatch                 | 実行        | —         | —                    |
| issues:opened(App が作った Issue)            | —           | 拒否(Bot) | —                    |
| issues:labeled `loop:code-review`(App)       | —           | 拒否(Bot) | 拒否(`autofix` 以外) |
| issues:labeled `autofix`(人間が後から付ける) | —           | —         | 実行(既存の挙動)     |

- code-review は Webhook で起動しないので、自分の副作用で再び起動しない。作った Issue は既存のループを起動しない(不変条件10)。人間が `autofix` を付けたときだけ、既存の autofix が動く。

## 9. このリポジトリでの検査(bats)

- 組み込みの範囲検出: `.loop/` だけの変更でスキップ、変更ありで `verifier_context` に範囲が入る、rc 2 で実行、rc 1 で非0終了、空の `detect_script` が組み込みの経路を通る、到達できない `last_sha` でプロンプトの `Last SHA` がフォールバックの値になる、既存の `detect_script` の caller の挙動が変わらない。
- `issue_create` の検証: L1 で拒否、entity / pull_request のターゲットで拒否、`finalize_script` と `finalize_label_allowlist` が必須。
- Deliver Message の `issue_create`: `[]` で何も作らない、重複を上限より先に除く(open と closed)、上限で切った指摘を記録する、marker とメンションの無害化、ラベル、失敗時の記録、outcome。
- state: APPROVE かつ push 成功で advance(0件でも)、REJECT で `rejected`(`finalize_script` は何もせず成功し、Write State が `rejected` を書く)、`finalize_script` / Deliver Message の失敗で state を書かない、push の失敗で既存どおり `metadata`・`error`。
- 不変条件10(全 caller の `finalize_label_allowlist`)。
- `render_code_review_issues.sh`: 差分の変更行に重ならない指摘を落とす、ブランチがないときに何もしない、`from.since` がない・到達できないときに失敗する。
- `issue_create` で `agent_unchanged_verdict: APPROVE` を拒否すること。
- `agent_tool_denylist` が `--disallowedTools` に足されること。claude 以外のエンジン、L1、entity caller で指定すると拒否されること(`loop-caller-parity.bats` を含む)。
- `finalize_script` / Deliver Message の失敗で state を書かないこと。REJECT のとき `finalize_script` が何もせず成功し、`rejected` が書かれて失敗回数が増えること。
- 新しい入力に合わせて `loop-caller-parity.bats`、`loop_input_topology.py` 等を更新する。

## 10. 残るリスク

- **L1 の観察を飛ばす:** 最初の数回は誤検出が多いかもしれない。上限3、checker、再検証、Slow Down / Kill で抑える(第0.2節)。
- **指紋の不安定さ:** 同じ不具合が別の Issue になりうる。checker と上限で抑える。揺れが目立てば、`finalize_script` が根拠のパスと不具合の種類から指紋を作る方式に変える。
- **再発の抑止:** closed も重複の判定に含めるので、同じ指紋の不具合が再発しても起票されない。
- **上限を超えた指摘:** 捨てて step summary に記録する。記録は Actions のログの保存期間の間だけ残る。拾うのは人間。上限に頻繁に当たるなら上限を上げる。
- **出所ラベルの削除:** 判定から漏れて再起票されうる(第3.3節)。
- **初回の確認事項:** CI の CLI の組み込み `code-review`、`Agent` なしでの動作。 `Agent` なしで `low` でも動かない(組み込みの `code-review` が sub-agent を必須にしている)場合は、loop を始めずにこの spec を見直す。

## 11. ドキュメントの更新

- `loop-engineering-design.md`: 不変条件10、State cursor の表(`issue_create`)、Finalize の strategy matrix とブランチを削除する delivery の一覧(`issue_create`)、Graduated Autonomy の段階ごとの権限(`issue_create` は L2 以上)、Credential Isolation の残るリスク(`issue_create`)、Implementation Status の表に code-review。
- `loop-caller-inputs-reference.md`、`docs/reference/specification.md`: `detect_script` の省略、組み込みの範囲検出の出力、`issue_create`、`finalize_issue_limit`。
- `common-loop-triage-format.md`: Delivery の行(`issue_create` を予約から外す)。
- `2026-10-17-loop-delivery-plan-design.md`: `issue_create` の使えるターゲットと検証表。
- `loop-engineering-design.md` の追加: Domain Isolation の「Detection criteria」と Phase Contract の Detect(`detect_script` を省略したときの組み込みの範囲検出)、STATE Files(`state-code-review.json`)、Intake Gating の「`loop-state-main` を共有する caller」の数。
- `loop-caller-inputs-reference.md` の追加: `agent_tool_denylist`、`issue_create` での `finalize_label_allowlist` の意味、`target_json.from.since`。
- `loop-run-log` の outcome の一覧(`issue_created`)。
- `loop-engineering-design.md` の Retry Policy の「Policy by failure type」(APPROVE → `issue_create` の advance、配信の失敗)、Phase Contract の Finalize の Responsibility と「GitHub API deliverables」、Denylist / Least Privilege の L2 の行(Issue の作成)。`CONTEXT.md` の「GitHub API Action (Execute)」(Deliver Message と合っていない既存の記述)。`validate_finalize_label_allowlist` のエラー文。
- 新規: `docs/explanation/loop-engineering/workflows/loop-code-review-workflow-design.md`(運用: ラベルを外さない、週1回の率の確認、Pause / Slow Down / Kill、state のスキーマ)。
- 新しいドキュメントを足すときの `mkdocs.yml` の nav。`loop-run-log/action.yml` の outcome の説明に `issue_created` を足す。
- delivery を列挙している入力の説明: `delivery`(`ci-loop-caller.yaml`、`ci-loop-agent.yaml`、`loop-detect/action.yml`、`loop-finalize/action.yml`)と `finalize_label_allowlist`(同じ4ファイル)、`ci-loop-agent.yaml` 冒頭のコメント。`validate_loop_write_contract.sh` と `lib/loop/delivery.sh` の冒頭の Design Rules のコメント(`issue_create` を未実装としている)。`loop-caller-inputs-reference.md` の `agent_unchanged_verdict` の行と検証の規則(`issue_create` では `REJECT` が必須)。

## 12. builder に任せること

- 組み込みの範囲検出と `target_last_sha` の到達の確認の実装の分け方。`verifier_context` の変更ファイルの一覧の上限。
- (state の判定は第3.5節で決めた: `resolve_state_write_mode` の `issue_create` の分岐は Deliver Message より前に置き、Write State には `always()` を付けない。builder はこれを変えない。)
- `issues.json` の検証の詳細(長さの上限)、無害化の方式。
- 予算の値、実行の曜日と時刻。
- **SHA pin は2段で更新する**(action のリリース → `ci-loop-agent.yaml` の pin → caller の pin。`loop-detect` と `loop-run-log` は `ci-loop-caller.yaml` が直接 pin しているので、その pin も更新する。`.github/workflows/CLAUDE.md` の Pins)。
