# code-review loop(L2、Issue の起票) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** マージ済みのコードを週1回 Claude Code の組み込み `code-review` でレビューし、checker が承認した指摘だけを Issue として起票する L2 loop を作る。

**Architecture:** 基盤に3つの汎用機能を足す(`detect_script` を省略したときの組み込みの範囲検出、`delivery: issue_create`、`agent_tool_denylist`)。code-review 固有のもの(caller、checker の基準、レポートを `issues.json` に変換して根拠を再検証するスクリプト)はリポジトリ専用の側に置く。流れは pr-review の L2 と同じ(maker がレポート → checker → `finalize_script` → Deliver Message)。

**Tech Stack:** bash、jq、gh CLI、GitHub Actions(reusable workflow と composite action)、bats。

**Spec:** `docs/superpowers/specs/2026-11-09-loop-code-review-design.md`(承認済み)。各 Task は spec の節を参照する。spec と食い違ったら spec が正。

## Global Constraints

- 新しい shell の関数は既存のファイルの規約に従う(header の Design Rules、関数の doc の Globals/Arguments/Outputs/Returns、a-z 順)。変更したスクリプトには対の bats を同じ commit で更新する(`.claude/rules/bats.md` BAT-01)。
- bats はテストを足したディレクトリだけを走らせる(全体のスイートは走らせない)。
- `.github/actions/**` と `.github/workflows/ci-*` は配布物。consumer のパスを既定値や分岐に埋め込まない(`.github/workflows/CLAUDE.md`)。composite から別の composite を `uses:` しない。
- 共有のロジックは `.github/actions/lib/loop/` に置く。
- `issue_create` は L2/L3 だけ、integration のターゲットだけ。`finalize_script`、`finalize_label_allowlist` が必須。`agent_unchanged_verdict` は `REJECT` が必須(spec 第3.1節)。
- `agent_tool_denylist` は `agent_engine: claude` かつ branch caller の L2/L3 だけ。それ以外で空でなければ拒否(spec 第4節)。
- 既存の state の意味を変えない。`error` は `consecutive_failures` を増やさない。Write State に `always()` を付けない(spec 第3.5節)。
- `finalize_issue_limit` の既定は `5`。code-review の caller は `3`。
- marker の形式: `<!-- <loop_name>:fp:<hash16> -->`、`hash16 = sha256(loop_name + "\n" + fingerprint)` の先頭16桁。
- プラットフォームが書くパスの除外: `.loop/` 配下、解決済みの `state_file`、`run_log_file`(pathspec で除く)。
- commit メッセージは Conventional Commits。末尾に `Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>`。

## Review Focus

1. **`finalize_script` が REJECT で失敗する。** REJECT のとき何もせず成功しないと、`rejected` が書かれず circuit breaker が効かない → Task 6 に「VERDICT=REJECT で exit 0、何も書かない」のテスト。
2. **重複判定が上限より後になる。** 上限で切ってから重複を除くと、毎回同じ件数が重複に消えて新しい指摘が起票されない → Task 5 に「既存3件 + 新規2件、limit 3 → 新規2件が作られる」のテスト。
3. **到達できない `last_sha` で、プロンプトの `Last SHA` だけが古いまま。** 範囲検出は `$(...)` の中なのでそこで直しても届かない → Task 3 に「到達できない sha の state でプロンプトの `Last SHA` が `HEAD~10` になる」のテスト。
4. **`.loop/` のコミットだけで実行される。** state と run-log の毎回のコミットで、変更0件のスキップが起きない → Task 3 に「`.loop/` と run-log だけの変更で skip」のテスト。
5. **Issue 本文の marker の偽装とメンション。** エージェントの本文に既存の marker が入ると将来の起票を抑止できる → Task 5 に「本文中の `<!-- code-review:fp:` が無害化され、`@user` が通知されない形になる」のテスト。

---

### Task 0: 実装前の確認(手動。コードは書かない)

spec 第4節「確認済みの事実の限界」と第10節の判断の材料を取る。結果で Task 7 の effort と CLI の版を決める。

- [ ] **Step 1: 固定する CLI の版を決める**

Run: `claude --version`
CI で使う版をこの値に固定する(Task 7 の `agent_cli_version`)。

