# Loop の `detect_hook_script` の削除

**Status:** Draft(第1回レビューの指摘を反映。High なし)
**Date:** 2026-10-18
**Related:** [Loop の投稿の配信とラベル](2026-10-18-loop-delivery-message-design.md)(同じ日に切り出した。依存はなく、どちらを先に実装してもよい)

## 方針(ユーザー承認済み)

loop の基本線は、検出(`detect_script`)→ エージェント → finalize(run-log、ドメイン処理の `finalize_script`、配信、state)である。スクリプトの入力は `detect_script` と `finalize_script` の2つだけにし、基本線の外にある `detect_hook_script` を削除する。

## 現状と、削除で変わること

- 使っているのは triage だけである(`on-loop-github-issue-triage.yaml:139`)。triage の detect が `result.dispatch_requested` を返すと、`loop-entity-detect` が `on_detect_dispatch.sh` を実行し、`repository_dispatch`(`loop-github-issue-autofix`)で autofix を起動する。パスは `scripts/hooks/on_detect_dispatch.sh` で終わる必要があり(`loop-entity-detect/lib/detect.sh:98-99`)、実質 triage 専用である。
- 起動するのは、`autofix` が付いた Issue に、人(リポジトリの所有者か Issue の作者)が `triage:ready` を付けたときだけである(`detect_issue.sh:352-379`、triage の起動条件 `on-loop-github-issue-triage.yaml:44-75`。エージェントが App のトークンで付けた `triage:ready` は Bot として拒否される)。
- autofix は、`autofix` のラベルで自分で起動し(`on-loop-github-issue-autofix.yaml:8-23`、`:39`)、dispatch からしか得られない情報を使わない(`client_payload.issue_number` は、ラベルと `workflow_dispatch` の経路でも得られる)。
- **失われる経路:** 最初の autofix が PR を作らずに終わった後(REJECT、予算切れ、PR を閉じた、など)、人が `triage:ready` を付けると、hook が autofix をもう一度起動していた。削除の後は、`autofix` を外して付け直すか、`workflow_dispatch`(または `repository_dispatch`)で `issue_number` を渡して起動する。どちらも、triage の設計の D17(`2026-08-11-issue-triage-entity-loops-design.md:51`。autofix の起動はラベルと明示の起動)に沿う。hook を導入した E13/Y3(`2026-08-11-entity-caller-responsibility-separation-design.md:48`、`:101`)は、この spec で廃止する。
- **`triage:ready` での triage の起動もやめる。** 起動の許可リストに `triage:ready` を残しているのは、この hook のためである(`on-loop-github-issue-triage.yaml:40-43`、`:73`)。detect は `triage:ready` の Issue をスキップする(`detect_issue.sh:321-322`)ので、残すと、スキップで終わるだけの実行が並ぶ。

## 変更

| 対象                                     | 変更                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ci-loop-caller-entity.yaml`             | 入力 `detect_hook_script` と、`loop-entity-detect` への受け渡しを削除                                                                                                                                                                                                                                                                                                                                                                                         |
| `loop-entity-detect`                     | `action.yml`(入力、`DETECT_HOOK_SCRIPT`、`:52` の `github_token` の説明の「detect hook」)、`lib/detect.sh`(`resolve_detect_hook_script`、hook の実行、ヘッダの `:17`、`:26`)を削除・修正                                                                                                                                                                                                                                                                      |
| `on-loop-github-issue-triage.yaml`       | `detect_hook_script` を削除。起動の許可リストから `triage:ready` を外し、`:40-43` のコメントを直す。maker の指示の「platform hook handles ready+autofix」を削除                                                                                                                                                                                                                                                                                               |
| triage の skill                          | `scripts/hooks/`(`on_detect_dispatch.sh`、`README.md`)を削除。`detect_issue.sh` の `should_request_dispatch` と `dispatch_*` の出力を削除。`SKILL.md:33`、`:38`、`references/category-fsm.md:20` を直す(evals と `common-checklist.md` は「エージェントは dispatch しない」の記述なので残す)                                                                                                                                                                  |
| autofix                                  | `on-loop-github-issue-autofix.yaml` の `repository_dispatch` の起動は残す(外部や手動の入口。pr-revise と同じ扱い)。skill は変えない                                                                                                                                                                                                                                                                                                                           |
| docs                                     | `loop-engineering-design.md:584`、`loop-caller-inputs-reference.md:37`・`:363`、`loop-github-issue-triage-workflow-design.md:26`・`:64`、`loop-github-issue-autofix-workflow-design.md:22`・`:31`・`:94`                                                                                                                                                                                                                                                      |
| `scripts/self/ci/loop_input_topology.py` | `:91` の項目を削除。配信設計の付録 A の表(`2026-10-17-loop-delivery-plan-design.md:522`)は履歴として作り直さない                                                                                                                                                                                                                                                                                                                                              |
| bats                                     | 削除: `test/bats/.apm/packages/github/github-issue-triage/on_detect_dispatch.bats`、`test/bats/.github/actions/loop-entity-detect/lib/detect_dispatch_hook.bats`。修正: `detect_issue.bats`(出力に `dispatch_*` がないこと)、`test/bats/github-actions/loop-entity-detect.bats`(`:9` のヘッダ、`:94` の入力の一覧、env の数を1つ減らす(件数は、配信の実装で `finalize_label_allowlist` と `finalize_script` が増えた後の値から数える))。追加: `loop-caller-parity.bats:851-860` の `old_names` に `detect_hook_script` を足し、入力が戻らないようにする |
| 同期先                                   | `apm install`(`scripts/self/apm/sync_apm_artifacts.sh`)で `.agents/`、`.claude/` などと `apm.lock.yaml` を更新し、同じ変更でコミットする                                                                                                                                                                                                                                                                                                                      |

- 配布するものの破壊的変更である。`detect_hook_script` を渡す外部の caller は、GitHub が起動時に拒否する(未定義の入力。actionlint が検出するのはローカル参照のときだけ)。loop の再設計では破壊的変更を許す方針に従う。

## 検証

- APM の同期の後、`git grep -inE "detect_hook|on_detect_dispatch|dispatch_requested|dispatch_event_type|dispatch_client_payload|should_request_dispatch"` が、`.loop/`、`CHANGELOG.md`、`docs/superpowers/`、`loop-caller-parity.bats` の `old_names` の行以外で0件。
- 通る bats: `detect_issue.bats`、`loop-entity-detect.bats`、`entity_target.bats`、`loop_input_topology.bats`、`loop-caller-parity.bats`。`python3 -I scripts/self/ci/loop_input_topology.py .` が 0 で終わる。
- dogfood(使い捨てのブランチ): triage を `workflow_dispatch` で動かし、detect が成功すること(動作の確認だけ。dispatch は、この経路では今も送られない)。
- リリースの後: `autofix` の付いたテスト用の Issue に、所有者が `triage:ready` を付け、triage が起動しないこと、`gh run list --workflow on-loop-github-issue-autofix.yaml --event repository_dispatch` に新しい実行がないことを確かめる。
- 未検証として残す: autofix の `repository_dispatch` の経路は、リポジトリ内に送る側がなくなり、テストもない。
