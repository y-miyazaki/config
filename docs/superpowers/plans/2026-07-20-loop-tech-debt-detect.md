# loop-tech-debt Detect Layer Implementation Plan

> **Superseded:** Package and skill were renamed to `loop-tech-debt` (`detect_tech_debt.sh`). See [loop-tech-debt plan](2026-07-20-loop-tech-debt.md). Retained for historical task context only.
>
> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add facts-only `detect_tech_debt.sh` (full-repo default) with markers/deps/docs/churn sensors, closed `kind` schema updates, and matching Bats — no workflow caller yet.

**Architecture:** Single entry script under the APM skill `scripts/`, sourcing synced `lib/all.sh`. Sensors are functions in a-z order; always exit 0 with JSON. Docs links use self-contained pinned `markdown-link-check@3.14.2` install; failure → `warnings[]` + skip that sensor only. LLM skill remains classify-only.

**Tech Stack:** bash, git, jq (tests), node/npm (docs sensor), markdown-link-check 3.14.2, bats

**Spec:** [loop-tech-debt Detect Layer Design](../specs/2026-07-20-loop-tech-debt-detect-design.md)

## Global Constraints

- Edit APM sources under `.apm/packages/loop-tech-debt/` only for skill/script; regenerate distributed trees with `apm install --update` when needed.
- Script DOC/structure must match `detect_changes.sh` / `detect_ci_failures.sh` + `shell-script.instructions.md` (`#######################################` headers; Arguments/Global Variables/Returns on every function; `show_usage` → `parse_arguments` → a-z → `main`).
- Default `SCOPE=all` (full repo). Accept `staged`/`range` for loop-detect parity.
- Exit 0 always; errors in JSON `status=error`.
- Do not emit lint-territory smells (complexity/style/unused).
- No `on-loop-tech-debt.yaml` in this plan.
- No dual broken-link implementations (mlc only; no bash existence fallback).
- No new-technology / migration playbook text beyond one explicit out-of-scope line.
- Bats path: `test/bats/.apm/packages/loop-tech-debt/detect_tech_debt.bats` (same layout as sibling loops).
- `scripts/lib/` only via `bash scripts/self/ai/sync_skill_lib.sh` (never hand-edit skill lib copies).
- Pin: `markdown-link-check@3.14.2` (matches `mise.toml`).

## File map

| Path                                                                                  | Role                                                     |
| ------------------------------------------------------------------------------------- | -------------------------------------------------------- |
| `.apm/packages/loop-tech-debt/.apm/skills/loop-tech-debt/scripts/detect_tech_debt.sh` | Detect entry (create)                                    |
| `.apm/packages/loop-tech-debt/.apm/skills/loop-tech-debt/scripts/lib/*`               | Synced from `scripts/lib/`                               |
| `test/bats/.apm/packages/loop-tech-debt/detect_tech_debt.bats`                        | Suite (create)                                           |
| `test/bats/support/common.bash`                                                       | Add `assert_detect_tech_debt_*_json` helpers             |
| `references/category-input-schema.md`                                                 | Closed kinds + `warnings[]`                              |
| `references/category-debt-taxonomy.md`                                                | Lint exclusion + no migration playbook                   |
| `references/common-checklist.md`                                                      | Markers secondary; detect vs lint                        |
| `SKILL.md`                                                                            | Version bump only if needed; keep “do not run detection” |

---

### Task 1: Scaffold script + lib sync + CLI/empty JSON + bats skeleton

**Files:**

- Create: `.apm/packages/loop-tech-debt/.apm/skills/loop-tech-debt/scripts/detect_tech_debt.sh`
- Create: `test/bats/.apm/packages/loop-tech-debt/detect_tech_debt.bats`
- Modify: `test/bats/support/common.bash` (assert helpers)
- Run: `bash scripts/self/ai/sync_skill_lib.sh` (creates `scripts/lib/`)

**Interfaces:**

- Produces: `detect_tech_debt.sh` CLI `--scope|--since|-h`; JSON keys `status`, `scope`, `since`, `skip`, `signals`, `hotspots`, `warnings` (and `message` on error)
- Produces: `assert_detect_tech_debt_ok_json` / `assert_detect_tech_debt_error_json`

