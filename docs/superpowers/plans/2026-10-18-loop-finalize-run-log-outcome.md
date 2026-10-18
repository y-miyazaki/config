# Loop Finalize Run-Log Outcome Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** run-log の outcome と失敗の段階の判断を `loop-finalize` の中の1か所(新しい `if: always()` のステップ)に寄せる。finalize-l1 と finalize-l2 の YAML からは、Resolve Run Log Metadata と outcome の式を消し、空のときの既定値だけを残す。

**Architecture:** `loop-finalize` の Export Failure Diagnostics の直前に Resolve Run Outcome(`id: run_outcome`)を置く。ステップは `lib/resolve_run_outcome.sh` を実行し、(1) `github.action_status` と finalize の記録と配信の値から outcome を決めて出力し、(2) finalize の記録がなければ、エージェントの段階、`agent_execute`、`finalize` の順で `loop_failure_record` により `LOOP_FAILURE_FILE` に記録する。出力は既存の Export Failure Diagnostics(`export_failure_diag.sh`)がそのまま書き出す。「記録がある」の判定は共有の `lib/loop/failure_record.sh` の新しい関数 `loop_failure_recorded FILE` で行う。

**Tech Stack:** GitHub Actions(reusable workflow、composite action)、bash、jq、bats。

**Spec:** `docs/superpowers/specs/2026-10-18-loop-finalize-run-log-outcome-design.md`。spec の行番号は配信の実装と detect hook の削除(`feat/loop-delivery-message`、HEAD `8580feb8`)の後でずれている。この plan の行番号は HEAD で確かめた値である(対応は末尾の「spec との差」)。

## Global Constraints

- 優先順位(失敗の段階): finalize の記録 > エージェントの段階とメッセージ(新しい入力 `agent_failure_stage`・`agent_failure_message`)> `agent_execute`(`agent_result` が `success` でも `skipped` でもない)> `finalize`(`ACTION_STATUS` が `success` でない、または配信の値が空)。記録しないときの `failure_message` は、どの段階でも `agent_failure_message`(現在の YAML の `msg` と同じ)。
- outcome: `ACTION_STATUS` が `success` でない(`failure`・`cancelled`)、配信の値(`steps.deliver.outputs.outcome || steps.outcome.outputs.value`)が空、または finalize の記録がある → `error`。ほかは配信の値をそのまま(`rejected`、`unchanged`、`watch` を含む)。**outcome はエージェントの段階を記録する前に決める**(Review Focus 1)。
- `LOOP_FAILURE_FILE` は既存と同じ `${{ runner.temp }}/loop-finalize-failure.json`。記録は `loop_failure_record`、書き出しは既存の `export_failure_diag.sh` だけ(`.github/workflows/CLAUDE.md` の Failure diagnostics)。新しい書き出しの処理を作らない。
- workflow に残すのは空のときの既定値だけ: `outcome: ${{ steps.finalize.outputs.outcome || 'error' }}`、`failure_stage: ${{ steps.finalize.outputs.failure_stage || (steps.finalize.outputs.outcome == '' && 'finalize' || '') }}`、`failure_message: ${{ steps.finalize.outputs.failure_message }}`。`loop-notify-pr` の `outcome:`(`ci-loop-agent.yaml:671`)は既にこの形なので変えない。
- 意図した違い(spec): L1 でエージェントの失敗を `agent_execute` として記録する、notify が後のステップの失敗で `error` を表示する、`loop-finalize` がスキップされたときは `error` / `finalize`(エージェントの段階は記録されない)、キャンセルは `error`。
- シェルの変更には bats を対にする(`.claude/rules/bats.md`)。`shfmt`・`prettier` は PostToolUse フック、`shellcheck`・`actionlint`・`markdownlint` などは Stop フックが実行する。**実装者は直接実行しない**(結果はフックの出力で見る)。
- 作業ツリーに無関係の変更がある(`.claude/settings.json`、`.cursor/mcp.json`、`.mcp.json`、`apm.lock.yaml`、`.claude/worktrees/`)。コミットは**明示したパスだけ**を stage する。`git add -A` は使わない。この plan は skill を変えないので APM の同期は要らない(Stop フックの同期で差分が出ても stage しない)。
- 一時ファイルは `tmp/` に置き、使い終えたら消す。
- `ci-*` から `./.github/...` を参照しない。pin は変えない。リリースと pin の更新、GitHub Actions のワークフローの実行(dogfood)は、この plan に含めない。push しない(「リリースと dogfood(手動)」)。
- credential-isolation の spec(`2026-10-18-loop-agent-credential-isolation-design.md`)は実装しない。ただし、その Push Agent Branch の失敗をステップの失敗にするステップは「Delete Agent Branch の後、Resolve Run Outcome の前」に入る。Resolve Run Outcome は Export Failure Diagnostics の**直前**に置き、Delete Agent Branch との間に何も置かない(後でその spec が1ステップを挟む)。その spec の Push Agent Branch は失敗を段階 `push` で同じ `LOOP_FAILURE_FILE` に記録して 0 で終えるので、Resolve Run Outcome は記録を上書きせず、outcome も記録だけで `error` になる(fail のステップより前でも)。その spec が足すステップの並びは、Task 5 の `steps run in spec order` の期待値を、その spec の実装で直す。

## Review Focus