- [ ] **Step 2: maker と同じ権限で `code-review` を動かす**

一時的な worktree(`git worktree add --detach tmp/cr-check HEAD`)で:

```bash
claude -p "Invoke the Skill tool with skill \"code-review\" and args \"medium HEAD~3\". Then write the findings as a JSON array of {title, body, fingerprint, evidence:{path, start_line, end_line}} to .loop-code-review/findings.json (write [] if none). Do not modify any other file." \
  --setting-sources project --permission-mode acceptEdits \
  --allowedTools 'Bash(git diff:*)' 'Bash(git log:*)' 'Bash(git show:*)' 'Bash(git status:*)' \
  --disallowedTools 'Agent' --max-turns 60 --output-format stream-json --verbose < /dev/null > tmp/cr-check.jsonl
```

Expected: `Agent` の tool_use が拒否され、`.loop-code-review/findings.json` が配列として書かれる。

- [ ] **Step 3: 判定**

- `medium` で書ける → Task 7 は effort `medium`。
- 書けない → `low` で Step 2 を繰り返す。`low` でも書けない → **ここで止めて spec を見直す**(spec 第10節)。人間に報告する。
- worktree を消す(`git worktree remove --force tmp/cr-check`)。

---

### Task 1: `issue_create` の契約の検証

**Files:**

- Modify: `.github/actions/lib/loop/delivery.sh`(`validate_delivery_value`、`validate_delivery_target`、`validate_delivery_detect_config`、header の Design Rules)
- Modify: `.github/actions/lib/loop/validate_loop_write_contract.sh`(`validate_loop_write_contract`、`validate_finalize_label_allowlist`、header)
- Modify: `.github/actions/loop-finalize/lib/parse_target.sh`(delivery とターゲットの検査)
- Test: `test/bats/github-actions/loop-delivery.bats`、`test/bats/github-actions/loop-write-contract.bats`、`test/bats/github-actions/loop-detect-delivery.bats`、`test/bats/.github/actions/loop-finalize/lib/parse_target.bats`

**Interfaces:**

- Produces: `issue_create` が検証を通る条件(後続の全 Task の前提)。関数のシグネチャは変えない。

- [ ] **Step 1: 失敗するテストを書く**

`loop-delivery.bats`:

- `validate_delivery_value issue_create` が 0 を返す。
- `validate_delivery_target issue_create '{"mode":"integration"}'` が 0、`'{"mode":"pull_request"}'` と `'{"entity":{"kind":"issue"}}'` が 1。
- `validate_delivery_detect_config issue_create true main` が 1(`detect_pr_enabled`)、`issue_create false ""` が 1(空の branch match)、`issue_create false main` が 0。

`loop-write-contract.bats`:

- L1 で `issue_create` → 1。
- L2 `issue_create`、`finalize_script` 空 → 1。`finalize_label_allowlist` 空 → 1。`agent_unchanged_verdict APPROVE` → 1(エラー文に `REJECT` を含む)。全部そろって `REJECT` → 0。
- `validate_finalize_label_allowlist` が `issue_create` で空でない許可リストを受け付ける。

`parse_target.bats`: `DELIVERY=issue_create` と integration のターゲットで成功、entity で失敗。

- [ ] **Step 2: 失敗を確かめる**

Run: `bats test/bats/github-actions/loop-delivery.bats test/bats/github-actions/loop-write-contract.bats test/bats/github-actions/loop-detect-delivery.bats test/bats/.github/actions/loop-finalize/lib/parse_target.bats`
Expected: 追加したケースが FAIL(`issue_create` は not implemented)。

- [ ] **Step 3: 実装する**

spec 第3.1節のとおり。`validate_delivery_value` の予約の拒否を外す。ターゲットは `mode == integration` だけ。`validate_loop_write_contract` の L1 の分岐は変えない(`none`/`issue_comment` 以外は既に拒否)。L2/L3 の分岐で `issue_create` の必須条件を足す。

- [ ] **Step 4: 通ることを確かめる**

Run: Step 2 と同じ。Expected: PASS(既存のケースも含めて)。

- [ ] **Step 5: Commit**

`git commit -m "feat(loop): validate issue_create delivery contract"`