- [ ] **Step 1: Write failing bats (CLI + empty skip)**

Create `test/bats/.apm/packages/loop-tech-debt/detect_tech_debt.bats`:

```bash
#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .apm/packages/loop-tech-debt/.apm/skills/loop-tech-debt/scripts/detect_tech_debt.sh
#
# Use cases:
# - detect_tech_debt defaults to scope all and skips on empty fixture repo
# - detect_tech_debt rejects unknown --scope
# - detect_tech_debt range without --since returns error JSON exit 0

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

DETECT_SCRIPT="$(apm_skill_script_path loop-tech-debt detect_tech_debt.sh)"

@test "detect_tech_debt defaults to scope all and skips on empty fixture repo" {
    git_test_repo_setup
    printf 'ok\n' > "${GIT_TEST_REPO}/README.md"
    git -C "${GIT_TEST_REPO}" add README.md
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    git_test_repo_run "bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    assert_detect_tech_debt_ok_json "${output}" "all" ""
    [[ $output == *'"skip": true'* ]]
}

@test "detect_tech_debt rejects unknown --scope" {
    git_test_repo_setup
    touch "${GIT_TEST_REPO}/file.txt"
    git -C "${GIT_TEST_REPO}" add file.txt
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    git_test_repo_run "bash '${DETECT_SCRIPT}' --scope weird"
    [ "$status" -eq 0 ]
    assert_detect_tech_debt_error_json "${output}" "scope"
}

@test "detect_tech_debt range without --since returns error JSON exit 0" {
    git_test_repo_setup
    touch "${GIT_TEST_REPO}/file.txt"
    git -C "${GIT_TEST_REPO}" add file.txt
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    git_test_repo_run "bash '${DETECT_SCRIPT}' --scope range"
    [ "$status" -eq 0 ]
    assert_detect_tech_debt_error_json "${output}" "requires --since"
}
```

Add to `test/bats/support/common.bash` before the final `export -f` block:

```bash
# assert_detect_tech_debt_ok_json: Validate detect_tech_debt.sh success JSON
function assert_detect_tech_debt_ok_json {
    local json="$1"
    local expected_scope="${2:-all}"
    local expected_since="${3:-}"

    jq -e --arg expected_scope "${expected_scope}" --arg expected_since "${expected_since}" '
        def signal_object:
            type == "object"
            and (.kind | type == "string" and length > 0)
            and (.path | type == "string" and length > 0)
            and (.line | type == "number")
            and (.snippet | type == "string")
            and (.source | type == "string" and length > 0)
            and (if has("hint") then .hint | type == "string" else true end);
        def hotspot_object:
            type == "object"
            and (.path | type == "string" and length > 0)
            and (.metric | type == "string" and length > 0)
            and (.value | type == "number")
            and (.window | type == "string" and length > 0);
        type == "object"
        and (.status == "ok")
        and .scope == $expected_scope
        and (.since | type == "string")
        and ($expected_since == "" or .since == $expected_since)
        and (.skip | type == "boolean")
        and (.signals | type == "array")
        and (.hotspots | type == "array")
        and (.warnings | type == "array" and all(type == "string"))
        and (.signals | all(signal_object))
        and (.hotspots | all(hotspot_object))
        and (if .skip then (.signals | length) == 0 and (.hotspots | length) == 0 else (.signals | length) > 0 or (.hotspots | length) > 0 end)
    ' <<< "${json}"
}

# assert_detect_tech_debt_error_json: Validate detect_tech_debt.sh error JSON
function assert_detect_tech_debt_error_json {
    local json="$1"
    local expected_message="${2:-}"

    jq -e --arg expected_message "${expected_message}" '
        type == "object"
        and .status == "error"
        and (.scope | type == "string")
        and (.since | type == "string")
        and .skip == true
        and (.signals | type == "array" and length == 0)
        and (.hotspots | type == "array" and length == 0)
        and (.warnings | type == "array")
        and (.message | type == "string" and length > 0)
        and ($expected_message == "" or (.message | contains($expected_message)))
    ' <<< "${json}"
}
```