1. **outcome を決める順。** `record_run_failure` の後に `resolve_run_outcome` を呼ぶと、エージェントの段階(例: `notify_context`)を書いたファイルが「記録あり」になり、成功した実行が `error` になる。`main` は outcome を先に決める。Task 4 の `outcome is resolved before the agent stage is recorded` と表の `agent_stage_on_success` 行で見る。
2. **`GITHUB_OUTPUT` の区切り。** 現在の `loop_failure_export_outputs`(`failure_record.sh:64-65`)は `printf '%s'` の後に区切りを書くので、空でないメッセージでは区切りが同じ行に付く。GitHub のランナーは区切りが1行で一致するまで読み、見つからなければ `Matching delimiter not found` で失敗する(`actions/runner` の `FileCommandManager.cs`)。この plan で全部の段階のメッセージがこの経路を通るので、Task 2 で直す(spec にない。下の「spec との差」)。
3. **`github.action_status`。** GitHub の docs の記述は「For a composite action, the current result of the composite action.」だけで、値の一覧はない。`success` 以外をすべて失敗として扱い、`cancelled` の実地の値は dogfood で確かめる(bats では確かめられない)。
4. **失敗した composite のステップの出力。** finalize の `continue-on-error: true` のステップが失敗したとき、`steps.finalize.outputs.*` が読めることを前提にする。現在の Resolve Run Log Metadata(`ci-loop-agent.yaml:604-606`)も同じ前提で、dogfood で確かめる。読めなければ既定値で `error` / `finalize` になる(誤った成功にはならない)。
5. **pin。** dogfood の caller は `./.github/workflows/ci-loop-caller*.yaml` を使い、その中の `ci-loop-agent.yaml` と、`ci-loop-agent.yaml` の中の `loop-finalize` は SHA で pin されている(`ci-loop-caller.yaml:476`、`ci-loop-caller-entity.yaml:327`、`ci-loop-agent.yaml:349`、`:563`)。Task 6 の後、pin を上げる前に `ci-loop-agent.yaml` だけが外の利用者に届くと、古い `loop-finalize` は `agent_failure_*` を知らず(未知の入力の警告)、`outcome` は旧い意味のままで、エージェントの段階が run-log から消える。リリースは pin の更新と同時に行う(spec「pin」)。

---

## ファイル構成

| ファイル                                                                                                                                                                                                                         | 責務                                                   | Task |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------ | ---- |
| `.github/actions/lib/loop/failure_record.sh`、`test/bats/.github/actions/lib/loop/failure_record.bats`                                                                                                                           | `loop_failure_recorded`、区切りの修正                  | 1, 2 |
| `test/bats/.github/actions/loop-finalize/lib/resolve_run_outcome.bats`(新規)                                                                                                                                                     | 現在の YAML の判断の表(写し)、新しいスクリプトのテスト | 3, 4 |
| `.github/actions/loop-finalize/lib/resolve_run_outcome.sh`(新規)                                                                                                                                                                 | outcome と失敗の段階の判断                             | 4    |
| `.github/actions/loop-finalize/action.yml`、`test/bats/.github/actions/loop-finalize/action_delivery.bats`                                                                                                                       | 入力、Resolve Run Outcome、出力                        | 5    |
| `.github/workflows/ci-loop-agent.yaml`、`test/bats/github-actions/loop-caller-parity.bats`                                                                                                                                       | Resolve Run Log Metadata と outcome の式の削除、既定値 | 6    |
| `docs/reference/specification.md`、`docs/explanation/github-workflows-design.md`、`docs/explanation/loop-engineering/workflows/loop-github-issue-triage-workflow-design.md`、`.github/actions/loop-run-log/action.yml`(説明だけ) | 記述                                                   | 7    |

---

### Task 1: `loop_failure_recorded` を共有ライブラリに足す

**Files:**

- Modify: `.github/actions/lib/loop/failure_record.sh:6-9`(Usage)、`:43-58`(`loop_failure_export_outputs` の判定)、`:68` の後(新しい関数。a-z の順で `loop_failure_record` の後)
- Test: `test/bats/.github/actions/lib/loop/failure_record.bats:6-10`(Use cases)、テストを足す

**Interfaces:** Produces `loop_failure_recorded FILE`: ファイルがあり、`jq -r '.failure_stage // empty'` が空でなければ 0、それ以外(ファイルがない、壊れた JSON、`failure_stage` が空)は 1。標準出力に何も出さない。`loop_failure_export_outputs` は `if ! loop_failure_recorded "${failure_file}"; then return 0; fi` で同じ判定を使う(判定を2か所に書かない。出力は変わらない)。

- [ ] **Step 1: 失敗するテストを書く(`failure_record.bats`)。** Use cases に `# - loop_failure_recorded is true only for a file with a non-empty failure_stage` を足す。a-z の順に置く:
  - `@test "loop_failure_recorded fails for a missing file, malformed JSON, or an empty stage"`: ファイルなし、`{` だけ、`{"failure_stage":"","failure_message":"x"}` の3つで `run loop_failure_recorded ...` が `status -eq 1`、`output` が空。
  - `@test "loop_failure_recorded succeeds after loop_failure_record"`: `loop_failure_record "finalize_pr" "x" "${f}"` の後に `status -eq 0`。
- [ ] **Step 2: 失敗を確認する。** `bats test/bats/.github/actions/lib/loop/failure_record.bats`。Expected: FAIL(`loop_failure_recorded: command not found`)。
- [ ] **Step 3: 実装する。** 関数のドキュメントは同じファイルの形(Globals / Arguments / Outputs / Returns)にする。`loop_failure_export_outputs` の `:50-58` を Interfaces の1行と `stage`・`message` の読み出しにする。
- [ ] **Step 4: 通ることを確認する。** `bats test/bats/.github/actions/lib/loop/failure_record.bats test/bats/.github/actions/lib/loop/export_failure_diag.bats`。Expected: PASS。
- [ ] **Step 5: コミットする。** `git add .github/actions/lib/loop/failure_record.sh test/bats/.github/actions/lib/loop/failure_record.bats`、`feat(loop): add loop_failure_recorded to the failure record library`。