---

### Task 2: `agent_tool_denylist`

**Files:**

- Modify: `.github/actions/loop-execute/lib/agent.sh`(`append_claude_permission_args`)、`.github/actions/loop-execute/action.yml`(入力 `agent_tool_denylist` → env `AGENT_TOOL_DENYLIST`)
- Modify: `.github/workflows/ci-loop-caller.yaml`、`.github/workflows/ci-loop-agent.yaml`(入力を足し、agent-l2 の `loop-execute` へ渡す。agent-l1 には渡さない)
- Modify: `.github/actions/loop-detect/action.yml`(入力 `agent_engine`、`agent_tool_denylist`)、`.github/actions/lib/loop/validate_loop_write_contract.sh`(新関数)、`.github/actions/loop-detect/lib/detect.sh`(`validate_detect_inputs` から呼ぶ)
- Test: `test/bats/.github/actions/loop-execute/lib/agent.bats`、`test/bats/github-actions/loop-write-contract.bats`、`test/bats/github-actions/loop-caller-parity.bats`

**Interfaces:**

- Produces: `validate_agent_tool_denylist <level> <agent_engine> <agent_tool_denylist>`(0/1)。caller 入力 `agent_tool_denylist`(改行区切りの permission rule。既定 `""`)。Task 7 が使う。

- [ ] **Step 1: 失敗するテストを書く**

- `agent.bats`: `AGENT_TOOL_DENYLIST=$'Agent'` で `append_claude_permission_args` の結果の `--disallowedTools` の後に、既定の deny と `Agent` の両方が入る。空なら既定だけ。
- `loop-write-contract.bats`: `validate_agent_tool_denylist L2 claude Agent` → 0、`L2 codex Agent` → 1、`L1 claude Agent` → 1、`L1 claude ""` → 0。
- `loop-caller-parity.bats`: `ci-loop-caller.yaml` が `agent_tool_denylist` を `loop-detect` と `ci-loop-agent` へ渡す。`ci-loop-agent.yaml` の agent-l1 は渡さない。`ci-loop-caller-entity.yaml` にこの入力がない。

- [ ] **Step 2: 失敗を確かめる**

Run: `bats test/bats/.github/actions/loop-execute/lib/agent.bats test/bats/github-actions/loop-write-contract.bats test/bats/github-actions/loop-caller-parity.bats`
Expected: 追加分が FAIL。

- [ ] **Step 3: 実装する**

`--disallowedTools` に `CLAUDE_PLATFORM_DENY_RULES` の後で caller の値を加える。入力の説明は `agent_tool_allowlist` と同じ形式で書き、「claude のみ、L2/L3 のみ」を明記する。

- [ ] **Step 4: 通ることを確かめる** — Step 2 と同じ。PASS。

- [ ] **Step 5: Commit** — `git commit -m "feat(loop): add agent_tool_denylist for claude makers"`

---

### Task 3: 組み込みの範囲検出

**Files:**

- Create: `.github/actions/loop-detect/lib/range_detect.sh`
- Modify: `.github/actions/loop-detect/lib/detect.sh`(`main` 先頭の `: "${DETECT_SCRIPT:?}"`、`resolve_detect_script_path`、`invoke_detect_script`、`build_integration_target_json` に `from.since`)、`.github/actions/loop-detect/lib/state.sh`(`target_last_sha` に到達の確認の引数)
- Modify: `.github/actions/loop-detect/action.yml`、`.github/workflows/ci-loop-caller.yaml`(`detect_script` を `required: false`、既定 `""`、説明を更新)
- Test: Create `test/bats/.github/actions/loop-detect/lib/range_detect.bats`。Modify `test/bats/.github/actions/loop-detect/lib/state.bats`、`detect.bats`

**Interfaces:**

- Consumes: `list_diff_paths`(`.github/actions/lib/loop/edit_paths.sh`。pathspec を `"$@"` で受ける。rc 1 = git の失敗、rc 2 = 安全でないパスで出力なし)。
- Produces:
  - `range_detect <since> <head> <state_file> <run_log_file>` → stdout に detect JSON。rc 0 / 1。JSON は spec 第2節: skip のとき `{"skip":true}`、それ以外 `{"skip":false,"result":{"since","head","changed_count"},"verifier_context":"..."}`。
  - `target_last_sha <target_state> <branch_ref> [verify_reachable]` — 第3引数が `true` で、保存された sha が `git cat-file -e <sha>^{commit}` で見つからなければ、警告を **stderr** に出して `HEAD~10` のフォールバックを返す。
  - `target_json.from.since`(integration のターゲット。Task 4・6 が使う)。

