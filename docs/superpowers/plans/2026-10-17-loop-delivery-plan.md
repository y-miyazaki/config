# Loop Delivery Plan Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make each loop decision depend on one declared value. Delivery is decided by `delivery`. Level-dependent validation is decided by `level`. Every input name is changed to follow the spec's naming rule.

**Architecture:** One new shared library, `.github/actions/lib/loop/delivery.sh`, does three things: it derives `pr_auto_merge`, validates targets against `delivery`, and decides when to skip `pr_push`. Both detect actions call it and expose the derived values as job outputs. The reusable workflows pass those outputs straight through, with no expressions in between. `loop-finalize` branches on `delivery` alone. Old outcome values that are already persisted get mapped to the new names by `.github/actions/lib/loop/outcome.sh`.

**Tech Stack:** GitHub Actions (reusable workflows and composite actions), bash, jq, bats.

**Spec:** `docs/superpowers/specs/2026-10-17-loop-delivery-plan-design.md`. Section numbers in this plan (§N) refer to the spec. Appendix A of the spec is the per-input source of truth for the new name, the levels where the input takes effect, and how the input is handled.

## Global Constraints

- Names use snake_case. The domain comes first: `agent_`, `detect_`, `finalize_`, `pr_`, `state_`, `budget_`/`run_log_`, `trigger_`. Only `delivery`, `level`, `loop_name` and `environment` have no prefix (§1).
- The same value has the same name at every layer: caller input, action input, `target_json`, prompt key, and env var (uppercase). Runtime-only data (`target_json`, `verdict`, `has_changes`, `.result.*`, the role vars `EFFORT`/`MODEL`/`MAX_TURNS`/`PROMPT`/`USAGE_ROLE`/`WORKING_DIRECTORY`) keeps its current name.
- `delivery` ∈ {`issue_comment`, `issue_create`, `none`, `pr_create`, `pr_push`, `pr_review`}. Only `none`, `pr_create` and `pr_push` pass validation. The others fail closed.
- `delivery` and `level` have no default at any layer. If either is empty, validation fails.
- There is no compatibility layer that accepts both old and new input names. Old outcome **values** are the exception: they are mapped permanently (§8).
- Distributed skills are edited only under `.apm/packages/`. After editing, run `scripts/self/apm/sync_apm_artifacts.sh` and commit the sync targets in the same commit.
- Every shell change ships with its bats change (`.claude/rules/bats.md`). Run `shfmt -w` after editing any `.sh` file with Edit.
- Task 1 ships alone. Tasks 2–15 are done on one branch and reach `main` in a single push via `scripts/self/ci/pin_config_actions.sh` (Task 15). Nothing is pushed before that.

## Review Focus

1. **`pr_push` with `detect_pr_number` equal to `0` or empty.** Expected: detect exits 0 with `should_run=false` and `skip_reason=pr_number_missing`, and the run-log gets `skipped`. It must not fail the job. Covered in Task 2 and Task 6.
2. **`agent_edit_allowlist: "**"`.** Expected: the prompt is byte-identical to today's prompt with an empty allowlist, with no `Allowed paths:` line. Covered in Task 5.
3. **Persisted old outcomes (`merged`, `pr-created`, `pr-closed`, `no-changes`, `no-action`) in existing `.loop/` files.** Expected: prune, notify, meta icons and ledgers treat them exactly like their new names. Covered in Task 3, Task 8, Task 10 and Task 13.
4. **`write_state.sh` advance-mode refusal.** Expected: it triggers on `pr_pushed`, not on `pr_created`. A literal rename of `pr-created` to `pr_created` would silently disable it. Covered in Task 8.
5. **`loop-agent-once` with `AGENT_MAKER_MODEL`/`AGENT_MAKER_EFFORT`/`AGENT_MAKER_MAX_TURNS`.** Expected: L1 triage still runs with the caller's model, effort and max_turns and does not fall back to CLI defaults. Covered in Task 9.

---

### Task 1: Fix the ci-sweeper ledger path (separate release)

**Files:**

- Modify: `.apm/packages/repo-maintenance/.apm/skills/ci-sweeper/scripts/update_run_ledger.sh:47`
- Test: `test/bats/.apm/packages/repo-maintenance/ci-sweeper/update_run_ledger.bats`

**Interfaces:** Produces: when `CI_SWEEPER_LEDGER_FILE` is unset, the ledger is written to `.loop/state-ci-sweeper-run-ledger.json`.