---

### Task 2: `failure_message` の区切りを行の頭に置く(spec にない修正)

**Files:**

- Modify: `.github/actions/lib/loop/failure_record.sh:64`
- Test: `test/bats/.github/actions/lib/loop/failure_record.bats`、`test/bats/.github/actions/lib/loop/export_failure_diag.bats`(変えない。回帰として通す)

**Interfaces:** `loop_failure_export_outputs` の出力は `failure_message<<D` / メッセージ / `D` の3行以上になる。GitHub は区切りの直前の改行を値に含めないので、値は変わらない。

- [ ] **Step 1: 失敗するテストを書く。** `@test "loop_failure_export_outputs puts the delimiter on its own line"`: `loop_failure_record "push" $'line one\nline two' "${f}"`、`loop_failure_export_outputs "${f}"` の後、`delim="$(sed -n 's/^failure_message<<//p' "${GITHUB_OUTPUT}")"` が空でなく、`grep -cxF "${delim}" "${GITHUB_OUTPUT}"` が `1`、区切りの前の行が `line two`。Use cases に `# - loop_failure_export_outputs ends the message before a delimiter line (GitHub matches the whole line)` を足す。
- [ ] **Step 2: 失敗を確認する。** `bats test/bats/.github/actions/lib/loop/failure_record.bats`。Expected: FAIL(区切りが `line two` の行に付いている)。
- [ ] **Step 3: 実装する。** `:64` を `printf '%s\n' "${message}"` にする。
- [ ] **Step 4: 通ることを確認する。** Task 1 Step 4 のコマンド。Expected: PASS。兄弟の箇所: `git grep -n -A1 "printf '%s' \"\${msg}\"" -- .github` は `ci-loop-agent.yaml:628`(Resolve Run Log Metadata)だけで、Task 6 で消える。ほかの `<<${delim}` の書き手(`loop-run-log/lib/run.sh:170`、`loop-agent-once/lib/run.sh:89`・`:123`、`loop-execute/lib/loop.sh:175-186`、`notify_context.sh:273`、`loop-entity-detect/lib/outputs.sh:52`、`loop-detect/lib/matrix.sh:249`、`loop-detect/lib/detect.sh:1074`)は `echo` で改行を付けており、当たらない。
- [ ] **Step 5: コミットする。** `git add .github/actions/lib/loop/failure_record.sh test/bats/.github/actions/lib/loop/failure_record.bats`、`fix(loop): end exported failure messages before the delimiter line`。

---

### Task 3: 現在の YAML の判断を表に写す(削除の前)

**Files:**

- Create: `test/bats/.github/actions/loop-finalize/lib/resolve_run_outcome.bats`(この Task では表と、現在の YAML を検査するテストだけ)

**Interfaces:**

- Produces 表 `L2_CASES`(ファイルの定数。`|` 区切りで、列は `name|agent_result|agent_stage|agent_message|action_status|record_stage|record_message|delivered_outcome|outcome|failure_stage|failure_message`)。`action_status` は現在の `steps.finalize.outcome`(`success` / `failure`)、`record_*` は現在の `steps.finalize.outputs.failure_*`、`delivered_outcome` は現在の `steps.finalize.outputs.outcome`(Determine Outcome より前の失敗では空)に当たる。
- Produces 補助関数(ファイルの中だけ):
  - `output_value KEY FILE`: `KEY=v` の行と `KEY<<D` の形を読む。区切りは「その行と一致する」か「その行の末尾にある」(現在の YAML の `:628-629` は区切りを本文の行に付けるため)。
  - `current_l2_outcome STEP_RESULT FINALIZE_OUTCOME AGENT_RESULT VERDICT`: `ci-loop-agent.yaml:645` の式を項の順に写した関数(`failure` → `error`、`FINALIZE_OUTCOME` が空でなければそれ、エージェントの失敗 → `error`、`REJECT` → `rejected`、ほかは `unchanged`)。

表(この内容で置く。メッセージに `|` を入れない):

```bash
# Rows transcribed from ci-loop-agent.yaml finalize-l2 (Resolve Run Log Metadata
# :597-631 and the Append Run Log outcome expression :645) before their removal.
L2_CASES="$(cat <<'EOF'
success_created|success||||success|||pr_created|pr_created||
rejected|success||||success|||rejected|rejected||
unchanged|success||||success|||unchanged|unchanged||
watch_override|success||||success|||watch|watch||
agent_failed_no_stage|failure||||success|||error|error|agent_execute|
agent_failed_with_stage|failure|push|remote rejected|success|||error|error|push|remote rejected
agent_stage_on_success|success|notify_context|detect result JSON is invalid (inline)|success|||pr_created|pr_created|notify_context|detect result JSON is invalid (inline)
finalize_record|success||||failure|finalize_pr|gh pr create failed|pr_created|error|finalize_pr|gh pr create failed
finalize_record_over_agent_stage|failure|push|remote rejected|failure|finalize_pr|gh pr create failed|error|error|finalize_pr|gh pr create failed
deliver_record|success||||failure|deliver_message|Failed to post: HTTP 502|pr_reviewed|error|deliver_message|Failed to post: HTTP 502
before_determine_outcome|success||||failure||||error|finalize|
finalize_failed_keeps_agent_stage|failure|push|remote rejected|failure||||error|error|push|remote rejected
finalize_failed_keeps_agent_execute|failure||||failure|||error|error|agent_execute|
push_target_failed_no_record|success||||failure|||pr_pushed|error|finalize|
EOF
)"
```