- [ ] **Step 1: 失敗するテストを書く**(`range_detect.bats`、一時 git repo)

- `range_detect skips when only .loop/ and the run log changed`: `.loop/state-x.json` と run-log のファイルだけを変える → `.skip == true`。
- `range_detect reports changed files and range in verifier_context`: `src/a.sh` を変える → `.skip == false`、`.result.changed_count == 1`、`.verifier_context` が `<since>..<head>` と `src/a.sh` を含む。
- `range_detect runs when list_diff_paths returns 2`: 改行を含むファイル名を追加 → `.skip == false`、`.verifier_context` に範囲だけ。
- `range_detect fails on git error`: 存在しない since → rc 1。

`state.bats`:

- `target_last_sha falls back to HEAD~10 for an unreachable sha when verifying` → 出力が `HEAD~10` の sha と一致、stdout に警告が混ざらない。
- 第3引数なしでは保存された sha をそのまま返す(既存の挙動)。

`detect.bats`:

- `DETECT_SCRIPT` が空のとき、`config_error` にならず range_detect の経路を通る。
- 到達できない sha の state で、candidate の prompt の `Last SHA:` 行がフォールバックの sha になる。
- 既存の `detect_script` を指定したとき、`target_last_sha` に検証の引数を渡さない。
- integration の `target_json` に `from.since` が入る。

- [ ] **Step 2: 失敗を確かめる**

Run: `bats test/bats/.github/actions/loop-detect/lib/`
Expected: 追加分が FAIL。

- [ ] **Step 3: 実装する**

`range_detect` は `list_diff_paths` を pathspec `-- . ':!.loop/' ':!<state_file>' ':!<run_log_file>'` で呼び、rc を `set -e` に頼らず変数で受けて分岐する。`verifier_context` の変更ファイルの一覧は先頭100件で切る。`invoke_detect_script` は `DETECT_SCRIPT` が空なら `range_detect` を呼ぶ。`append_detect_candidate` は `DETECT_SCRIPT` が空のときだけ `target_last_sha` に `true` を渡す。

- [ ] **Step 4: 通ることを確かめる** — Step 2 と同じ。PASS。

- [ ] **Step 5: Commit** — `git commit -m "feat(loop): built-in range detect when detect_script is omitted"`

---

### Task 4: finalize の outcome、state、ブランチの削除、Deliver Message の条件

**Files:**

- Modify: `.github/actions/loop-finalize/lib/determine_outcome.sh`、`resolve_state_write_mode.sh`、`should_delete_rejected_branch.sh`
- Modify: `.github/actions/loop-finalize/action.yml`(Deliver Message の `if`、Delete Agent Branch の delivery の一覧)
- Modify: `.github/actions/loop-run-log/action.yml`(outcome の説明に `issue_created`)
- Test: `test/bats/.github/actions/loop-finalize/lib/determine_outcome.bats`、`resolve_state_write_mode.bats`、`should_delete_rejected_branch.bats`、`test/bats/.github/actions/loop-finalize/action_delivery.bats`

**Interfaces:**

- Produces: outcome `issue_created`。`resolve_state_write_mode` が `issue_create` で APPROVE かつ pushed なら `advance`。

- [ ] **Step 1: 失敗するテストを書く**

- `determine_outcome`: `("", success, true, APPROVE, issue_create, false)` → `issue_created`。`("watch", success, true, APPROVE, issue_create, false)` → `issue_created`(override を無視)。`(..., REJECT, issue_create, ...)` → `rejected`。`push_failed=true` → `error`。
- `resolve_state_write_mode APPROVE true issue_create false true` → `advance`。`REJECT ...` → `metadata`。`push_failed=true` → `metadata`。
- `should_delete_rejected_branch` が `issue_create` で APPROVE のときも削除する(`pr_review` と同じ)。
- `action_delivery.bats`: Deliver Message の `if` が `issue_create` を含み、`issue_create` の分岐は `verdict == 'APPROVE'`、かつ `agent_result == 'success'` と push の失敗なしの条件を保つ。Write State の `if` に `always()` がない。