Also append to the `export -f` list:

```bash
export -f assert_detect_tech_debt_ok_json assert_detect_tech_debt_error_json
```

- [ ] **Step 2: Run bats — expect FAIL (script missing)**

```bash
bats test/bats/.apm/packages/loop-tech-debt/detect_tech_debt.bats
```

Expected: FAIL resolving/running `detect_tech_debt.sh`.

- [ ] **Step 3: Create scripts dir, sync lib, implement scaffold**

```bash
mkdir -p .apm/packages/loop-tech-debt/.apm/skills/loop-tech-debt/scripts
bash scripts/self/ai/sync_skill_lib.sh
```

Implement `detect_tech_debt.sh` skeleton (full DOC header matching siblings). Required behavior for this task:

- `SCOPE` default `"all"`
- `declare -a SIGNALS_JSON=() HOTSPOTS_JSON=() WARNINGS=()`
- `show_usage` / `parse_arguments` / `output_error` / `output_json` / `main`
- `main`: parse → (later sensors) → `output_json`
- `output_json`: `skip=true` when both arrays empty; emit `warnings` via `json_string_array`
- Signal/hotspot object builders can be stubs unused until later tasks

Minimal `output_json` / `output_error` pattern (mirror ci-sweeper):

```bash
function output_error {
    local message="$1"
    json_object_start
    json_field_string "status" "error" ","
    json_field_string "scope" "${SCOPE}" ","
    json_field_string "since" "${SINCE_REF}" ","
    json_field_bool "skip" "true" ","
    json_field_array "signals" "[]" ","
    json_field_array "hotspots" "[]" ","
    json_field_array "warnings" "$(json_string_array "${WARNINGS[@]}")" ","
    json_field_string "message" "${message}" ""
    json_object_end
    exit 0
}
```

Header must document Design Rules: facts only; exit 0; full-repo default; no lint smells; self-contained mlc for docs; source `lib/all.sh`.

- [ ] **Step 4: Re-run bats — expect PASS for Task 1 tests**

```bash
bats test/bats/.apm/packages/loop-tech-debt/detect_tech_debt.bats
```

- [ ] **Step 5: Commit** (only if user requested commits)

```bash
git add .apm/packages/loop-tech-debt/.apm/skills/loop-tech-debt/scripts \
  test/bats/.apm/packages/loop-tech-debt/detect_tech_debt.bats \
  test/bats/support/common.bash
git commit -m "$(cat <<'EOF'
feat(loop-tech-debt): scaffold detect_tech_debt CLI and JSON contract

EOF
)"
```

---

### Task 2: Marker signals (secondary)

**Files:**

- Modify: `detect_tech_debt.sh` — add `collect_marker_signals`, `append_signal`, prune helpers
- Modify: `detect_tech_debt.bats` — marker tests

**Interfaces:**

- Consumes: git work tree at cwd
- Produces: signals with `kind` ∈ `todo_comment|fixme|hack|xxx`, `source=git_grep`, optional `hint=code_quality`
- Caps: per-file and global (constants `MARKER_PER_FILE_CAP=10`, `MARKER_GLOBAL_CAP=50`); on truncate append warning string

- [ ] **Step 1: Add failing bats**

```bash
@test "detect_tech_debt emits todo_comment and fixme marker signals" {
    git_test_repo_setup
    mkdir -p "${GIT_TEST_REPO}/src"
    printf 'package main\n// TODO: extract helper\n// FIXME: handle nil\nfunc main() {}\n' \
        > "${GIT_TEST_REPO}/src/main.go"
    git -C "${GIT_TEST_REPO}" add .
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    git_test_repo_run "bash '${DETECT_SCRIPT}' --scope all"
    [ "$status" -eq 0 ]
    assert_detect_tech_debt_ok_json "${output}" "all" ""
    [[ $output == *'"skip": false'* ]]
    [[ $output == *'"todo_comment"'* ]]
    [[ $output == *'"fixme"'* ]]
}
```