- [ ] **Step 1: テストを書く。** ヘッダーは `# Tests for .github/actions/loop-finalize/lib/resolve_run_outcome.sh` と `# and, until its removal, the finalize-l2 run-log decisions in .github/workflows/ci-loop-agent.yaml`。Use cases に `# - L2_CASES is a faithful transcription of the current finalize-l2 Resolve Run Log Metadata and outcome expression`。support の読み込みは `failure_record.bats` と同じ形。テストは1件:
  - `@test "current finalize-l2 run log metadata and outcome match L2_CASES"`:
    - `ci-loop-agent.yaml` から Resolve Run Log Metadata の `run: |` の本文を取り出す(`awk '/^      - name: Resolve Run Log Metadata$/ {f=1; next} f && /^        run: \|$/ {r=1; next} r && /^          / {sub(/^          /, ""); print; next} r {exit}'`)。空でないこと。
    - `:645` の式の行が `grep -qxF` で一致すること(式が変わったら写しも見直すため)。
    - 各行で `GITHUB_OUTPUT` を空にし、`AGENT_RESULT`・`EXEC_FAILURE_STAGE`・`EXEC_FAILURE_MESSAGE`・`FINALIZE_STEP_RESULT`(=`action_status`)・`FINALIZE_FAILURE_STAGE`・`FINALIZE_FAILURE_MESSAGE` を渡して `bash -c "${script}"` を実行する。`output_value failure_stage` と `output_value failure_message` が表と一致し、`current_l2_outcome "${action_status}" "${delivered_outcome}" "${agent_result}" ""` が `outcome` 列と一致すること。合わなければ `echo "case ${name}: ..." >&2` で行の名前を出して `return 1`。
    - 最後に、検査した行数が `14` であること。
- [ ] **Step 2: 通ることを確認する。** `bats test/bats/.github/actions/loop-finalize/lib/resolve_run_outcome.bats`。Expected: PASS(現状の写し)。落ちたら YAML ではなく表を直す(写しの誤り)。
- [ ] **Step 3: コミットする。** `git add test/bats/.github/actions/loop-finalize/lib/resolve_run_outcome.bats`、`test(loop-finalize): transcribe the current finalize-l2 run-log decisions as a table`。

---

### Task 4: `resolve_run_outcome.sh`

**Files:**

- Create: `.github/actions/loop-finalize/lib/resolve_run_outcome.sh`
- Test: `test/bats/.github/actions/loop-finalize/lib/resolve_run_outcome.bats`

**Interfaces:**

- Consumes `loop_failure_record`・`loop_failure_recorded`(Task 1)。`failure_record.sh` は `$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib/loop" && pwd)` から source する(`create_pr.sh:98` と同じ解決)。
- Produces 実行スクリプト(`push_target.sh` の形: `set -euo pipefail`、`umask 027`、`LC_ALL=C.UTF-8`、Global variables、`main`、`if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then main "$@"; fi`)。
  - 読む env: `ACTION_STATUS`、`AGENT_FAILURE_MESSAGE`、`AGENT_FAILURE_STAGE`、`AGENT_RESULT`、`DELIVERED_OUTCOME`、`GITHUB_OUTPUT`(任意)、`LOOP_FAILURE_FILE`(必須。空なら `::error::LOOP_FAILURE_FILE is required` で 1)。
  - `resolve_run_outcome <action_status> <delivered_outcome> <failure_file>`: Global Constraints の outcome を標準出力に出す。0 を返す。
  - `record_run_failure <failure_file> <agent_result> <agent_stage> <agent_message> <action_status> <delivered_outcome>`: `loop_failure_recorded` なら何もしない。そうでなければ Global Constraints の優先順位で1回だけ `loop_failure_record` を呼ぶ。どれにも当たらなければ何もしない。0 を返す。
  - `main`: `outcome="$(resolve_run_outcome ...)"` → `record_run_failure ...` の順(Review Focus 1)。`GITHUB_OUTPUT` があれば `outcome=<v>` を書く。0 で終わる。
  - 関数は a-z の順(`main`、`record_run_failure`、`resolve_run_outcome`)。ヘッダーの Design Rules に、優先順位、outcome の規則、「書き出しは `export_failure_diag.sh`」を書く。