- [ ] **Step 1: Write the failing test.** Add `@test "update_run_ledger defaults ledger to .loop/state-ci-sweeper-run-ledger.json"`. Unset `CI_SWEEPER_LEDGER_FILE`, run the script in a temp repo with `OUTCOME=rejected`, and assert `[ -f .loop/state-ci-sweeper-run-ledger.json ]` and `[ ! -f ci-sweeper-run-ledger.json ]`.
- [ ] **Step 2: Run the test and confirm it fails.** Run `bats test/bats/.apm/packages/repo-maintenance/ci-sweeper/update_run_ledger.bats`. Expected: the new test FAILS.
- [ ] **Step 3: Change the default.** Set `LEDGER_FILE="${CI_SWEEPER_LEDGER_FILE:-.loop/state-ci-sweeper-run-ledger.json}"`. Update the header comment to say the same thing as test-gap's `update_test_gap_ledger.sh:15-17`.
- [ ] **Step 4: Run the suite and confirm it passes.** Run the same command. Expected: PASS.
- [ ] **Step 5: Sync and commit.** Run `scripts/self/apm/sync_apm_artifacts.sh`, then `git add` the source, the sync targets and the bats file. Commit with `fix(ci-sweeper): write run ledger under .loop so finalize commits it`.
- [ ] **Step 6: Release this change on its own,** following the normal flow. After the next ci-sweeper finalize run, confirm that `.loop/state-ci-sweeper-run-ledger.json` exists on `main`. This closes the spec's open question about §9.

---

### Task 2: The delivery library

**Files:**

- Create: `.github/actions/lib/loop/delivery.sh`
- Test: `test/bats/github-actions/loop-delivery.bats`

**Interfaces:** Produces (all functions are pure, write errors as `::error::` on stderr, and return 0 or 1):

- `derive_pr_auto_merge <level> <delivery>`: prints `true` when `level == L3 && delivery == pr_create`, and `false` otherwise.
- `validate_delivery_value <delivery>`: returns 0 only for `none`, `pr_create` and `pr_push`. For `issue_comment`, `issue_create` and `pr_review` it returns 1 with the message "not implemented". For anything else, including empty, it returns 1.
- `validate_delivery_detect_config <delivery> <detect_pr_enabled> <detect_branch_match>`. Branch callers only. When `delivery == pr_push`, it requires `detect_pr_enabled == true` and an empty `detect_branch_match`. For every delivery, it requires `detect_branch_match` to be non-empty or `detect_pr_enabled == true` (§7-3).
- `delivery_requires_pr_number_skip <delivery> <detect_pr_number>`: returns 0, meaning skip, when `delivery == pr_push` and the number is empty or `0`.
- `validate_delivery_target <delivery> <target_json>`. The kind comes from `.mode` (`integration` or `pull_request`) or, for entity targets, from `.entity.kind` (`issue` or `pr`). Allowed kinds: `none` and `pr_create` allow every kind, and `pr_push` allows only `pull_request`.

- [ ] **Step 1: Write the failing tests.** Add one `@test` per row:
  - `derive_pr_auto_merge` over {L1, L2, L3} × {none, pr_create, pr_push}. Only `L3 pr_create` prints `true`.
  - `validate_delivery_value`: 3 accepted values, 3 "not implemented" values, plus `open_pr`, `log` and empty, which are rejected.
  - `validate_delivery_detect_config`:
    - `pr_push true ""` passes.
    - `pr_push true main` fails.
    - `pr_push false ""` fails.
    - `pr_create false ""` fails.
    - `pr_create false main` passes.
    - `pr_create true ""` passes (pr-revise manual dispatch).
  - `delivery_requires_pr_number_skip`:
    - `pr_push ""` returns 0.
    - `pr_push 0` returns 0.
    - `pr_push 12` returns 1.
    - `pr_create ""` returns 1.
  - `validate_delivery_target`:
    - `pr_push` + `{"mode":"integration"}` fails.
    - `pr_push` + `{"mode":"pull_request"}` passes.
    - `pr_create` + `{"entity":{"kind":"pr"}}` passes.
    - `none` + `{"entity":{"kind":"issue"}}` passes.
- [ ] **Step 2: Write the golden test.** Freeze the old behavior as a table inside the bats file. For each old combination in (`open_pr`|`none`) × `git_landing_integration` (`open_pr`|`push`) × `git_landing_pull_request` (`open_pr`|`push_head`) × `level` (L1|L2|L3) × target set ({integration}, {pull_request}, {both}), the table holds the old per-target `finalize` from `detect.sh:907-936` and the old `auto_merge` from `ci-loop-caller.yaml:499`. Map each row with the rule in spec "検証" (`open_pr`→`pr_create`, `push_head`→`pr_push`, `none`→`none`; mixed targets or `push` are unmappable). Assert:
  - Every mappable row satisfies `derive_pr_auto_merge` == old `auto_merge`.
  - Every mappable row passes `validate_delivery_target` for each of its targets.
  - Every unmappable row fails `validate_delivery_target` for at least one target.