- [ ] **Step 2: Run bats — expect FAIL on missing kinds**

- [ ] **Step 3: Implement `collect_marker_signals`**

Logic:

- `git grep -nI -E '//\s*TODO\b|#\s*TODO\b|/\*\s*TODO\b|\bTODO:'` (and parallel patterns for FIXME/HACK/XXX) with standard prune via `git grep` pathspecs excluding generated dirs, **or** `git grep` then filter paths with a `path_is_pruned` helper matching docs-triage prune list + `docs/report/`
- Map match → kind; build signal JSON via `append_signal`
- Enforce caps; push warning `"marker signals truncated"` when hit

Wire into `main` after parse.

- [ ] **Step 4: Run bats — PASS**

- [ ] **Step 5: Commit** (if requested)

```bash
git commit -m "$(cat <<'EOF'
feat(loop-tech-debt): detect TODO/FIXME/HACK/XXX marker signals

EOF
)"
```

---

### Task 3: Dependency signals

**Files:**

- Modify: `detect_tech_debt.sh` — `collect_dependency_signals` (+ helpers for go.mod / package.json)
- Modify: `detect_tech_debt.bats`

**Interfaces:**

- Produces: `kind` ∈ `pin_drift|version_range|eol_hint`
- Env: `TECH_DEBT_EOL_MODULES` optional comma-separated module paths/names for `eol_hint` (facts only; empty = no eol_hint from env)
- `hint=dependency_version`

- [ ] **Step 1: Failing bats**

```bash
@test "detect_tech_debt emits version_range for caret dependency in package.json" {
    git_test_repo_setup
    printf '%s\n' '{"name":"x","dependencies":{"leftpad":"^1.0.0"}}' \
        > "${GIT_TEST_REPO}/package.json"
    git -C "${GIT_TEST_REPO}" add package.json
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    git_test_repo_run "bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    [[ $output == *'"version_range"'* ]]
}

@test "detect_tech_debt emits eol_hint when TECH_DEBT_EOL_MODULES matches go.mod require" {
    git_test_repo_setup
    cat > "${GIT_TEST_REPO}/go.mod" <<'EOF'
module example.com/app

go 1.22

require github.com/old/lib v1.2.3
EOF
    git -C "${GIT_TEST_REPO}/" add go.mod
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    git_test_repo_run "env TECH_DEBT_EOL_MODULES='github.com/old/lib' bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    [[ $output == *'"eol_hint"'* ]]
}
```

For `pin_drift` (optional third test): `package.json` exact version vs `package-lock.json` different resolved version → `pin_drift`. Implement if straightforward with jq; otherwise document as follow-up and keep version_range + eol_hint for v1.

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Implement collectors**

- Scan for `go.mod`, `package.json` (prune paths).
- `version_range`: package.json deps whose version string starts with `^`, `~`, `*`, or `x`.
- `eol_hint`: require/dependency name listed in `TECH_DEBT_EOL_MODULES`.
- `pin_drift`: when lockfile present and declared exact version ≠ lock resolved (npm); for Go, skip pin_drift unless easy (`go.mod` vs `go.sum` is not a simple pin compare — skip Go pin_drift in v1).

- [ ] **Step 4: Bats PASS**

- [ ] **Step 5: Commit** (if requested)

---

### Task 4: Docs sensor (self-contained mlc + stale_doc)

**Files:**

- Modify: `detect_tech_debt.sh` — `ensure_markdown_link_check`, `collect_doc_signals`
- Modify: `detect_tech_debt.bats`
- Note: cache dir under `${TMPDIR:-/tmp}/loop-tech-debt-mlc` or `SCRIPT_DIR/.cache/markdown-link-check` (gitignore `.cache` if under skill; prefer `$TMPDIR` to avoid committing node_modules)

**Interfaces:**

- Constant: `MLC_VERSION="3.14.2"`
- Env: `TECH_DEBT_STALE_DAYS` default `365`; `TECH_DEBT_SKIP_MLC=true` forces skip with warning (for offline bats)
- Produces: `broken_doc_ref` from mlc JSON/quiet output; `stale_doc` from git log / mtime age
- On node/npm/mlc failure: `warnings+=("docs link sensor skipped: …")`; do not fail whole detect