- [ ] **Step 1: 失敗するテストを書く。**
  - Use cases を足す(表の全行、意図した違い、再記録、`LOOP_FAILURE_FILE` の必須)。`SCRIPT` 定数と `setup()`(`bats_source_rel ".github/actions/lib/loop/failure_record.sh"`、`LOOP_FAILURE_FILE`・`GITHUB_OUTPUT` を `BATS_TEST_TMPDIR` に)を置く。
  - 補助関数 `run_case AGENT_RESULT AGENT_STAGE AGENT_MESSAGE ACTION_STATUS RECORD_STAGE RECORD_MESSAGE DELIVERED`: 2つのファイルを消し、`RECORD_STAGE` が空でなければ `loop_failure_record` で先に記録し、`run env ... bash "${SCRIPT}"` を実行する。結果の outcome は `output_value outcome "${GITHUB_OUTPUT}"`、段階とメッセージは `jq -r '.failure_stage // ""'` / `.failure_message // ""`(ファイルがなければ空)で読む。
  - テスト(a-z の順):
    - `@test "a cancelled composite is error and records finalize"`: `success||| cancelled ||| pr_created` → `error` / `finalize` / 空(意図した違い。現在は `steps.finalize.outcome == 'cancelled'` を失敗と見ず `pr_created`)。
    - `@test "a finalize record makes the outcome error even when the action status is success"`: `success||| success | finalize_pr | x | pr_created` → `error` / `finalize_pr` / `x`(spec「記録があればステップも失敗していること」の、この plan の解釈)。
    - `@test "an L1 agent failure records agent_execute"`: `failure||| success ||| error` → `error` / `agent_execute` / 空(意図した違い。現在の finalize-l1 は段階を記録しない)。
    - `@test "every L2_CASES row resolves to the transcribed outcome, stage and message"`: 表の全行(行数 `14` を確かめる)。
    - `@test "fails without LOOP_FAILURE_FILE"`: `status -eq 1`、`GITHUB_OUTPUT` に `outcome=` がない。
    - `@test "outcome is resolved before the agent stage is recorded"`: `agent_stage_on_success` の行で、ファイルの段階が `notify_context` かつ outcome が `pr_created`。
    - `@test "pr_push landing failure is error for notify and run log alike"`: `push_target_failed_no_record` の行を名前で呼ぶ(意図した違い。現在の notify は `steps.finalize.outputs.outcome` の `pr_pushed` を表示する)。
    - `@test "re-recording a recorded agent message keeps it unchanged"`: `loop_failure_record "push" "auth failed: x-access-token:ghp_abcdefghijklmnopqrstuvwxyz" "${tmp}"` と、`printf 'a%.0s' {1..600}` の2つで、記録した値を読み、`AGENT_FAILURE_STAGE=push`・`AGENT_FAILURE_MESSAGE=<その値>` で実行した後のファイルの `failure_message` がバイト単位で同じ(前者は `[REDACTED]` を含み `ghp_` を含まない、後者は長さ `500`)。
    - `@test "writes no failure record when nothing failed"`: 表の `success_created`・`rejected`・`unchanged`・`watch_override` で `run loop_failure_recorded "${LOOP_FAILURE_FILE}"` が `status -eq 1`。
- [ ] **Step 2: 失敗を確認する。** `bats test/bats/.github/actions/loop-finalize/lib/resolve_run_outcome.bats`。Expected: Task 3 のテストは PASS、新しいテストは FAIL(スクリプトがない)。
- [ ] **Step 3: 実装する。** Interfaces のとおり。`agent_result` の判定は `case` で `success | skipped) ;;`。`loop_failure_record` の切り詰めとマスクにそのまま任せる(再記録で値が変わらないことは Step 1 のテストで見る)。
- [ ] **Step 4: 通ることを確認する。** Step 2 のコマンド。Expected: PASS(全件)。
- [ ] **Step 5: コミットする。** `git add .github/actions/loop-finalize/lib/resolve_run_outcome.sh test/bats/.github/actions/loop-finalize/lib/resolve_run_outcome.bats`、`feat(loop-finalize): resolve the run-log outcome and failure stage in one script`。

---

### Task 5: `loop-finalize` に Resolve Run Outcome をつなぐ

**Files:**

- Modify: `.github/actions/loop-finalize/action.yml:5-12`(`agent_engine` と `agent_result` の間に入力を2つ)、`:127-135`(出力の説明と `outcome` の値)、`:355` と `:356` の間(Resolve Run Outcome)
- Test: `test/bats/.github/actions/loop-finalize/action_delivery.bats:4-14`(Use cases)、`:63-75`、`:149-154`、`:156-161`、テストを足す

**Interfaces:**

- Consumes `resolve_run_outcome.sh`(Task 4)。
- Produces 入力 `agent_failure_message`・`agent_failure_stage`(既定 `""`、`required: false`。説明は `Failure message (stage) from the agent job (loop-execute failure_message / failure_stage); recorded when no finalize step recorded a failure`)。
- Produces ステップ(Delete Agent Branch の後、Export Failure Diagnostics の直前。キーの並びは Export Failure Diagnostics と同じ `name`・`if`・`id`・`shell`・`env`・`run`):

  ```yaml
  - name: Resolve Run Outcome
    if: always()
    id: run_outcome
    shell: bash
    env:
      ACTION_STATUS: ${{ github.action_status }}
      AGENT_FAILURE_MESSAGE: ${{ inputs.agent_failure_message }}
      AGENT_FAILURE_STAGE: ${{ inputs.agent_failure_stage }}
      AGENT_RESULT: ${{ inputs.agent_result }}
      DELIVERED_OUTCOME: ${{ steps.deliver.outputs.outcome || steps.outcome.outputs.value }}
      LOOP_FAILURE_FILE: ${{ runner.temp }}/loop-finalize-failure.json
    run: bash "${GITHUB_ACTION_PATH}/lib/resolve_run_outcome.sh"
  ```

- Produces 出力:
  - `outcome`: `value: ${{ steps.run_outcome.outputs.outcome }}`、説明 `Final outcome for the run log: error when an earlier step failed or was cancelled, else the delivered or determined outcome`
  - `failure_stage`: 説明 `Failure stage for the run log: the finalize record, else the agent stage, agent_execute, or finalize (empty when nothing failed)`
  - `failure_message`: 説明 `Redacted, truncated failure message for the run log (empty when nothing failed)`
  - Write State の `OUTCOME`(`:321`)は変えない(state は配信の値のまま)。