- [ ] **Step 2: 失敗を確かめる**

Run: `bats test/bats/.github/actions/loop-finalize/`
Expected: 追加分が FAIL。

- [ ] **Step 3: 実装する**

spec 第3.2節・第3.5節。`determine_outcome` の `issue_create` の分岐は、`push_failed` の検査の後、override の検査の前に置く(`delivery == issue_create && verdict == APPROVE → issue_created`、`verdict == REJECT → rejected`)。

- [ ] **Step 4: 通ることを確かめる** — Step 2 と同じ。PASS。

- [ ] **Step 5: Commit** — `git commit -m "feat(loop): finalize outcome and state for issue_create"`

---

### Task 5: Deliver Message の `issue_create`(起票、重複判定、上限)

**Files:**

- Modify: `.github/actions/lib/loop/deliver_message.sh`(新関数と `deliver_loop_message` の分岐)
- Modify: `.github/actions/lib/loop/loop_message.sh`(`loop_message_to_json` / `from_json` が `issues.json` を運ぶ。L2 では使わないが、`message_json` の形をそろえる)
- Modify: `.github/actions/loop-finalize/action.yml`(入力 `finalize_issue_limit`、env `FINALIZE_ISSUE_LIMIT`)、`.github/workflows/ci-loop-agent.yaml`、`.github/workflows/ci-loop-caller.yaml`、`.github/actions/loop-detect/action.yml`(入力の配線。既定 `5`)
- Test: `test/bats/.github/actions/lib/loop/deliver_message.bats`、`loop_message.bats`、`test/bats/github-actions/loop-caller-parity.bats`

**Interfaces:**

- Consumes: Task 1 の検証、Task 4 の outcome。
- Produces:
  - `deliver_issue_create`(Globals: `LOOP_MESSAGE_DIR`、`LOOP_NAME`、`FINALIZE_LABEL_ALLOWLIST`、`FINALIZE_ISSUE_LIMIT`、`GITHUB_REPOSITORY`、`GH_TOKEN`、`GITHUB_OUTPUT`)。成功 0、失敗 1。`GITHUB_OUTPUT` に 0件なら `outcome=unchanged`。
  - `issue_fingerprint_hash <loop_name> <fingerprint>` → 16桁の16進。
  - `sanitize_issue_body <loop_name> <body>` → 既存の marker(`<!-- <loop_name>:fp:`)を壊し、`@name` を `@​name` 相当にする。

- [ ] **Step 1: 失敗するテストを書く**(既存の `mock_gh` を使う)

- `issue_fingerprint_hash code-review "a.sh:f:null"` が `printf 'code-review\na.sh:f:null' | sha256sum` の先頭16桁と一致。
- `issues.json` が `[]` → gh を呼ばず `outcome=unchanged`。
- `issues.json` がない、または配列でない、または `title` 欠落 → rc 1、`fail_loop_message` の記録。
- 既存の Issue 3件(marker あり、open 2・closed 1)と新規2件、limit 3 → 新規2件だけ作られる(Review Focus 2)。
- 新規5件、limit 3 → 3件作られ、切った2件の題名と指紋が step summary に出る。
- 同じ実行の中で同じ指紋2件 → 1件だけ作られる。
- `gh issue create` に `finalize_label_allowlist` の全ラベルが付き、本文の先頭に marker、末尾に Meta。
- 一覧の取得は `gh api --paginate` で、`labels=` に全ラベルをカンマ区切りで渡し `state=all`。
- 本文中の `<!-- code-review:fp:` と `@user` が無害化される(Review Focus 5)。
- 2件目の作成で失敗 → rc 1、作成済みの1件目の番号が step summary に出る。

`loop_message.bats`: `issues.json` だけがあるディレクトリで `loop_message_to_json` が `{"issues":[...]}` を含む JSON を返し、`from_json` が戻す。