- [ ] **Step 1: Failing bats**

```bash
@test "detect_tech_debt emits broken_doc_ref for missing relative markdown link" {
    git_test_repo_setup
    mkdir -p "${GIT_TEST_REPO}/docs"
    printf '# Doc\n\nSee [missing](./nope.md)\n' > "${GIT_TEST_REPO}/docs/index.md"
    git -C "${GIT_TEST_REPO}" add .
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    git_test_repo_run "bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    assert_detect_tech_debt_ok_json "${output}" "all" ""
    [[ $output == *'"broken_doc_ref"'* ]] || [[ $output == *'docs link sensor skipped'* ]]
}

@test "detect_tech_debt emits stale_doc when TECH_DEBT_STALE_DAYS is zero" {
    git_test_repo_setup
    mkdir -p "${GIT_TEST_REPO}/docs"
    printf '# Old\n' > "${GIT_TEST_REPO}/docs/old.md"
    git -C "${GIT_TEST_REPO}" add .
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    git_test_repo_run "env TECH_DEBT_STALE_DAYS=0 TECH_DEBT_SKIP_MLC=true bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    [[ $output == *'"stale_doc"'* ]]
}

@test "detect_tech_debt warns and continues when TECH_DEBT_SKIP_MLC=true" {
    git_test_repo_setup
    printf '# x\n' > "${GIT_TEST_REPO}/README.md"
    git -C "${GIT_TEST_REPO}" add .
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    git_test_repo_run "env TECH_DEBT_SKIP_MLC=true bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    [[ $output == *'"warnings"'* ]]
}
```

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Implement**

`ensure_markdown_link_check`:

1. If `TECH_DEBT_SKIP_MLC=true` → return 1
2. `command -v node` and `npm` or use `npx`; else warn + return 1
3. Cache prefix `$TMPDIR/loop-tech-debt-mlc/${MLC_VERSION}`
4. If binary missing: `npm install --prefix "${cache}" "markdown-link-check@${MLC_VERSION}"` (network)
5. Return path to CLI

`collect_doc_signals`:

- Find `*.md` with prune
- Run mlc per file or batch; parse failures into `broken_doc_ref` signals (`source=markdown_link_check`)
- For each md: if last commit age or mtime days ≥ `TECH_DEBT_STALE_DAYS` → `stale_doc` (`source=git_log`)

- [ ] **Step 4: Bats PASS** (broken_doc_ref may need network once for mlc install; if CI offline, prefer asserting warning path + separate optional `@test` tagged or skip when no node)

Document in suite header: broken_doc_ref test requires node+network on first run.

- [ ] **Step 5: Commit** (if requested)

---

### Task 5: Churn hotspots

**Files:**

- Modify: `detect_tech_debt.sh` — `collect_churn_hotspots`
- Modify: `detect_tech_debt.bats`

**Interfaces:**

- Env: `TECH_DEBT_CHURN_WINDOW` default `90d`; `TECH_DEBT_CHURN_MIN` default `5`; `TECH_DEBT_CHURN_TOP` default `20`
- Produces: `hotspots[]` with `metric=churn`, `window` from env

- [ ] **Step 1: Failing bats**

```bash
@test "detect_tech_debt emits churn hotspot for frequently edited file" {
    git_test_repo_setup
    printf 'v1\n' > "${GIT_TEST_REPO}/hot.txt"
    git -C "${GIT_TEST_REPO}" add hot.txt
    git -C "${GIT_TEST_REPO}" commit -q -m "c1"
    local i
    for i in 2 3 4 5 6; do
        echo "v${i}" >> "${GIT_TEST_REPO}/hot.txt"
        git -C "${GIT_TEST_REPO}" add hot.txt
        git -C "${GIT_TEST_REPO}" commit -q -m "c${i}"
    done
    git_test_repo_run "env TECH_DEBT_CHURN_MIN=5 TECH_DEBT_CHURN_WINDOW=365d TECH_DEBT_SKIP_MLC=true bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    [[ $output == *'"metric": "churn"'* ]] || [[ $output == *'"metric":"churn"'* ]]
    [[ $output == *'hot.txt'* ]]
}
```

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Implement**

