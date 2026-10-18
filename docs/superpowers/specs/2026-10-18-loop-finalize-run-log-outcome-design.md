# Loop の run-log の outcome と失敗の段階を `loop-finalize` に寄せる

**Status:** Draft(第2回レビューの指摘を反映。High なし)
**Date:** 2026-10-18
**Related:** [Loop の投稿の配信とラベル](2026-10-18-loop-delivery-message-design.md)(finalize-l1 で `loop-finalize` を実行する変更が入る。**この spec は、その後に実装する**)

## 方針(ユーザー承認済み)

finalize は、エージェントから返ってきたものを処理する最終地点である。何が起きたか(outcome、失敗の段階)の判断は `loop-finalize` の中で1回だけ行い、workflow の YAML に判断を書かない。

## 現状の問題

配信の spec の実装後、finalize-l1 と finalize-l2(`ci-loop-agent.yaml`)は、どちらも `loop-finalize` の外に判断を2つ持つ。

| 箇所                                                                                 | 判断                                                                                 | 問題                                                      |
| ------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------ | --------------------------------------------------------- |
| Resolve Run Log Metadata(finalize-l2、`:564-598`)                                    | 失敗の段階とメッセージを、エージェントのジョブの出力と finalize の失敗から選ぶ       | YAML の中の bash で、bats でテストできない。L1 にはない   |
| Append Run Log の `outcome:` の式(`:612`。配信の spec で finalize-l1 も同じ式になる) | finalize の失敗、`outputs.outcome`、エージェントの結果、`REJECT` から outcome を選ぶ | `loop-finalize` の `determine_outcome` と同じ判断の二重化 |

## 変更

- **失敗の段階:** 既存の `if: always()` の Export Failure Diagnostics(`loop-finalize/action.yml:315-320`)の直前に、`if: always()` のステップを1つ足す。finalize の失敗の記録がないときだけ、`loop_failure_record` で記録する。「記録がある」の判定は、共有の `lib/loop/failure_record.sh` に関数 `loop_failure_recorded FILE` を足して行う(ファイルがあり `.failure_stage` が空でない。`loop_failure_export_outputs` の判定と同じ。`failure_record.sh:50-58`)。ファイルは `action.yml:244`、`:318` と同じ `LOOP_FAILURE_FILE`(`.github/workflows/CLAUDE.md` の Failure diagnostics。出力の書き出しは既存の `export_failure_diag.sh` のまま)。
  - 優先順位は現在の Resolve Run Log Metadata と同じで、finalize の記録 > エージェントの段階とメッセージ(新しい入力 `agent_failure_stage`、`agent_failure_message`)> `agent_execute`(`agent_result` が `success` でも `skipped` でもない)> `finalize`(`loop-finalize` のステップが失敗し、ほかに何もない)。
  - L1 では新しい入力は空で、エージェントの失敗は `agent_execute` として記録される(現在の finalize-l1 は段階を記録しない。意図した変更)。
  - 判断は `loop-finalize/lib/` のスクリプトに置き、bats でテストする。
- **outcome:** 同じ `if: always()` のステップが、出力 `outcome` を決める。`github.action_status`(composite の中では、その composite の前のステップの状態。env の `ACTION_STATUS` でスクリプトに渡す)が `success` でなければ `error`(キャンセルを含む)、ほかは配信の spec の最終の値(Deliver Message の出力、なければ Determine Outcome の値)。Parse Target など Determine Outcome より前の失敗も `error` にする。出力 `outcome` の説明を「run-log に書く最終の outcome」に直す。
- **workflow:** finalize-l1 と finalize-l2 は、`loop-finalize` の `outcome`、`failure_stage`、`failure_message` を `loop-run-log` に、`outcome` を `loop-notify-pr` に渡す(`loop-notify-pr` に段階の入力はない)。Resolve Run Log Metadata と `:612` の式を削除する。Append Run Log の `agent_result` は `needs.<agent>.result` を直接渡し、`agent_failure_*` には `needs.agent-l2.outputs.failure_*`(`:357-358`)を渡す。`:523-527` のコメントを直す。
- **`loop-finalize` が動かなかったとき**(Checkout、Download Loop Handoff、Resolve GitHub Token の失敗で、Finalize のステップがスキップされたとき): 出力は空になる。`loop-run-log` は `OUTCOME` を必須にする(`loop-run-log/lib/run.sh:139`)ので、workflow に `outcome: ${{ steps.finalize.outputs.outcome || 'error' }}` と `failure_stage: ${{ steps.finalize.outputs.failure_stage || (steps.finalize.outputs.outcome == '' && 'finalize' || '') }}` の既定値だけを残す。判断ではなく、空のときの既定値である(`loop-notify-pr` の `:638` と同じ形)。この場合、run-log の行は `error` / `finalize` になり、エージェントの段階とメッセージは記録されない(現在はエージェントの結果から outcome を選ぶ。意図した変更として受け入れる)。
- **notify の変化(意図した変更):** 現在、notify は Determine Outcome の値を受け取るので、後のステップ(例: `pr_push` の Push to Target Branch)が失敗しても `pr_pushed` を表示する。変更後は `error` を表示し、run-log と一致する。
- **pin:** workflow の変更は、`ci-loop-agent.yaml` の `loop-finalize` の SHA pin の更新と同じ変更で出す(`.github/workflows/CLAUDE.md` の Pins)。

## 検証

- 新しいスクリプトの bats(`test/bats/.github/actions/loop-finalize/lib/` に置く): 優先順位の表の全行(エージェントの失敗の段階あり・なし、finalize の失敗の記録あり・なし、両方、どちらもなし)、`REJECT`、`unchanged`、Determine Outcome より前の失敗、キャンセル、記録があればステップも失敗していること。メッセージには、マスクされるトークンを含むものと 500 文字を超えるものを入れる(再記録で値が変わらないこと)。
- `test/bats/github-actions/loop-caller-parity.bats`: finalize-l1 と finalize-l2 に `run_log_meta` がなく、`outcome:` が上の既定値の形だけであること。
- L2 の run-log の行(outcome、failure_stage、failure_message)が変更の前後で同じであること。現在の YAML の判断を、bats の期待値の表として写してから削除する。意図した違い(L1 の段階の記録、notify の `error`、`loop-finalize` がスキップされたときの `error` / `finalize`、キャンセルの `error`)は別のケースにする。
- docs: `docs/reference/specification.md:400`、`:491`(診断をまとめる場所が `ci-loop-agent` から `loop-finalize` に移る)、`:509-517`(`error` に finalize の失敗を含める)、`loop-finalize/action.yml` の出力の説明。