- [ ] **Step 3: Run the tests and confirm they fail.** Run `bats test/bats/github-actions/loop-delivery.bats`. Expected: FAIL because `delivery.sh` does not exist.
- [ ] **Step 4: Implement the five functions** in `delivery.sh`. Follow the header and doc-block style of `validate_loop_write_contract.sh` (Globals, Arguments, Outputs and Returns, with functions in a-z order).
- [ ] **Step 5: Run the tests and confirm they pass.** Run the same command. Expected: PASS.
- [ ] **Step 6: Commit** with `feat(loop): add delivery plan library`.

---

### Task 3: The outcome normalization library

**Files:**

- Create: `.github/actions/lib/loop/outcome.sh`
- Test: `test/bats/github-actions/loop-outcome.bats`

**Interfaces:** Produces `normalize_outcome <value>`. It prints the new name for an old value: `pr-created`→`pr_created`, `merged`→`pr_merged`, `pr-closed`→`pr_closed`, `no-changes`→`unchanged`, `no-action`→`unchanged`. Every other value, including new names and empty, is printed unchanged.

- [ ] **Step 1: Write the failing tests.** Add one `@test` per mapping and one per passthrough: `pr_pushed`, `rejected`, `reported`, `skipped`, `error`, `watch`, `escalated` and the empty string.
- [ ] **Step 2: Run the tests and confirm they fail.** Run `bats test/bats/github-actions/loop-outcome.bats`. Expected: FAIL.
- [ ] **Step 3: Implement** the function as a single `case` statement.
- [ ] **Step 4: Run the tests and confirm they pass.** Run the same command. Expected: PASS.
- [ ] **Step 5: Commit** with `feat(loop): add outcome normalization for persisted values`.

---

### Task 4: Level-keyed write-contract validation

**Files:**

- Modify: `.github/actions/lib/loop/validate_loop_write_contract.sh`
- Test: `test/bats/github-actions/loop-write-contract.bats` (replace the cases that check `may_edit`)

**Interfaces:**

- Produces `validate_loop_write_contract <level> <delivery> <agent_edit_target> <agent_edit_allowlist> <agent_edit_denylist> <agent_unchanged_verdict>`. This replaces the old 4-argument signature, so every caller changes in Tasks 6 and 7.
- Consumes `validate_delivery_value` from Task 2.

- [ ] **Step 1: Rewrite the bats file from the §6 table.** For every cell, add one test that passes and one that fails:
  - **L1.** `delivery` must be `none`. Any non-empty value in the other four fields fails.
  - **L2 and L3.** `delivery` must be `pr_create`, `pr_push` or `none`.
  - **L2 and L3, other fields:**
    - `agent_edit_target` must be `fix` or `report`, and empty fails.
    - `agent_edit_allowlist` must be non-empty, and `**` passes.
    - `agent_edit_denylist` may be anything, including empty.
    - `agent_unchanged_verdict` must be `APPROVE` or `REJECT`, and empty fails.
  - **Any level.** An empty `level` fails, and so does `L4`.
- [ ] **Step 2: Run the tests and confirm they fail.** Run `bats test/bats/github-actions/loop-write-contract.bats`. Expected: FAIL.
- [ ] **Step 3: Implement the new signature.** Rewrite the file's header Design Rules to the §6 table.
- [ ] **Step 4: Run the tests and confirm they pass.** Run the same command. Expected: PASS.
- [ ] **Step 5: Commit** with `refactor(loop): key write contract validation on level`.

---

### Task 5: Prompt constraints and checker criteria

**Files:**

- Modify: `.github/actions/lib/loop/build_constraints.sh` (delete `emit_loop_constraints_from_level:119` and `emit_loop_constraints_legacy:164`)
- Modify: `.github/actions/loop-execute/lib/agent_output_format_criteria.md:7-22`
- Test: `test/bats/github-actions/loop-build-constraints.bats`

**Interfaces:**

- Produces `emit_loop_constraints <level> <agent_edit_target> <agent_edit_allowlist> <agent_report_file>`.
- `agent_edit_allowed` is derived inside the function: `false` for L1 and `true` for L2 and L3.
- The emitted keys are `agent_edit_allowed`, `agent_edit_target` and `agent_report_file`.

- [ ] **Step 1: Write the failing tests.**
  - The L1 output contains `agent_edit_allowed: false` and no `agent_edit_target` line.
  - The L2 `fix` output contains `agent_edit_allowed: true` and `agent_edit_target: fix`.
  - The L2 `report` output with a report file contains `agent_report_file: <path>`.
  - For `**`, the output equals the output for an empty allowlist, with no `Allowed paths:` line (Review Focus 2).
  - For `docs/**`, the output contains `Allowed paths: docs/**`.
  - No output contains `may_edit`, `write_target` or `report_file:` as a key.