- [ ] **Step 1: 失敗するテストを書く(`action_delivery.bats`)。**
  - Use cases に `# - Resolve Run Outcome always runs right before Export Failure Diagnostics and owns the outcome output` を足す。
  - `action inputs are the delivery contract in alphabetical order` の期待値の `agent_engine` の後に `agent_failure_message agent_failure_stage` を足す。
  - `steps run in spec order` の期待値の `Delete Agent Branch, Export Failure Diagnostics` を `Delete Agent Branch, Resolve Run Outcome, Export Failure Diagnostics` にする。
  - `outcome output and write state use the delivered outcome` を `@test "outcome output comes from Resolve Run Outcome and write state keeps the delivered outcome"` にする: `grep -c 'value: ${{ steps.run_outcome.outputs.outcome }}'` が `1`、`grep -c 'value: ${{ steps.deliver.outputs.outcome || steps.outcome.outputs.value }}'` が `0`、Write State の `OUTCOME` は今のまま。
  - 足す:
    - `@test "resolve run outcome always runs with the action status and the delivered outcome"`: `step_if "Resolve Run Outcome"` が `always()`、`step_env` が Interfaces の6行と完全一致。
    - `@test "every failure record step uses the same LOOP_FAILURE_FILE"`: Deliver Message、Create PR、Resolve Run Outcome、Export Failure Diagnostics の `step_env` に `LOOP_FAILURE_FILE: ${{ runner.temp }}/loop-finalize-failure.json` がある(件数 `4`)。
    - `@test "resolve run outcome runs the lib script"`: そのステップの `run:` の1行を取り出し、`GITHUB_ACTION_PATH=<repo>/.github/actions/loop-finalize`、`ACTION_STATUS=failure`、`DELIVERED_OUTCOME=pr_created`、`AGENT_RESULT=success`、`LOOP_FAILURE_FILE`・`GITHUB_OUTPUT` を `BATS_TEST_TMPDIR` にして `bash -c` で実行し、`outcome=error` と記録の `finalize` を確かめる。
- [ ] **Step 2: 失敗を確認する。** `bats test/bats/.github/actions/loop-finalize/action_delivery.bats`。Expected: FAIL。
- [ ] **Step 3: 実装する。** Interfaces のとおり。入力と出力はアルファベット順を保つ(ORD-01)。
- [ ] **Step 4: 通ることを確認する。** `bats test/bats/.github/actions/loop-finalize/ test/bats/github-actions/loop-caller-parity.bats`。Expected: PASS(parity は、workflow がまだ新しい入力を渡さないだけで通る)。
- [ ] **Step 5: コミットする。** `git add .github/actions/loop-finalize/action.yml test/bats/.github/actions/loop-finalize/action_delivery.bats`、`feat(loop-finalize): record the run failure stage and final outcome in an always step`。

---

### Task 6: finalize-l1 と finalize-l2 から判断を消す

**Files:**

- Modify: `.github/workflows/ci-loop-agent.yaml`
  - finalize-l1 の Append Run Log(`:366-380`): `failure_message`・`failure_stage` を足し、`outcome`(`:375`)を既定値の形にする。`agent_result`(`:371`)は今のまま。
  - finalize-l2 の Finalize の前のコメント(`:555-559`)、Finalize の `with`(`:566` と `:567` の間に `agent_failure_message: ${{ needs.agent-l2.outputs.failure_message }}`、`agent_failure_stage: ${{ needs.agent-l2.outputs.failure_stage }}`。出力は `:390-391`)
  - Resolve Run Log Metadata(`:597-632`。後ろの空行を含む)を削除する。
  - finalize-l2 の Append Run Log(`:638`、`:640-641`、`:645`)
  - 変えない: Notify Pull Request の `outcome`(`:671`)、finalize-l1 の Finalize(L1 のエージェントには段階の出力がない)
- Modify: `test/bats/.github/actions/loop-finalize/lib/resolve_run_outcome.bats`(Task 3 の YAML のテストと `current_l2_outcome` を消し、ヘッダーから `ci-loop-agent.yaml` の行を消す。表と `output_value` は残す)
- Test: `test/bats/github-actions/loop-caller-parity.bats:9`、`:16`(Use cases)、`:695-702`、テストを足す

**Interfaces:** Append Run Log(両方のジョブ)の該当の行:

```yaml
agent_result: ${{ needs.agent-l1.result }} # finalize-l2 は needs.agent-l2.result
failure_message: ${{ steps.finalize.outputs.failure_message }}
failure_stage: ${{ steps.finalize.outputs.failure_stage || (steps.finalize.outputs.outcome == '' && 'finalize' || '') }}
outcome: ${{ steps.finalize.outputs.outcome || 'error' }}
```

finalize-l2 のコメント(`:555-559` を置き換える):

```yaml
# continue-on-error: a landing, PR, or delivery failure must not stop the
# run log and the PR notification below. loop-finalize resolves the final
# outcome (error when any of its steps failed) and the failure stage; the
# steps below only default an empty outcome to error.
```