`loop-caller-parity.bats`: `finalize_issue_limit` が ci-loop-caller → ci-loop-agent → loop-finalize と loop-detect に渡り、既定が `5`。

- [ ] **Step 2: 失敗を確かめる**

Run: `bats test/bats/.github/actions/lib/loop/deliver_message.bats test/bats/.github/actions/lib/loop/loop_message.bats test/bats/github-actions/loop-caller-parity.bats`
Expected: 追加分が FAIL。

- [ ] **Step 3: 実装する**

手順は spec 第3.3節の順(検証 → 指紋 → 重複を除く → 上限 → 1件ずつ作る)。title は256文字、body は60000文字を上限とし、超えたら検証の失敗。

- [ ] **Step 4: 通ることを確かめる** — Step 2 と同じ。PASS。

- [ ] **Step 5: Commit** — `git commit -m "feat(loop): deliver issue_create with fingerprint dedup and limit"`

---

### Task 6: `render_code_review_issues.sh`(リポジトリ専用の finalize_script)

**Files:**

- Create: `scripts/self/loop/render_code_review_issues.sh`
- Test: Create `test/bats/scripts/self/loop/render_code_review_issues.bats`

**Interfaces:**

- Consumes: env `VERDICT`、`EXECUTE_BRANCH`(エージェントのブランチ)、`TARGET_JSON`(`from.since`、`from.ref`。Task 3)、`LOOP_MESSAGE_DIR`、`GITHUB_STEP_SUMMARY`。レポート `.loop-code-review/findings.json` の形: `[{"title","body","fingerprint","evidence":{"path","start_line","end_line"}}]`。
- Produces: `LOOP_MESSAGE_DIR/issues.json`(`[{"title","body","fingerprint"}]`。body の末尾に根拠のパスと行)。Task 7 が `finalize_script` に指定する。

- [ ] **Step 1: 失敗するテストを書く**(一時 git repo と bare remote)

- `exits 0 and writes nothing when VERDICT is REJECT`(Review Focus 1)。
- `exits 0 and writes nothing when the agent branch does not exist on origin`。
- `fails when from.since or from.ref is missing or unreachable`(APPROVE のとき)。
- `fails when findings.json is not an array`(APPROVE のとき)。
- `keeps findings whose evidence overlaps changed lines and drops others`: `since..ref` で `src/a.sh` の 10-12 行を変更。evidence が `src/a.sh:11-11` の指摘は残り、`src/a.sh:40-41` と `src/b.sh:1-1` は落ちる。落とした件数と理由が step summary に出る。
- `writes [] when every finding is dropped`。

- [ ] **Step 2: 失敗を確かめる**

Run: `bats test/bats/scripts/self/loop/render_code_review_issues.bats`
Expected: FAIL(スクリプトがない)。

- [ ] **Step 3: 実装する**

変更行は `git diff --unified=0 <since> <ref> -- <path>` の hunk ヘッダ(`+start,count`)から取る。レポートは `git show origin/<EXECUTE_BRANCH>:.loop-code-review/findings.json` で読む。

- [ ] **Step 4: 通ることを確かめる** — Step 2 と同じ。PASS。

- [ ] **Step 5: Commit** — `git commit -m "feat(loop): render code-review findings into issues with evidence check"`

---

### Task 7: caller、予算、Renovate、不変条件10の検査

**Files:**

- Create: `.github/workflows/on-loop-code-review.yaml`
- Modify: `.loop/loop-budget.json`(`code-review` を追加)、`.github/renovate.json`(regex マネージャ)
- Modify: 権限の4ファイル(`.claude/settings.json`、`.cursor/cli.json`、`.cursor/permissions.json`、`.lean-ctx.toml`)は **変えない**(新しいコマンドはない)
- Test: `test/bats/github-actions/loop-caller-parity.bats`(不変条件10と caller の検査)

**Interfaces:**

- Consumes: Task 1〜6 の全入力。

- [ ] **Step 1: 失敗するテストを書く**(`loop-caller-parity.bats`)

