# Issue Autofix and PR Revise Full Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn `issue-autofix` and `pr-revise` from skip-always stubs into full L2 Loop Engineering loops (detect → execute → finalize), wire triage→autofix via a trusted post-detect hook, and add `pr_draft` to finalize — without inventing a new caller profile.

**Architecture:** Keep autofix and revise on `ci-loop-caller` (branch / PR-head). Triage stays on `ci-loop-caller-entity`. Detect owns skip/gates; skills own fix behavior and PR body templates; platform owns `delivery`, `pr_draft`, `git_landing_*`, and invoking the dispatch hook after entity detect. Agent never calls `repository_dispatch`.

**Tech Stack:** Bash, jq, Bats, GitHub Actions (`ci-loop-caller`, `ci-loop-agent`, `loop-finalize`, `loop-entity-detect`), APM skills under `.apm/packages/common/.apm/skills/`

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-11-issue-autofix-pr-revise-full-design.md`
- Edit SoT under `.apm/packages/common/`, `scripts/lib/`, `.github/actions/**`, `.github/workflows/`, `docs/` — do not hand-edit distributed `.agents/` / `.claude/` copies as SoT
- Work on **`main` checkout only** — do **not** create a git worktree
- Do **not** create git commits unless the user explicitly asks (skip any “Commit” habit)
- Do **not** push half-finished stubs: each axis’s detect + skill + caller must be coherent before considering the work publishable
- TDD for shell helpers and detect/hook scripts (Bats RED→GREEN)
- No auto-merge; no Copilot implementer; no mention-less revise triggers
- Skills branch only on `may_edit` / `write_target` — never on `delivery`

## File map

| Path                                                                                | Responsibility                                                |
| ----------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| `.github/actions/loop-finalize/lib/create_pr.sh`                                    | Honor `PR_DRAFT=true` → `gh pr create --draft`                |
| `.github/actions/loop-finalize/action.yml`                                          | New input `pr_draft`; pass `PR_DRAFT` env into create step    |
| `.github/workflows/ci-loop-agent.yaml`                                              | Thread `pr_draft` into finalize                               |
| `.github/workflows/ci-loop-caller.yaml`                                             | New input `pr_draft` (default `false`) → agent                |
| `test/bats/.github/actions/loop-finalize/lib/create_pr.bats`                        | Assert `--draft` when `PR_DRAFT=true`                         |
| `.github/actions/loop-entity-detect/lib/detect.sh`                                  | After successful detect write, invoke optional dispatch hook  |
| `.github/actions/loop-entity-detect/action.yml`                                     | Inputs: hook path / token for dispatch (trusted)              |
| `.apm/packages/common/.apm/skills/issue-triage/scripts/detect_issue.sh`             | Emit dispatch flags when `triage:ready` ∧ `autofix`           |
| `.apm/packages/common/.apm/skills/issue-triage/scripts/hooks/on_detect_dispatch.sh` | Live `repository_dispatch` (migrate from autofix stub)        |
| `.apm/packages/common/.apm/skills/issue-autofix/scripts/hooks/*`                    | Remove stub or leave README pointing at triage hook           |
| `.apm/packages/common/.apm/skills/issue-autofix/scripts/detect_autofix.sh`          | Real detect + Fixes/#N skip                                   |
| `.apm/packages/common/.apm/skills/issue-autofix/SKILL.md` + `assets/` + references  | L2 fix loop + PR body templates                               |
| `.apm/packages/common/.apm/skills/pr-revise/scripts/detect_pr_revise.sh`            | Mention gate + PR number hydrate                              |
| `.apm/packages/common/.apm/skills/pr-revise/SKILL.md` + `assets/` + references      | L2 revise loop + PR body templates                            |
| `.github/workflows/on-loop-issue-autofix.yaml`                                      | L2 planes, `pr_draft`, real skill wiring                      |
| `.github/workflows/on-loop-pr-revise.yaml`                                          | Comment triggers + mention input + `git_landing_pull_request` |
| `.github/workflows/on-loop-issue-triage.yaml`                                       | Pass dispatch hook path + token into entity detect            |
| Docs under `docs/explanation/loop-engineering/`                                     | Replace skeleton wording; status table                        |

---

### Task 1: `pr_draft` on finalize (`create_pr.sh`)

**Files:**

- Modify: `.github/actions/loop-finalize/lib/create_pr.sh`
- Modify: `.github/actions/loop-finalize/action.yml`
- Modify: `test/bats/.github/actions/loop-finalize/lib/create_pr.bats`
- Modify: `.github/workflows/ci-loop-agent.yaml`
- Modify: `.github/workflows/ci-loop-caller.yaml`

**Interfaces:**

- Consumes: existing `gh pr create` arg assembly in `create_pr.sh`
- Produces: env `PR_DRAFT` (`true`/`false`); when `true`, `gh_args` includes `--draft`. Caller input `pr_draft` boolean default `false`

- [ ] **Step 1: Extend mock `gh` and add failing Bats**

In `create_pr.bats` `setup()` mock, record argv when `pr create` runs:

```bash
# Inside mock gh for pr create success path:
printf '%s\n' "$*" > "${GH_ARGV_FILE:-/tmp/gh-argv}"
echo "https://github.com/example/repo/pull/42"
```

Add tests:

```bash
@test "create_pr passes --draft when PR_DRAFT=true" {
    export GH_ARGV_FILE="${BATS_TEST_TMPDIR}/gh-argv"
    # ... same required exports as success test ...
    export PR_DRAFT="true"
    run bash "$(bats_workspace_root)/.github/actions/loop-finalize/lib/create_pr.sh"
    [ "$status" -eq 0 ]
    grep -q -- '--draft' "${GH_ARGV_FILE}"
}

@test "create_pr omits --draft when PR_DRAFT unset or false" {
    export GH_ARGV_FILE="${BATS_TEST_TMPDIR}/gh-argv"
    # ... required exports ...
    export PR_DRAFT="false"
    run bash "$(bats_workspace_root)/.github/actions/loop-finalize/lib/create_pr.sh"
    [ "$status" -eq 0 ]
    ! grep -q -- '--draft' "${GH_ARGV_FILE}"
}
```

Update the existing mock in `setup()` so every successful `pr create` writes argv to `GH_ARGV_FILE` when set.

- [ ] **Step 2: Run Bats — expect RED**

Run: `bats test/bats/.github/actions/loop-finalize/lib/create_pr.bats`
Expected: new draft test FAIL (no `--draft` support yet)

- [ ] **Step 3: Implement `PR_DRAFT` in `create_pr.sh`**

Add global `PR_DRAFT="${PR_DRAFT:-false}"`. After building `gh_args`, before `gh pr create`:

```bash
if [[ ${PR_DRAFT} == "true" ]]; then
    gh_args+=(--draft)
fi
```

- [ ] **Step 4: Wire action + caller + agent**

`loop-finalize/action.yml`:

- Add input `pr_draft` (string/boolean, default `'false'`)
- On create_pr step env: `PR_DRAFT: ${{ inputs.pr_draft }}`

`ci-loop-agent.yaml`:

- Add workflow input `pr_draft` default `false`
- Pass `pr_draft: ${{ inputs.pr_draft }}` into `loop-finalize`

`ci-loop-caller.yaml`:

- Add input `pr_draft` default `false`
- Pass through to `ci-loop-agent`

**Pin note:** `ci-loop-agent` currently pins remote `loop-finalize`. In this PR, either (a) temporarily point that step at `./.github/actions/loop-finalize` for dogfood of `pr_draft`, or (b) after local changes land on the branch, retarget the pin SHA to the commit that contains them. Prefer (a) for local verification consistency with `loop-entity-detect`.

- [ ] **Step 5: Run Bats — expect GREEN**

Run: `bats test/bats/.github/actions/loop-finalize/lib/create_pr.bats`
Expected: PASS

---

### Task 2: Entity detect invokes trusted dispatch hook

**Files:**

- Modify: `.github/actions/loop-entity-detect/lib/detect.sh`
- Modify: `.github/actions/loop-entity-detect/action.yml`
- Modify: `.github/actions/loop-entity-detect/lib/_init.sh` (if new env vars documented there)
- Create: `test/bats/.github/actions/loop-entity-detect/lib/detect_dispatch_hook.bats` (or extend existing entity-detect bats if present)

**Interfaces:**

- Consumes: detect JSON at `DETECT_OUT` with optional `result.dispatch_requested`
- Produces: when hook path set and `dispatch_requested==true`, runs  
  `DISPATCH_HOOK_TOKEN=... bash "$DISPATCH_HOOK_SCRIPT" "$DETECT_OUT"`  
  Non-zero hook exit → detect action fails

- [ ] **Step 1: Write failing Bats for hook invoke**

Stub a detect script that prints:

```json
{ "status": "ok", "skip": false, "result": { "handoff_key": "entity:issue:1", "dispatch_requested": true, "dispatch_event_type": "loop-issue-autofix", "dispatch_client_payload": { "issue_number": "1" } } }
```

Stub hook that writes `invoked` to a temp file and exits 0. Assert file exists after `detect.sh` with `DISPATCH_HOOK_SCRIPT` set.

Second case: `dispatch_requested` absent → hook not invoked.

Third case: hook exits 1 → `detect.sh` exits non-zero.

- [ ] **Step 2: Run — expect RED**

- [ ] **Step 3: Implement invoke in `detect.sh` after detect JSON is written and status is ok, before skip/matrix**

```bash
# After: bash "${DETECT_SCRIPT}" > "${DETECT_OUT}" and status ok
if [[ -n ${DISPATCH_HOOK_SCRIPT:-} ]]; then
    requested="$(jq -r '.result.dispatch_requested // false' "${DETECT_OUT}")"
    if [[ ${requested} == "true" ]]; then
        if [[ ! -f ${DISPATCH_HOOK_SCRIPT} ]]; then
            echo "::error::DISPATCH_HOOK_SCRIPT not found: ${DISPATCH_HOOK_SCRIPT}" >&2
            exit 1
        fi
        GH_TOKEN="${DISPATCH_HOOK_TOKEN:-${GH_TOKEN:-}}" \
            bash "${DISPATCH_HOOK_SCRIPT}" "${DETECT_OUT}"
    fi
fi
```

Only invoke when skip is false **or** always when flag set? Spec: triage may still skip agent work but still want dispatch — prefer: invoke whenever `dispatch_requested==true` regardless of `skip`, as long as detect `status==ok`. Document that in hook README.

Add action inputs:

- `dispatch_hook_script` (optional path)
- `dispatch_hook_token` (optional secret passthrough via env)

- [ ] **Step 4: Run Bats — GREEN**

---

### Task 3: Triage emits dispatch flags + live hook

**Files:**

- Modify: `.apm/packages/common/.apm/skills/issue-triage/scripts/detect_issue.sh`
- Create: `.apm/packages/common/.apm/skills/issue-triage/scripts/hooks/on_detect_dispatch.sh`
- Create: `.apm/packages/common/.apm/skills/issue-triage/scripts/hooks/README.md`
- Modify: `test/bats/.apm/packages/common/issue-triage/detect_issue.bats`
- Create: `test/bats/.apm/packages/common/issue-triage/on_detect_dispatch.bats`
- Delete or rewrite stub under `.apm/packages/common/.apm/skills/issue-autofix/scripts/hooks/` (point README to triage)
- Modify: `.github/workflows/on-loop-issue-triage.yaml` to pass hook path + bot token into entity detect
- Modify: `.apm/packages/common/.apm/skills/issue-triage/SKILL.md` (Agent must not dispatch)

**Interfaces:**

- Produces in detect `result` when labels contain both `triage:ready` and `autofix`:
  - `dispatch_requested: true`
  - `dispatch_event_type: "loop-issue-autofix"`
  - `dispatch_client_payload: {"issue_number":"<N>"}`
- Hook: `gh api repos/{owner}/{repo}/dispatches` with `-f event_type=...` and raw `client_payload` JSON. Env: `GH_TOKEN`, `GITHUB_REPOSITORY`. Support `DISPATCH_DRY_RUN=1` for Bats (log only, exit 0).

- [ ] **Step 1: Failing Bats — detect flags**

When `ISSUE_LABELS_JSON='["triage:ready","autofix"]'` and valid issue number, assert jq:

```bash
jq -e '.result.dispatch_requested == true and .result.dispatch_event_type == "loop-issue-autofix"'
```

When only `triage:ready` (no autofix), assert dispatch_requested is not true.

- [ ] **Step 2: Failing Bats — hook**

With `DISPATCH_DRY_RUN=1`, assert exit 0 and stderr contains event type. With dry-run off and mock `gh`, assert `gh api .../dispatches` invoked.

- [ ] **Step 3: Implement detect flag emission** (after skip checks, when building result object)

- [ ] **Step 4: Implement live hook** (migrate logic from autofix stub; default live, dry-run for tests)

```bash
# Conceptual live call:
gh api "repos/${GITHUB_REPOSITORY}/dispatches" \
  -f event_type="${event_type}" \
  --input - <<< "$(jq -n --argjson p "${payload}" '{client_payload: $p}')"
```

Verify exact `gh api` shape against current `gh` docs in-repo or `gh api --help` before finalizing.

- [ ] **Step 5: Wire `on-loop-issue-triage.yaml`**

Pass into `ci-loop-caller-entity` / `loop-entity-detect`:

- `dispatch_hook_script: .agents/skills/issue-triage/scripts/hooks/on_detect_dispatch.sh`  
  (distributed path after APM sync — if dogfood uses `.apm` checkout path, use the path the runner actually has; match how `detect_script` is already referenced in that workflow)

- Token: same bot/app token used for trusted automation (not Agent session token if separable)

- [ ] **Step 6: Bats GREEN for triage detect + hook**

---

### Task 4: Real `detect_autofix.sh`

**Files:**

- Modify: `.apm/packages/common/.apm/skills/issue-autofix/scripts/detect_autofix.sh`
- Modify: `test/bats/.apm/packages/common/issue-autofix/detect_autofix.bats`

**Interfaces:**

- Env: `ISSUE_NUMBER` (required for non-skip), optional `GITHUB_EVENT_PATH`, `GH_TOKEN`, `GITHUB_REPOSITORY`
- Output when proceed: `status=ok`, `skip=false`, `result.issue_number`, `result.handoff_key` unused on branch caller but may include issue facts for prompt
- Skip when: empty issue number; or `gh` search/list finds open/draft PR with body/title matching  
  `(?i)\b(fix(e[sd)?|close[sd]?|resolve[sd]?)\s+#<N>\b`

- [ ] **Step 1: Replace “always skips” Bats with:**

1. No `ISSUE_NUMBER` → skip true
2. Mock `gh` returning a PR with `Fixes #12` → skip true when `ISSUE_NUMBER=12`
3. Mock `gh` returning empty → skip false, status ok, result includes issue_number

- [ ] **Step 2: RED**

- [ ] **Step 3: Implement detect**

Hydrate `ISSUE_NUMBER` from env or `GITHUB_EVENT_PATH` (`issue.number` / `client_payload.issue_number`). Query open PRs (prefer `gh pr list --state open --json number,title,body,isDraft` and filter in jq). On proceed, emit JSON via existing `json_object` helpers if available.

- [ ] **Step 4: GREEN**

---

### Task 5: `issue-autofix` skill body (L2) + caller

**Files:**

- Modify: `.apm/packages/common/.apm/skills/issue-autofix/SKILL.md`
- Create: `assets/pr-body-template.md`, `assets/pr-body-template-survey.md`
- Create: `references/` as required by `check_loop_pr_body_contract.sh` (copy structure from `docs-updater` / `ci-sweeper` — required headings only, autofix-specific Overview examples)
- Modify: `.github/workflows/on-loop-issue-autofix.yaml`

**Interfaces:**

- Caller planes: `level: L2`, `may_edit: true`, `write_target: fix`, `delivery: open_pr`, `finalize` via caller defaults, `pr_draft: ${{ inputs.pr_draft || false }}`, `git_landing_integration: open_pr`
- Skill: implement fix for Issue; PR body from assets; must include `Fixes #<N>`; do not call `repository_dispatch`

- [ ] **Step 1: Run contract checker to see required files**

Run: `bash scripts/self/apm/check_loop_pr_body_contract.sh` (or repo’s documented invoke) and list missing paths for `issue-autofix`.

- [ ] **Step 2: Add assets + references mirroring a sibling loop skill** (e.g. `docs-updater`), with autofix Overview that mentions `Fixes #N`

- [ ] **Step 3: Rewrite SKILL.md** — remove STUB; document intake, skip rules, Constraints/`may_edit`, PR body synthesis, verifier expectations (no dispatch from Agent)

- [ ] **Step 4: Update `on-loop-issue-autofix.yaml`**

- Add `workflow_dispatch` input `pr_draft` boolean default `false`
- Set L2 planes as above
- `prompt_instructions` / verifier criteria for real autofix (APPROVE when fix+PR path correct; REJECT on dispatch attempts or missing Fixes link)
- Keep concurrency per issue number
- `detect_script` path consistent with other loops

- [ ] **Step 5: Shellcheck + Bats for detect still GREEN; contract checker includes skill**

---

### Task 6: Real `detect_pr_revise.sh`

**Files:**

- Modify: `.apm/packages/common/.apm/skills/pr-revise/scripts/detect_pr_revise.sh`
- Modify: `test/bats/.apm/packages/common/pr-revise/detect_pr_revise.bats`

**Interfaces:**

- Env: `PR_NUMBER`, `PR_MENTION` (default `@loop`), `PR_COMMENT_BODY`, `PR_ACTOR_TYPE`, `GITHUB_EVENT_PATH`
- Skip when: bot actor; missing PR number; comment body does not contain mention token
- Proceed: `skip=false`, result includes `pr_number`, `mention`, comment excerpt facts for prompt

- [ ] **Step 1: Bats cases**

1. Bot actor → skip
2. Human without `@loop` → skip
3. Human with `@loop` and `PR_NUMBER=5` → skip false
4. Custom `PR_MENTION=@waza` matches `@waza` only

- [ ] **Step 2: RED → implement hydrate from `GITHUB_EVENT_PATH` for `issue_comment` / `pull_request_review_comment` → GREEN**

---

### Task 7: `pr-revise` skill + caller

**Files:**

- Modify: `.apm/packages/common/.apm/skills/pr-revise/SKILL.md`
- Create: assets + references for PR body contract
- Modify: `.github/workflows/on-loop-pr-revise.yaml`

**Interfaces:**

- Triggers: `issue_comment` (types that apply to PRs), `pull_request_review_comment`, `repository_dispatch` (`loop-pr-revise`), `workflow_dispatch`
- Inputs: `mention` default `@loop`; `git_landing` choice or hard-default `push_head` with optional input for stacked `open_pr`
- Planes: L2, `may_edit: true`, `write_target: fix`, `delivery: open_pr`, `git_landing_pull_request: push_head` (default)

- [ ] **Step 1: PR body assets + SKILL.md** (apply comment feedback to PR head; stacked only when landing says so)

- [ ] **Step 2: Expand `on-loop-pr-revise.yaml` triggers**

```yaml
on:
  issue_comment:
    types: [created]
  pull_request_review_comment:
    types: [created]
  repository_dispatch:
    types: [loop-pr-revise]
  workflow_dispatch:
    inputs:
      pr_number: ...
      mention:
        default: "@loop"
      git_landing_pull_request:
        description: push_head | open_pr
        default: push_head
```

Job `if:` for `issue_comment`: only when `github.event.issue.pull_request` is set (ignore pure Issue comments).

Pass mention into `detect_domain_env_json` via safe env+jq pattern (no template injection).

- [ ] **Step 3: Bats + contract checker GREEN**

---

### Task 8: Docs and status

**Files:**

- Modify: `docs/explanation/loop-engineering/workflows/loop-issue-autofix-workflow-design.md`
- Modify: `docs/explanation/loop-engineering/workflows/loop-pr-revise-workflow-design.md`
- Modify: `docs/explanation/loop-engineering/loop-engineering-design.md` (status table)
- Modify: `docs/explanation/loop-engineering/multi-branch-loops-design.md` / `index.md` if wording still says skeleton
- Modify: `docs/superpowers/specs/2026-08-11-entity-caller-responsibility-separation-design.md` — add “Implementation: see autofix/pr-revise full design” pointer (optional one-liner)
- Modify: `docs/superpowers/specs/2026-08-11-issue-autofix-pr-revise-full-design.md` — Status → Accepted when docs match

- [ ] **Step 1: Replace skeleton sections with full caller shapes from the spec**

- [ ] **Step 2: Status rows:** `issue-autofix` / `pr-revise` → Dogfood L2 / in progress (not stub)

- [ ] **Step 3: markdown-link-check on touched docs if CI expects it**

---

### Task 9: Integration verification sweep

- [ ] **Step 1: Bats suites**

```bash
bats test/bats/.github/actions/loop-finalize/lib/create_pr.bats
bats test/bats/.github/actions/loop-entity-detect/lib/detect_dispatch_hook.bats
bats test/bats/.apm/packages/common/issue-triage/
bats test/bats/.apm/packages/common/issue-autofix/
bats test/bats/.apm/packages/common/pr-revise/
```

Expected: all PASS

- [ ] **Step 2: Workflow lint on touched YAML**

```bash
actionlint .github/workflows/on-loop-issue-autofix.yaml \
  .github/workflows/on-loop-pr-revise.yaml \
  .github/workflows/on-loop-issue-triage.yaml \
  .github/workflows/ci-loop-caller.yaml \
  .github/workflows/ci-loop-agent.yaml
ghalint run .github/workflows/on-loop-issue-autofix.yaml \
  .github/workflows/on-loop-pr-revise.yaml \
  .github/workflows/on-loop-issue-triage.yaml
```

Expected: no new policy errors (zizmor ignores remain consistent with sibling `on-loop-*`)

- [ ] **Step 3: Confirm no remaining “always skip” stub messages in autofix/pr-revise detect scripts**

```bash
rg -n "stub: not implemented|always skip" \
  .apm/packages/common/.apm/skills/issue-autofix \
  .apm/packages/common/.apm/skills/pr-revise
```

Expected: no matches (or only historical comments in docs)

---

## Spec coverage (self-review)

| Spec requirement                                 | Task       |
| ------------------------------------------------ | ---------- |
| LE Agent implementer, branch caller              | 5, 7       |
| `pr_draft` default open                          | 1          |
| Autofix intake label/dispatch/manual             | 4, 5       |
| Fixes/#N open/draft skip                         | 4          |
| Triage ready∧autofix → dispatch via trusted hook | 2, 3       |
| Agent never dispatches                           | 3, 5 SKILL |
| pr-revise @loop mention + human comments         | 6, 7       |
| Default push_head / optional stacked             | 7          |
| PR body skill templates                          | 5, 7       |
| Docs / completion criteria                       | 8, 9       |
| No half-stub publish                             | Global + 9 |

**Placeholder scan:** none intentional.  
**Type consistency:** `dispatch_requested` / `dispatch_event_type` / `dispatch_client_payload` / `PR_DRAFT` / `PR_MENTION` names stable across tasks.