- [ ] **Step 1: 失敗するテストを書く(`loop-caller-parity.bats`)。**
  - Use cases の `:9` の `and logs the finalize outcome` を `and logs the loop-finalize outcome and failure stage` に、`:16` を `# - finalize-l2 always runs loop-finalize; loop-run-log receives state_branch with no fallback expression; run-log and notify read loop-finalize outputs with empty-value defaults only` にする。
  - `finalize-l1 run log uses the finalize outcome`(`:695`)を `@test "finalize jobs log the loop-finalize outcome and failure stage with defaults only"` に置き換える。`finalize-l1`・`finalize-l2` のそれぞれで、Append Run Log のブロックに Interfaces の4行(`agent_result` はジョブに合わせる)が `grep -qxF` で一致する。
  - 足す:
    - `@test "finalize jobs keep no run-log decision outside loop-finalize"`: 両方のジョブの `job_block` に `run_log_meta` と `Resolve Run Log Metadata` がない。`grep -E '^ +outcome: '` の行がすべて `          outcome: ${{ steps.finalize.outputs.outcome || 'error' }}` で、件数は finalize-l1 が `1`、finalize-l2 が `2`(Append Run Log と Notify Pull Request)。
    - `@test "finalize-l2 passes the agent failure stage and message to loop-finalize"`: finalize-l2 の Finalize に `agent_failure_message: ${{ needs.agent-l2.outputs.failure_message }}` と `agent_failure_stage: ${{ needs.agent-l2.outputs.failure_stage }}`、finalize-l1 の Finalize に `agent_failure_` がない。
  - `resolve_run_outcome.bats` から Task 3 のテストを消す(この Task で YAML の写し元が消えるため。表は Task 4 のテストが使い続ける)。
- [ ] **Step 2: 失敗を確認する。** `bats test/bats/github-actions/loop-caller-parity.bats`。Expected: FAIL(新しい3件)。
- [ ] **Step 3: 実装する。** Files と Interfaces のとおり。`with` のキーはアルファベット順(ORD-01)。
- [ ] **Step 4: 通ることを確認する。**
  - `bats test/bats/github-actions/loop-caller-parity.bats test/bats/.github/actions/loop-finalize/ test/bats/scripts/self/ci/loop_input_topology.bats`。Expected: PASS(`Every with: key on a pinned loop action ...` は、Task 5 で足した入力で通る)。
  - `grep -A72 '^  finalize-l1:'` を使う既存の2件(`agent-l1 exposes usage_json ...`、`finalize-l1 persists run-log after agent-l1`)が、2行増えた後も通ることを上の実行で確かめる。
  - `git grep -n -e run_log_meta -e 'Resolve Run Log Metadata' -e "steps.finalize.outcome == 'failure'" -- .github test`。Expected: 出力がない。
- [ ] **Step 5: コミットする。** `git add .github/workflows/ci-loop-agent.yaml test/bats/github-actions/loop-caller-parity.bats test/bats/.github/actions/loop-finalize/lib/resolve_run_outcome.bats`、`refactor(loop): read the run-log outcome and failure stage from loop-finalize`。

---

### Task 7: docs

**Files:**

- Modify: `docs/reference/specification.md:400`(`loop-finalize` の行の `outputs include failure_stage / failure_message when finalize PR steps fail` を、`outputs the final run-log outcome and the failure stage / message (finalize record, else the agent stage, agent_execute, or finalize) from Resolve Run Outcome` にする)
- Modify: `docs/reference/specification.md:491`(`loop-finalize` が `agent_failure_stage` / `agent_failure_message` を受け取り、run-log の診断を1つにまとめる。`ci-loop-agent` は出力をそのまま `loop-run-log` と `loop-notify-pr` に渡し、`loop-finalize` が動かなかったときだけ `error` / `finalize` を既定にする)
- Modify: `docs/reference/specification.md:495-501`(入力の表に `agent_failure_message`、`agent_failure_stage` の行。既存の表に並びの規則はないので、表の最初に置く)
- Modify: `docs/reference/specification.md:523`(`error` の Meaning を `Agent or finalize failed, including a cancelled finalize`)
- Modify: `docs/explanation/github-workflows-design.md:148`(`loop-execute` の診断は `loop-finalize` に入り、`loop-finalize` の出力が run-log に入る)
- Modify: `docs/explanation/loop-engineering/workflows/loop-github-issue-triage-workflow-design.md:28`(`failure of finalize-l1 has no failure_stage in the run-log until the run-log outcome change lands` を、`an agent failure is recorded as agent_execute` にする)
- Modify: `.github/actions/loop-run-log/action.yml:7`(`agent job result (success | failure | cancelled | skipped)`)、`:23`(`(push | notify_context | finalize_pr | deliver_message | agent_execute | finalize | …)`)。説明だけで、bats は要らない。
- 変えない: `docs/reference/loop-notify-pr-specification.md:82`(「finalize outcome enum」のままで正しい)、`CHANGELOG.md`(リリースのとき)、`docs/superpowers/`

**Interfaces:** なし(記述だけ)。

- [ ] **Step 1: docs を直す。** DOC-00 に従い、該当する行だけを変える。表の桁揃えは prettier のフックに任せる。
- [ ] **Step 2: 残っていないことを確かめる。** `git grep -n -e 'Resolve Run Log Metadata' -e 'merges execute and finalize diagnostics' -e 'until the run-log outcome change lands' -- docs .github ':!docs/superpowers'`。Expected: 出力がない。
- [ ] **Step 3: コミットする。** `git add docs/reference/specification.md docs/explanation/github-workflows-design.md docs/explanation/loop-engineering/workflows/loop-github-issue-triage-workflow-design.md .github/actions/loop-run-log/action.yml`、`docs(loop): document the run-log outcome resolved in loop-finalize`。

---

### Task 8: 全体の確認

**Files:** なし(確認だけ。直しが要れば、原因の Task のファイルを直して別のコミットにする)。