```bash
# git log --since="${window}" --name-only --pretty=format: | sort | uniq -c | sort -rn
```

Filter pruned paths; take top N with count ≥ min; `append_hotspot`.

- [ ] **Step 4: Bats PASS**

- [ ] **Step 5: Commit** (if requested)

---

### Task 6: Skill reference updates (schema / taxonomy / checklist)

**Files:**

- Modify: `references/category-input-schema.md`
- Modify: `references/category-debt-taxonomy.md`
- Modify: `references/common-checklist.md`
- Modify: `SKILL.md` metadata version → `1.2.0`

**Interfaces:**

- Schema documents closed kinds exactly as detect emits
- Add optional top-level `warnings` array description (caller may pass through)

- [ ] **Step 1: Update `category-input-schema.md`**

Replace open-ended kind examples with closed set:

`todo_comment`, `fixme`, `hack`, `xxx`, `pin_drift`, `version_range`, `eol_hint`, `broken_doc_ref`, `stale_doc`

Document: detect default full-repo; markers secondary; `warnings` optional strings from detect.

- [ ] **Step 2: Taxonomy + checklist**

Add short sections:

- **Detect vs lint:** do not restate linter findings; markers may appear in reports (usually Watch).
- **Out of scope:** new-technology / tool migration playbooks — report EOL/deprecation facts only; do not recommend replacement stacks.

- [ ] **Step 3: Bump SKILL.md version to 1.2.0** (description unchanged regarding not running detection)

- [ ] **Step 4: Commit** (if requested)

---

### Task 7: Validation gate

**Files:** none new

- [ ] **Step 1: Sync check**

```bash
bash scripts/self/ai/sync_skill_lib.sh --check
```

Expected: exit 0

- [ ] **Step 2: Shell validation**

```bash
bash -n .apm/packages/loop-tech-debt/.apm/skills/loop-tech-debt/scripts/detect_tech_debt.sh
shellcheck .apm/packages/loop-tech-debt/.apm/skills/loop-tech-debt/scripts/detect_tech_debt.sh
```

Expected: clean (or only justified disables matching siblings)

- [ ] **Step 3: Full bats suite**

```bash
bats test/bats/.apm/packages/loop-tech-debt/detect_tech_debt.bats
```

Expected: all PASS

- [ ] **Step 4: Mark spec status Implemented** in `docs/superpowers/specs/2026-07-20-loop-tech-debt-detect-design.md`

- [ ] **Step 5: Final commit** (if requested)

```bash
git commit -m "$(cat <<'EOF'
feat(loop-tech-debt): full-repo detect sensors and closed signal kinds

EOF
)"
```

---

## Spec coverage self-review

| Spec item                                            | Task                        |
| ---------------------------------------------------- | --------------------------- |
| Full-repo default `scope=all`                        | 1                           |
| Markers secondary                                    | 2, 6                        |
| Deps pin/range/eol                                   | 3                           |
| Docs mlc self-install + stale; no existence fallback | 4                           |
| Churn hotspots                                       | 5                           |
| Closed kinds + warnings                              | 1, 6                        |
| No migration playbook                                | 6                           |
| Script DOC level like siblings                       | 1–5 (enforced in authoring) |
| Bats TEST-00                                         | 1–5, 7                      |
| No workflow                                          | (omitted)                   |
| Lint non-overlap                                     | 6 + sensor selection        |

## Placeholder scan

None intentional. Go `pin_drift` may be skipped in Task 3 with explicit note — prefer implementing npm `pin_drift` only in v1.

## Type / name consistency

- Script: `detect_tech_debt.sh`
- Package/skill: `loop-tech-debt`
- Assert helpers: `assert_detect_tech_debt_ok_json` / `assert_detect_tech_debt_error_json`
- Env prefix: `TECH_DEBT_*`
- MLC pin: `3.14.2`