- `issue_create callers never apply an intake label`: `delivery: issue_create` の全 caller の `finalize_label_allowlist` に `autofix`、`needs-triage`、`triage:needs-info` が含まれない。
- `on-loop-code-review uses L2 issue_create with REJECT on unchanged and denies Agent`: `level: L2`、`delivery: issue_create`、`agent_unchanged_verdict: REJECT`、`agent_tool_denylist` に `Agent`、`agent_cli_version` が `latest` でない、`concurrency.group: loop-state-main`、`detect_script` がない、`finalize_issue_limit: 3`。
- `loop-budget has a code-review entry`。

- [ ] **Step 2: 失敗を確かめる**

Run: `bats test/bats/github-actions/loop-caller-parity.bats`
Expected: FAIL。

- [ ] **Step 3: 実装する**

caller の値は spec 第4節の表のとおり。maker と checker の指示文は spec 第4節の `agent_maker_instructions` と `agent_checker_instructions` の内容を英語で書く(既存の on-loop と同じ言語)。`agent_checker_model` は maker より強いモデル(既存の on-loop と同じく checker を opus 系、maker を sonnet 系)。effort と CLI の版は Task 0 の結果。予算は tech-debt の値(`max_runs_per_day: 2` 等)を出発点にする。schedule は既存の on-loop の cron と重ならない曜日と時刻。Renovate は `on-loop-code-review.yaml` の `agent_cli_version:` を `@anthropic-ai/claude-code` の npm として追い、`automerge: false`。

- [ ] **Step 4: 通ることを確かめる** — Step 2 と同じ。PASS。actionlint 等は Stop フックに任せる。

- [ ] **Step 5: Commit** — `git commit -m "feat(loop): add on-loop-code-review caller"`

---

### Task 8: ドキュメント

**Files:**(spec 第11節の一覧すべて)

- Modify: `docs/explanation/loop-engineering/loop-engineering-design.md`、`docs/explanation/loop-engineering/workflows/loop-caller-inputs-reference.md`、`docs/reference/specification.md`、`docs/explanation/loop-engineering/common-loop-triage-format.md`、`docs/explanation/loop-engineering/CONTEXT.md`、`docs/superpowers/specs/2026-10-17-loop-delivery-plan-design.md`
- Create: `docs/explanation/loop-engineering/workflows/loop-code-review-workflow-design.md`
- Modify: `mkdocs.yml`(nav)
- Modify: Task 1〜5 で触った入力の `description:`(`delivery` と `finalize_label_allowlist` の列挙)と、スクリプトの header の Design Rules(Task の中で直していなければ)

- [ ] **Step 1: spec 第11節の各項目を反映する**

workflow 設計書には運用(事前に `loop:code-review` ラベルを作る、ラベルを外さない、週1回の not planned 率の確認、Pause / Slow Down / Kill、state のスキーマ、書き込みトークンは GitHub App)を書く。

- [ ] **Step 2: 確認**

Run: `grep -rn 'issue_create' docs/ .github/ | grep -i 'reserved\|not implemented\|予約'`
Expected: 出力なし(古い「予約」の記述が残っていない)。markdown の lint はフックに任せる。

- [ ] **Step 3: Commit** — `git commit -m "docs(loop): document issue_create, built-in range detect, code-review loop"`

---

### Task 9: SHA pin の更新とリリース(人間の確認が必要)

dogfood の caller は `./ci-loop-caller.yaml` を使うが、その中の `loop-detect`、`loop-run-log`、`ci-loop-agent` と、`ci-loop-agent.yaml` の中の `loop-execute`、`loop-finalize` は SHA で固定されている。新しいコードを動かすには pin を2段で更新する(`.github/workflows/CLAUDE.md` の Pins)。

- [ ] **Step 1: 人間に確認する**

リリース(タグ)の作成と push は外部に出る操作なので、手順と対象の SHA を示して承認を取る。

- [ ] **Step 2: 承認の後、既存のリリース手順で更新する**

action のリリース → `ci-loop-agent.yaml` の `loop-execute` / `loop-finalize` の pin → `ci-loop-caller.yaml` の `loop-detect` / `loop-run-log` / `ci-loop-agent` の pin。`test/bats/.github/pin_config_actions.bats` を走らせる。

- [ ] **Step 3: 初回の実行**

`gh workflow run on-loop-code-review.yaml` で1回動かし、Issue が起票されるか(または0件で cursor が進むか)を確かめる。