- [ ] **Step 1: spec の bats。** `bats test/bats/.github/actions/lib/loop/failure_record.bats test/bats/.github/actions/lib/loop/export_failure_diag.bats test/bats/.github/actions/loop-finalize/ test/bats/github-actions/loop-caller-parity.bats`。Expected: PASS。
- [ ] **Step 2: 全部の bats。** `mkdir -p tmp && bats -r test/bats > tmp/bats-run-log-outcome.txt 2>&1; echo $?`。Expected: `0`。確認の後 `rm -f tmp/bats-run-log-outcome.txt`。
- [ ] **Step 3: topology。** `python3 -I scripts/self/ci/loop_input_topology.py . > /dev/null; echo $?`。Expected: `0`(reusable の入力は変えていない)。
- [ ] **Step 4: 作業ツリー。** `git status --porcelain`。Expected: 作業の前からある `.claude/settings.json`、`.cursor/mcp.json`、`.mcp.json`、`apm.lock.yaml`、`.claude/worktrees/` だけ。
- [ ] **Step 5: lint。** actionlint、ghalint、zizmor、shellcheck、markdownlint は Stop フックの結果を見る。直接は実行しない。

---

## リリースと dogfood(手動。この plan の範囲外)

spec は「workflow の変更は `loop-finalize` の SHA pin の更新と同じ変更で出す」としている(`.github/workflows/CLAUDE.md` の Pins)。ユーザーはリリースを後に回すので、ここでは行わない。それまで push しない(Review Focus 5)。

1. 明示の承認を得てから、`scripts/self/ci/pin_config_actions.sh` で `loop-finalize`(`ci-loop-agent.yaml:349`、`:563`)、`ci-loop-agent.yaml`(`ci-loop-caller.yaml:476`、`ci-loop-caller-entity.yaml:327`)、`example/` の pin を1回で上げる。CHANGELOG に、出力 `outcome` の意味の変更(run-log の最終の値)と意図した違い4つを書く。
2. dogfood(使い捨てのブランチ): `pr_create`(例: changelog)、`pr_push`(pr-revise)、`issue_comment`(triage)で run-log の行が今と同じであること。後のステップの失敗(例: 存在しない `to.branch`)で notify と run-log が `error` で一致すること。キャンセルした実行の `github.action_status` の値と run-log の行(Review Focus 3)。`continue-on-error` で失敗した `loop-finalize` の出力が読めること(Review Focus 4)。

## Self-review(writing-plans のチェックリスト)

- **spec の網羅:**
  - 変更「失敗の段階」(always のステップ、`loop_failure_recorded`、新しい入力、優先順位、L1 の `agent_execute`、判断を `lib/` に置く)→ Task 1, 4, 5
  - 変更「outcome」(`ACTION_STATUS`、キャンセル、Determine Outcome より前の失敗、出力の説明)→ Task 4, 5
  - 変更「workflow」(両ジョブの受け渡し、Resolve Run Log Metadata と式の削除、`agent_failure_*`、コメント)→ Task 6
  - 変更「`loop-finalize` が動かなかったとき」(既定値だけ)→ Task 6
  - 変更「notify の変化」→ Task 4(`pr_push landing failure ...`)、Task 6(notify の `outcome:` の形)
  - 変更「pin」→ 「リリースと dogfood(手動)」
  - 検証: 新しいスクリプトの bats(表の全行、`REJECT`、`unchanged`、Determine Outcome より前、キャンセル、記録とステップの失敗、マスクと 500 文字)→ Task 4。parity → Task 6。表として写してから削除 → Task 3(写し)と Task 6(削除)。意図した違いを別のケースに → Task 4、Task 6(スキップの既定値)。docs → Task 7
- **プレースホルダー:** なし。spec が決めていない3点(キャンセルの段階、記録があり `success` のとき、配信の値が空のとき)は Global Constraints と Task 4 で決めた。
- **名前の一貫性:** `loop_failure_recorded` / `resolve_run_outcome.sh` / `resolve_run_outcome` / `record_run_failure` / `Resolve Run Outcome` / `run_outcome` / `agent_failure_stage` / `agent_failure_message` / `ACTION_STATUS` / `DELIVERED_OUTCOME` / `L2_CASES` は Task 1〜8 で同じ綴り。
- **分量:** 判断の表とテストの名前、YAML の行は全文で書き、スクリプトの本体は Interfaces の規則だけにした。

## spec との差(HEAD `8580feb8` で確かめた値)

- 行番号: Resolve Run Log Metadata `:564-598` → `ci-loop-agent.yaml:597-631`。outcome の式 `:612` → `:645`(finalize-l2)、`:375`(finalize-l1)。`needs.agent-l2.outputs.failure_*` `:357-358` → `:390-391`。コメント `:523-527` → `:555-559`。notify `:638` → `:671`。Export Failure Diagnostics `action.yml:315-320` → `:356-362`。`LOOP_FAILURE_FILE` `action.yml:244`・`:318` → `:238`(Deliver Message)、`:287`(Create PR)、`:361`(Export)。`specification.md:509-517` → `:511-523`。
- spec は「Append Run Log の … `agent_failure_*` には `needs.agent-l2.outputs.failure_*` を渡す」とするが、`loop-run-log` にその入力はない。この plan は `loop-finalize`(Finalize のステップ)に渡す。
- 「記録があればステップも失敗していること」の意味が一つに決まらない。この plan は「記録があれば `ACTION_STATUS` に関係なく outcome は `error`」とした。
- キャンセルの段階と、`ACTION_STATUS` が `success` で配信の値が空のときは spec にない。どちらも `finalize` を記録する。
- `loop-notify-pr` の `outcome:` は既に既定値の形(`:671`)で、YAML は変わらない(意味だけが変わる)。
- 現在の finalize-l1 は run-log に `failure_stage` / `failure_message` を渡していない。Task 6 で足す。
- `failure_record.sh:64-65` と `ci-loop-agent.yaml:628-629` は区切りを本文の行に付ける(空でないメッセージで書き出しが失敗する)。spec にない修正として Task 2 に置いた。