- [ ] **Step 2: Run the tests and confirm they fail.** Run `bats test/bats/github-actions/loop-build-constraints.bats`. Expected: FAIL.
- [ ] **Step 3: Implement the change.**
  - Rename the keys in the emitted lines and in the instruction sentences at `:79` and `:86`.
  - Treat `**` the same as empty for the `Allowed paths` line.
  - Update the criteria markdown to resolve mode from `agent_edit_allowed`, `agent_edit_target` and `agent_report_file`.
- [ ] **Step 4: Run the tests and confirm they pass.** Run the same command. Expected: PASS.
- [ ] **Step 5: Commit** with `refactor(loop): rename prompt constraint keys`.

---

### Task 6: loop-detect

**Files:**

- Modify: `.github/actions/loop-detect/action.yml`
- Modify: `.github/actions/loop-detect/lib/{_init.sh,branches.sh,detect.sh,matrix.sh,prs.sh}`
- Test: the `loop-detect/lib/*.bats` and `test/bats/github-actions/loop-detect-*.bats` files listed in spec "影響を受ける箇所"

**Interfaces:**

- Consumes Tasks 2, 4 and 5.
- Produces the action outputs `delivery` and `pr_auto_merge` (string `true`/`false`), plus `skip_reason=pr_number_missing` when the run is skipped.
- Inputs follow the new names in Appendix A: `state_branch`, `detect_branch_match`, `detect_branch_match_mode`, `detect_max_targets`, `detect_pr_enabled`, `detect_pr_denylist`, `detect_pr_bot_allowlist`, `detect_priority`, `detect_pr_number`, `agent_edit_allowlist`, `agent_edit_denylist`, `agent_unchanged_verdict`, `agent_edit_target`, `delivery` and `level`.
- Removed inputs: `may_edit`, `git_landing_integration` and `git_landing_pull_request`.

- [ ] **Step 1: Update the bats files first.**
  - Rename the env vars the tests set: `LOOP_*` becomes the uppercase new names, `BASE_BRANCH` becomes `STATE_BRANCH`, and `ALLOWLIST` becomes `AGENT_EDIT_ALLOWLIST`.
  - Add these tests:
    - An empty `detect_branch_match` yields no integration targets (no fallback to `state_branch`).
    - Validation failure exits 1, where today it skips with `config_error`.
    - `pr_push` with `detect_pr_number=0` or empty writes `should_run=false` and `skip_reason=pr_number_missing`, and exits 0.
    - `target_json` has no `finalize` and no `report_file` key.
    - The detect JSON key `agent_report_file` reaches the prompt and `verifier_context` (`matrix.sh:73-74`, `lib/loop/verifier_context.sh:117`).
    - `STATE_BRANCH` is exported to skill scripts in place of `DEFAULT_BASE_BRANCH` (`detect.sh:438`).
    - The outputs include `pr_auto_merge`.
- [ ] **Step 2: Run the tests and confirm they fail.** Run `bats test/bats/.github/actions/loop-detect/lib test/bats/github-actions/loop-detect-*.bats`. Expected: FAIL.
- [ ] **Step 3: Implement the changes.**
  - Remove `resolve_git_finalize_strategies` (`detect.sh:907-936`) and the `finalize` argument of the target builders (`:302-372`). Remove the defaults at `:500`, `:535` and `:957`.
  - Call `validate_loop_write_contract` (Task 4), then `validate_delivery_value` and `validate_delivery_detect_config`, then `delivery_requires_pr_number_skip`. After filtering, call `validate_delivery_target` on each target. Write `pr_auto_merge` from `derive_pr_auto_merge`.
  - Remove the `branch_state` monitor fallback (`branches.sh:93-106`, `detect.sh:1223`).
  - Stop adding `target_json.report_file` (`detect.sh:829-846`).
- [ ] **Step 4: Run the tests and confirm they pass.** Run the same command. Expected: PASS.
- [ ] **Step 5: Commit** with `refactor(loop-detect): one-value delivery and renamed inputs`.

---

### Task 7: loop-entity-detect

**Files:**

- Modify: `.github/actions/loop-entity-detect/{action.yml,lib/detect.sh,lib/entity_target.sh,lib/outputs.sh}`
- Test: `test/bats/.github/actions/loop-entity-detect/lib/{entity_target,detect_dispatch_hook}.bats`, `test/bats/github-actions/loop-entity-detect.bats`

**Interfaces:**

- Consumes Tasks 2, 4 and 5.
- Produces outputs that match Task 6 (`delivery`, `pr_auto_merge`) and `target_json.entity`, which equals `{handoff_key}` merged with `result.entity`.
- Adds the inputs `agent_edit_allowlist`, `agent_edit_denylist` and `agent_unchanged_verdict`, and renames `dispatch_hook_script` to `detect_hook_script`.
- Removes `may_edit`, `dispatch_hook_token` and the defaults at `action.yml:25-28` and `:43-46` and `detect.sh:46-47`.

- [ ] **Step 1: Write the failing tests.**
  - A missing `result.entity.kind`, or a value other than `issue`/`pr`, fails when `skip=false` and is ignored when `skip=true`.
  - `target_json.entity` keeps `handoff_key` and also carries `kind`.
  - The prompt contains the given `agent_edit_allowlist` (`entity_target.sh:69` no longer hardcodes it to empty).
  - Empty `delivery` or `level` fails.
  - The dispatch hook always uses the detect token.
  - `target_json` has no `finalize` (`entity_target.sh:175`), and there is no duplicate `handoff_key` field in the matrix row (`:189`).
- [ ] **Step 2: Run the tests and confirm they fail.** Run `bats test/bats/.github/actions/loop-entity-detect/lib test/bats/github-actions/loop-entity-detect.bats`. Expected: FAIL.
- [ ] **Step 3: Implement the changes.** In `outputs.sh:43`, write `pr_auto_merge`.
- [ ] **Step 4: Run the tests and confirm they pass.** Run the same command. Expected: PASS.
- [ ] **Step 5: Commit** with `refactor(loop-entity-detect): entity kind, renamed inputs, delivery plan`.

---

### Task 8: loop-finalize

**Files:**

- Modify: `.github/actions/loop-finalize/action.yml`
- Modify: `.github/actions/loop-finalize/lib/{determine_outcome,should_push_target,should_delete_rejected_branch,write_state,prune_targets,create_pr,create_pr_body,render_pr_body,push_target}.sh`
- Test: the `test/bats/.github/actions/loop-finalize/` files listed in the spec (including `action_domain_persistence_env.bats`), and `test/bats/github-actions/loop-{write-state,prune-targets,delete-rejected-branch}.bats`

**Interfaces:**

- Consumes `normalize_outcome` from Task 3.
- New inputs: `delivery` (replaces the `finalize_strategy` taken from `target_json`), `pr_auto_merge`, `state_branch` (required), `finalize_hook_script`, `finalize_commit_paths`, `finalize_outcome_override` and `agent_engine`.
- Removed inputs: `base_branch`, `detect_result_json`, `level`, `state_push_branch` and `auto_merge`.
- The env var `SKIP_STATE_PR` becomes `STATE_PR_SKIP`.
- Produces `determine_outcome <override> <agent_result> <has_changes> <verdict> <delivery>`, which prints `pr_created` for `pr_create`, `pr_pushed` for `pr_push`, `reported` for `none`, and `unchanged` in place of `no-changes`.

- [ ] **Step 1: Write the failing tests.**
  - `determine_outcome` gives the three APPROVE-with-changes rows of the §3 table, and `unchanged` for APPROVE without changes.
  - `should_push_target` and `should_delete_rejected_branch` take `delivery`. `pr_push` is the old `push_head`, and `none` is the old `none`.
  - The `write_state.sh` advance-mode fallback refusal fires on `pr_pushed` and does not fire on `pr_created` (Review Focus 4).
  - `prune_targets.sh` treats both `pr-closed` and `pr_closed` as closed.
  - An empty `TARGET_JSON` fails, where today it falls back to `open_pr` (`action.yml:155`, `:160`).
  - The PR base comes from `target_json`.
  - The ci-sweeper PR body still shows the Failure context through the handoff-resolved `DETECT_RESULT_JSON` (`create_pr_body.sh:238`, `render_pr_body.sh:625`).
  - The step name searched by `action_domain_persistence_env.bats` is renamed to match `finalize_hook_script`.
- [ ] **Step 2: Run the tests and confirm they fail.** Run `bats test/bats/.github/actions/loop-finalize test/bats/github-actions/loop-write-state.bats test/bats/github-actions/loop-prune-targets.bats test/bats/github-actions/loop-delete-rejected-branch.bats`. Expected: FAIL.
- [ ] **Step 3: Implement the changes.**
  - Branch every step on `delivery` only (§3).
  - `Enable Auto-Merge` runs only when `pr_auto_merge == 'true'`.
  - The hook step runs whenever finalize runs, regardless of `delivery`.
- [ ] **Step 4: Run the tests and confirm they pass.** Run the same command. Expected: PASS.
- [ ] **Step 5: Commit** with `refactor(loop-finalize): branch on delivery and rename outcomes`.

---

### Task 9: loop-execute, loop-agent-once, loop-install-cli, loop-worktree-setup

**Files:**

- Modify: `.github/actions/loop-execute/{action.yml,lib/paths.sh,lib/common.sh,lib/loop.sh,lib/agent.sh,lib/mcp.sh,lib/verifier.sh,lib/notify_context.sh}`
- Modify: `.github/actions/loop-agent-once/{action.yml,lib/run.sh}`
- Modify: `.github/actions/loop-install-cli/{action.yml,lib/install.sh}`
- Modify: `.github/actions/loop-worktree-setup/action.yml`
- Test: `test/bats/.github/actions/loop-execute/lib/{paths,common,verifier,agent,notify_context,loop}.bats`, `loop-agent-once/lib/run.bats`, `loop-install-cli/lib/install.bats`

**Interfaces:**

- Renames, applied to inputs and their env vars: `agent_engine`, `agent_cli_version`, `agent_tool_allowlist`, `agent_commit_message`, `agent_checker_path_pattern`, `agent_edit_allowlist`, `agent_edit_denylist`, `agent_unchanged_verdict` and `finalize_outcome_override` (output).
- `loop-agent-once` inputs become `agent_maker_effort`, `agent_maker_max_turns` and `agent_maker_model`.
- `loop-worktree-setup` inputs become `from_branch`, `from_ref` and `agent_branch_prefix`.
- `detect_result_json` is removed from the `loop-execute` inputs.
- The `REJECT` defaults are removed (`action.yml:96-97`, `common.sh:109`, `verifier.sh:249`).

- [ ] **Step 1: Write the failing tests.**
  - `run.sh` maps `AGENT_MAKER_MODEL`, `AGENT_MAKER_EFFORT` and `AGENT_MAKER_MAX_TURNS` to `MODEL`, `EFFORT` and `MAX_TURNS` before it calls `run_agent` (Review Focus 5).
  - `install.sh` reads `AGENT_ENGINE` and `AGENT_CLI_VERSION`.
  - An empty `AGENT_UNCHANGED_VERDICT` at L2 is an error and no longer defaults to `REJECT`.
  - `paths.sh` reads `AGENT_EDIT_ALLOWLIST` and `AGENT_EDIT_DENYLIST`.
- [ ] **Step 2: Run the tests and confirm they fail.** Run `bats test/bats/.github/actions/loop-execute/lib test/bats/.github/actions/loop-agent-once test/bats/.github/actions/loop-install-cli`. Expected: FAIL.
- [ ] **Step 3: Implement the renames.**
- [ ] **Step 4: Run the tests and confirm they pass.** Run the same command. Expected: PASS.
- [ ] **Step 5: Commit** with `refactor(loop-execute): rename agent inputs to the naming rule`.

---

### Task 10: loop-notify-pr, loop-run-log, loop-state-promote

**Files:**

- Modify: `.github/actions/loop-notify-pr/{action.yml,lib/notify.sh}`
- Modify: `.github/actions/loop-run-log/action.yml`
- Modify: `.github/actions/loop-state-promote/{action.yml,lib/run.sh}`
- Modify: `.github/actions/lib/loop/loop_meta.sh:147`
- Test: `test/bats/.github/actions/loop-notify-pr/lib/notify.bats`, `loop-run-log/lib/{append,run}.bats`, `loop-state-promote/` bats, `lib/loop/loop_meta.bats`

**Interfaces:**

- `loop-notify-pr` inputs: `pr_auto_merge` (replaces `auto_merge`), `agent_loop_max_attempts` (replaces `max_attempts`) and `agent_engine`. `level` is removed.
- `loop-run-log` input: `state_branch`, which is required and has no default.
- `loop-state-promote` inputs: `state_branch` (required) and `state_pr_skip`. It writes `pr_merged` and `pr_closed`.

- [ ] **Step 1: Write the failing tests.**
  - The L3 next-step text in `notify.sh` depends only on `PR_AUTO_MERGE`.
  - `notify.sh:207` matches both `pr-created` and `pr_created` through `normalize_outcome`.
  - `loop_meta.sh` gives `unchanged` and `no-changes` the same icon.
  - The `run.sh` promotion writes `pr_merged` and `pr_closed`.
  - An empty `STATE_BRANCH` fails, and the `gh repo view` fallback at `run.sh:286-297` is gone.
  - The run-log `skip_reason` description lists `pr_number_missing`.
- [ ] **Step 2: Run the tests and confirm they fail.** Run `bats test/bats/.github/actions/loop-notify-pr test/bats/.github/actions/loop-run-log test/bats/.github/actions/loop-state-promote test/bats/.github/actions/lib/loop/loop_meta.bats`. Expected: FAIL.
- [ ] **Step 3: Implement the changes.**
- [ ] **Step 4: Run the tests and confirm they pass.** Run the same command. Expected: PASS.
- [ ] **Step 5: Commit** with `refactor(loop): rename notify, run-log, and state-promote inputs`.

---

### Task 11: The reusable workflows

**Files:**

- Modify: `.github/workflows/{ci-loop-caller,ci-loop-caller-entity,ci-loop-agent}.yaml`
- Test: `test/bats/github-actions/loop-caller-parity.bats`

**Interfaces:** Consumes the action interfaces from Tasks 6–10. Caller inputs follow Appendix A (new names, deletions, and `delivery`/`level` required). The `ci-loop-agent` inputs `finalize_enabled`, `detect_result_json`, `handoff_key`, `current_sha` and `base_branch` are removed.

- [ ] **Step 1: Replace the parity assertions** at `:33-42`, `:44-` and `:127-128` with these tests:
  - Neither caller contains `finalize_enabled` or an `auto_merge` expression.
  - Both callers pass `pr_auto_merge: ${{ needs.detect.outputs.pr_auto_merge }}`.
  - `finalize-l2` runs `loop-finalize` with no step `if:`.
  - `delivery` and `level` are `required: true` in both callers and have no `default:`.
  - `ci-loop-agent` passes `state_branch` to `loop-run-log` with no `||` expression.
  - `agent-l2` Parse Target has no fallback when `target_json` is empty.
- [ ] **Step 2: Run the tests and confirm they fail.** Run `bats test/bats/github-actions/loop-caller-parity.bats`. Expected: FAIL.
- [ ] **Step 3: Rewire the three workflows.** Pass the detect outputs straight through. Derive the key, the ref and the base inside `ci-loop-agent.yaml` from `target_json`. Leave the SHA pins as they are; Task 15 bumps them.
- [ ] **Step 4: Run the tests and confirm they pass.** Run the same command. Expected: PASS. The actionlint, ghalint and zizmor Stop hooks must also be clean.
- [ ] **Step 5: Commit** with `refactor(loop): one-value wiring in reusable workflows`.

---

### Task 12: Dogfood callers

**Files:**

- Modify: all 10 `.github/workflows/on-loop-*.yaml` and `on-loop-state-promote.yaml:59`

**Interfaces:** Consumes the caller inputs from Task 11.

- [ ] **Step 1: Apply the §1 mapping and the §7-4 deletions to each caller.**
  - Seven loops become `delivery: pr_create`.
  - pr-revise:
    - becomes `pr_push`;
    - drops `branch_match`;
    - its `workflow_dispatch` input becomes `delivery` (`type: choice`, options `pr_push` and `pr_create`).
  - pr-review and triage stay `none`.
  - Add `level: L2` to docs-updater and ci-sweeper.
  - Triage drops these lines: `write_target`, `allowlist`, `denylist` and `no_changes_verdict`.
  - In autofix, pr-revise and pr-review, change `allowlist: ""` to `agent_edit_allowlist: "**"`.
  - Delete the plumbing lines that repeat a default.
  - `on-loop-state-promote.yaml` passes `state_branch: main`.
  - Update the comments and checker text at `on-loop-github-pr-revise.yaml:3`, `:43` and `:94`, and at `on-loop-github-pr-review.yaml:7-10` and `:71`.
- [ ] **Step 2: Add the topology gate.**
  - Create `scripts/self/ci/loop_input_topology.py` by merging the spec's Appendix A generator scripts (`topology.py`, `appendix.py`, `annotate.py`). Its decision table is keyed by the **new** names.
  - Interface: `python3 -I scripts/self/ci/loop_input_topology.py <repo_root>` prints the table. It exits non-zero in two cases: a caller input has no annotation, or one of the §6 inputs (`agent_edit_allowlist`, `agent_edit_denylist`, `agent_unchanged_verdict`, `agent_edit_target`, `delivery`, `level`) does not reach detect in either reusable.
  - Add `test/bats/scripts/self/ci/loop_input_topology.bats`, which runs the script on the repo and asserts exit 0.
- [ ] **Step 3: Run the gate.** Run `bats test/bats/scripts/self/ci/loop_input_topology.bats`. Expected: PASS.
- [ ] **Step 4: Commit** with `refactor(loop): migrate dogfood callers to the new delivery inputs`.

---

### Task 13: Distributed skills

**Files:**

- Modify, under `.apm/packages/github/.apm/skills/`: `github-issue-autofix`, `github-issue-triage`, `github-pr-review` and `github-pr-revise`.
- Modify, under `.apm/packages/repo-maintenance/.apm/skills/`: `changelog`, `ci-sweeper`, `docs-updater`, `refactor`, `tech-debt` and `test-gap`.
- In each skill: `SKILL.md`, `references/`, `assets/`, `evals/` (rename eval files whose names contain `may-edit`) and `scripts/`.
- Test: `test/bats/.apm/packages/**` for these skills, and `test/bats/support/common.bash:360`, `:385`.

**Interfaces:**

- Prompt keys: `agent_edit_allowed`, `agent_edit_target` and `agent_report_file`.
- Detect JSON key: `agent_report_file`.
- `result.entity.kind` must be written by `detect_issue.sh` (`issue`) and `detect_pr_review.sh` (`pr`).
- `result.report_path` stays unchanged.

- [ ] **Step 1: Write the failing tests.**
  - `detect_issue.bats` and `detect_pr_review.bats` assert `.result.entity.kind`.
  - The tech-debt detect output keys include `agent_report_file`. Update the exact-set assertion in `common.bash`.
  - The ci-sweeper and test-gap ledger scripts map old outcomes with their own table. Test-gap records `pr_created` and `pr_pushed` and skips `unchanged`, `no-action` and `no-changes`. ci-sweeper treats `pr_created` and `pr_pushed` as landed and records `unchanged`.
  - `detect_ci_failures.sh` no longer reads `DEFAULT_BASE_BRANCH` and keeps its other fallbacks (§7-1).
- [ ] **Step 2: Run the tests and confirm they fail.** Run `bats test/bats/.apm/packages`. Expected: FAIL.
- [ ] **Step 3: Implement the changes.**
  - Edit the sources.
  - Grep the 10 skills for `may_edit`, `write_target`, `report_file`, `open_pr` and `pr-created`. Fix every hit, and for `open_pr` keep the hits that mean "open PR".
  - Run `scripts/self/apm/sync_apm_artifacts.sh`.
- [ ] **Step 4: Run the tests and confirm they pass.** Run the same command. Expected: PASS.
- [ ] **Step 5: Commit** the sources and the sync targets with `refactor(skills): adopt renamed loop prompt keys and outcomes`.

---

### Task 14: Documentation

**Files:**

- Modify: the docs listed in spec "影響を受ける箇所 / docs"
- Modify: `.github/workflows/CLAUDE.md` (the `open_pr` and `push_head` rules become `pr_create` and `pr_push`; remove `push`)
- Modify: `.apm/CLAUDE.md` (the `may_edit` row)

- [ ] **Step 1: Update every listed doc** to the new names, values and outcomes. In `docs/explanation/loop-engineering/workflows/loop-caller-inputs-reference.md`, regenerate the input table from Appendix A.
- [ ] **Step 2: Verify.** The markdownlint and link-check Stop hooks must be clean, and `mkdocs build` must pass.
- [ ] **Step 3: Commit** with `docs(loop): document one-value delivery and renamed inputs`.

---

### Task 15: Final gates and release

**Files:** none new. This task uses the gate from Task 12.

- [ ] **Step 1: Run the topology gate.** Run `python3 -I scripts/self/ci/loop_input_topology.py .`. Expected: exit 0.
- [ ] **Step 2: Grep for old names.** Grep the repo, excluding `.loop/` and `docs/superpowers/`, for:
  - every left column of the spec's rename tables;
  - every deleted input;
  - the old values `open_pr` (as a delivery), `push_head`, `pr-created`, `no-changes` and `no-action`, except inside `outcome.sh` and the ledger mapping tables;
  - the old prompt keys;
  - the old env vars listed in spec "影響を受ける箇所".

  Expected: no hits.

- [ ] **Step 3: Run the full bats suite.** Run `bats -r test/bats`. Expected: all pass.
- [ ] **Step 4: Check dogfood before release.**
  - Create a disposable branch from the work branch. Bump the pins there with `pin_config_actions.sh --no-push`, and set `state_branch` (and `detect_branch_match` for branch callers) to the disposable branch name.
  - Dispatch each loop once.
  - For pr-revise and ci-sweeper, open a test PR against the disposable branch and set `detect_pr_number` to it.
  - Confirm each run in that branch's run-log, then close the test PR and delete both branches. Nothing from this step is merged.
- [ ] **Step 5: Ask the user to approve the push.** First, list the open PRs that pr-revise or ci-sweeper could target and whose head does not contain the release (spec Migration step 4), so the user can rebase them after the push.
- [ ] **Step 6: Release.** After approval, run `scripts/self/ci/pin_config_actions.sh` (it commits the pins, tags and pushes once). After release, confirm one successful run per loop in `.loop/loop-run-log.md`.
