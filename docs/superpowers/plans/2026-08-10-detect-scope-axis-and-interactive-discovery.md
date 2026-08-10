# Detect Scope Axis and Interactive Discovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align sibling utility detect `--scope` semantics to the cursor axis and make Interactive discovery “universe → detect → Agent complement” explicit in skill contracts, including the docs-updater `all` behavior change.

**Architecture:** Normative design is `docs/superpowers/specs/2026-08-10-detect-scope-axis-and-interactive-discovery-design.md`. Each skill gets a thin portable `references/category-detect-scope.md` (shared axis + that skill’s mapping row). SKILL.md Interactive steps stop saying “when helpful” and require detect when JSON is absent. docs-updater `detect_changes.sh --scope all` switches from HEAD+untracked diff to full candidate-doc enumeration (TDD via existing Bats suite).

**Tech Stack:** Bash detect scripts, Bats (`test/bats/`), APM skills under `.apm/packages/common/.apm/skills/`, Markdown skill references.

## Global Constraints

- Spec source of truth: `docs/superpowers/specs/2026-08-10-detect-scope-axis-and-interactive-discovery-design.md`.
- Skill edits: `.apm/packages/common/.apm/skills/<name>/` only. Do **not** hand-edit `.agents/`, `.claude/`, `.cursor/`, etc.
- After skill package edits: `bash scripts/self/apm/sync_apm_artifacts.sh apm-install` (or `apm install --update` per repo norm); verify with `apm audit --ci` when touching packages.
- Portable package wording only — no `on-loop-*` workflow names inside `.apm/packages/**`.
- Commit only when the user asks. Plan steps say **Do not commit** unless the user requested commits for that task.
- Prefer lean-ctx for reads/searches when available.
- Do not weaken or delete existing Bats to make checks pass.

## File map

| Path | Responsibility |
| ---- | -------------- |
| `.apm/packages/common/.apm/skills/{changelog,ci-sweeper,docs-updater,refactor,tech-debt}/references/category-detect-scope.md` | Thin cursor axis + per-skill mapping + Interactive discovery rules |
| `.apm/packages/common/.apm/skills/*/SKILL.md` | Reference Files Guide + Interactive workflow: detect-when-absent + complement |
| `.apm/packages/common/.apm/skills/refactor/references/common-checklist.md` | SURVEY-01 Interactive wording |
| `.apm/packages/common/.apm/skills/docs-updater/scripts/detect_changes.sh` | `--scope all` = full candidate-doc enumeration |
| `.apm/packages/common/.apm/skills/{changelog,ci-sweeper,refactor,tech-debt}/scripts/detect_*.sh` | Usage headers: axis language; noop/deprecated `staged` where applicable |
| `.apm/packages/common/.apm/skills/*/references/category-input-schema.md` | Cross-link scope axis; docs-updater `scope: all` description |
| `test/bats/.apm/packages/common/docs-updater/detect_changes.bats` | Failing-then-passing tests for new `all` |
| `docs/explanation/loop-engineering/workflows/loop-docs-updater-workflow-design.md` (if it documents old `all`) | Maintainer note: Loop stays `range`; old `all` meaning retired |

---

### Task 1: Add `category-detect-scope.md` to all five skills

**Files:**
- Create: `.apm/packages/common/.apm/skills/changelog/references/category-detect-scope.md`
- Create: `.apm/packages/common/.apm/skills/ci-sweeper/references/category-detect-scope.md`
- Create: `.apm/packages/common/.apm/skills/docs-updater/references/category-detect-scope.md`
- Create: `.apm/packages/common/.apm/skills/refactor/references/category-detect-scope.md`
- Create: `.apm/packages/common/.apm/skills/tech-debt/references/category-detect-scope.md`
- Modify: each skill’s `SKILL.md` Reference Files Guide (add load trigger)

**Interfaces:**
- Consumes: Spec §§ Cursor axis, Domain mapping, Interactive discovery
- Produces: Portable reference Agents load on interactive path / when running detect

- [ ] **Step 1: Create the shared front matter + skill-specific body for `refactor`**

Write `.apm/packages/common/.apm/skills/refactor/references/category-detect-scope.md` with this content (adjust only the **This skill** section per skill in later steps):

```markdown
# Detect Scope Axis

`--scope` is a **cursor axis**, not a universal “whole repo files” switch.

| Value | Cursor | Meaning |
| ----- | ------ | ------- |
| `range` | Commit (`--since` required) | Universe members related to `<since>..HEAD` |
| `all` | None | Full enumeration of this skill’s domain universe, then caps/filters |
| `staged` | Index | Universe members in the git index — file-oriented skills only |

`all` is not unbounded: skill caps still apply (hint limits, commit limits, run limits).

## File-oriented enumeration

When natural units are files: enumerate eligible paths, then apply this skill’s glob filter when configured; unset/empty glob means no glob filter. Resolve the universe from the user prompt **before** invoking detect when the user named paths/globs.

## Interactive discovery

1. Resolve universe from the prompt / Constraints (default = this skill’s config).
2. If detect JSON is absent, run `scripts/` detect with the resolved scope (default `all`; use `staged`/`range` when the user named index or SHA range).
3. Classify mechanical output.
4. **Agent complement:** read targets; add in-scope candidates detect cannot see. User-supplied URL/path/symbol is primary evidence when present.
5. Empty detect alone does not force no-op if complement found work.

## This skill (`refactor`)

| Field | Value |
| ----- | ----- |
| Universe | Enumerate tracked paths, then `REFACTOR_SCAN_GLOBS` when set (default `.apm/packages/**,scripts/**`) |
| `all` | Full enumerated∩filter scan → `hints[]` |
| `range` | Changed paths in `<since>..HEAD` ∩ filter |
| `staged` | Cached paths ∩ filter |
| Detect script | `scripts/detect_refactor.sh` |
```

- [ ] **Step 2: Copy to the other four skills; replace only the `## This skill` section**

**changelog** — commits, not files:

```markdown
## This skill (`changelog`)

| Field | Value |
| ----- | ----- |
| Universe | Commit set capped by `CHANGELOG_MAX_COMMITS` (or successor) |
| `all` | Cap-bounded commits without since-cursor |
| `range` | `<since>..HEAD` commits |
| `staged` | Not used — if accepted for CLI parity, treat as noop / deprecated |
| Detect script | `scripts/detect_changelog_commits.sh` |
```

**ci-sweeper:**

```markdown
## This skill (`ci-sweeper`)

| Field | Value |
| ----- | ----- |
| Universe | Failed workflow runs on the relevant branch (scan limit applies) |
| `all` | Limit-bounded failure enumeration |
| `range` | Failures related to the `--since` window |
| `staged` | noop / deprecated (index cursor does not apply to CI runs) |
| Detect script | `scripts/detect_ci_failures.sh` |
| Interactive note | Prefer user-supplied run URL / job / log as primary evidence; still run detect when JSON is absent and tools allow; if `gh`/auth missing, fall back to user context — do not silent no-op |
```

**docs-updater:**

```markdown
## This skill (`docs-updater`)

| Field | Value |
| ----- | ----- |
| Universe | Candidate docs (`DOCS_UPDATER_DOC_GLOBS` or default markdown discovery) |
| `all` | Full candidate-doc enumeration (not working-tree diff) |
| `range` | Impact from `<since>..HEAD` changes |
| `staged` | Impact from cached diff (git hook / pre-commit) |
| Detect script | `scripts/detect_changes.sh` |
| Path roles | Interactive free-form → `all`; git hook → `staged`; automation with cursor → `range` |
```

**tech-debt:**

```markdown
## This skill (`tech-debt`)

| Field | Value |
| ----- | ----- |
| Universe | Repository sensor universe (full tree walk when unfiltered) |
| `all` | Full sensor pass |
| `range` | Accepted for CLI parity — document actual sensor behavior in detect usage; do not silently redefine without tests |
| `staged` | noop / deprecated |
| Detect script | `scripts/detect_tech_debt.sh` |
```

- [ ] **Step 3: Wire Reference Files Guide in each `SKILL.md`**

Add this line (keep alphabetical / existing order conventions of that file; place near other `category-*` entries):

```markdown
- [category-detect-scope.md](references/category-detect-scope.md) (read on interactive path)
```

Also ensure `category-input-schema.md` trigger still covers detect script runs. For **refactor**, change the input-schema trigger if needed to:

```markdown
- [category-input-schema.md](references/category-input-schema.md) (read when structured mode JSON, automation detect JSON, or the optional detect script is run)
```

- [ ] **Step 4: Sanity-check links**

Run: `rg -n 'category-detect-scope' .apm/packages/common/.apm/skills/{changelog,ci-sweeper,docs-updater,refactor,tech-debt}/SKILL.md`

Expected: one hit per skill.

- [ ] **Step 5: Do not commit** (unless the user asked)

---

### Task 2: Rewrite Interactive Workflow steps (detect-when-absent + complement)

**Files:**
- Modify: `.apm/packages/common/.apm/skills/changelog/SKILL.md`
- Modify: `.apm/packages/common/.apm/skills/ci-sweeper/SKILL.md`
- Modify: `.apm/packages/common/.apm/skills/docs-updater/SKILL.md`
- Modify: `.apm/packages/common/.apm/skills/refactor/SKILL.md`
- Modify: `.apm/packages/common/.apm/skills/tech-debt/SKILL.md`
- Modify: `.apm/packages/common/.apm/skills/refactor/references/common-checklist.md` (SURVEY-01)

**Interfaces:**
- Consumes: Task 1 references
- Produces: Agent-visible Interactive contract matching the spec

- [ ] **Step 1: Replace “when helpful” gather sentences**

In changelog, ci-sweeper, docs-updater, tech-debt Workflow step 1 (and docs-updater Interactive/hook path step 1), replace the pattern:

```text
otherwise run this skill's optional detect script when helpful, or gather …
```

with:

```text
otherwise resolve the detect universe from the prompt ([category-detect-scope.md](references/category-detect-scope.md)), run this skill's optional detect script with the resolved `--scope` (default `all`), then Agent-complement beyond mechanical output; if tools for detect are unavailable, gather from the user request and repository context instead of silent no-op.
```

Keep each skill’s existing “Load category-input-schema… On detect script non-zero exit…” clauses.

- [ ] **Step 2: Expand `refactor` Interactive path**

Replace `### Interactive path` body with:

```markdown
### Interactive path

1. Resolve `may_edit` (table above). Load [category-detect-scope.md](references/category-detect-scope.md).
2. Resolve universe from the prompt (default = `REFACTOR_SCAN_GLOBS` / skill defaults). If the user named paths/globs, narrow the universe before detect.
3. If detect JSON is absent, run `scripts/detect_refactor.sh` with the resolved scope (default `--scope all`; set `REFACTOR_SCAN_GLOBS` for a temporary universe). On non-zero exit or `status: "error"`, read stdout and stop.
4. Phase A: classify every `hints[]` entry and Agent-complement structural candidates (read targets — SURVEY-03). Architecture without `approved_slice` stops inside Phase A step 3.
5. Empty detect alone is not a no-op if complement found apply-worthy or watch-worthy work.
6. `may_edit: false` or `write_target` ≠ `fix` → emit survey shape; stop.
7. Else → Phase B; emit apply shape.
```

- [ ] **Step 3: Update docs-updater Input / USE FOR for Interactive `all`**

In `docs-updater` `SKILL.md`:
- Input Interactive line: note free-form survey uses `--scope all` (full candidate docs); hooks use `staged`; automation uses `range` when a cursor exists.
- USE FOR: add that Interactive free-form may survey candidate docs for drift/sync opportunities, not only git diff sync.

- [ ] **Step 4: Update refactor SURVEY-01 checkbox text**

In `common-checklist.md` SURVEY-01, change the discover bullet to:

```markdown
- [ ] Discover candidates in scope — automation: every `hints[]` entry; interactive structural: run optional detect for the resolved universe then Agent-complement (user paths/symbols always read); architecture Phase B: **only** the `approved_slice`
```

- [ ] **Step 5: Grep for leftover “when helpful”**

Run: `rg -n 'when helpful' .apm/packages/common/.apm/skills/{changelog,ci-sweeper,docs-updater,refactor,tech-debt}`

Expected: no matches in those skill trees.

- [ ] **Step 6: Do not commit** (unless the user asked)

---

### Task 3: docs-updater `--scope all` behavior (TDD)

**Files:**
- Test: `test/bats/.apm/packages/common/docs-updater/detect_changes.bats`
- Modify: `.apm/packages/common/.apm/skills/docs-updater/scripts/detect_changes.sh`
- Modify: `.apm/packages/common/.apm/skills/docs-updater/references/category-input-schema.md` (describe `scope: all`)
- Modify: header comments / `show_usage` in `detect_changes.sh`

**Interfaces:**
- Consumes: Spec D4/D5 — `all` = full candidate-doc enumeration
- Produces: `affected_docs` populated without requiring a non-markdown git change when `--scope all`

- [ ] **Step 1: Write the failing Bats tests**

Append to `detect_changes.bats` (and add matching `# Use cases:` header lines):

```bash
@test "detect_changes all scope enumerates candidate docs without code changes" {
    git_test_repo_setup
    mkdir -p "${GIT_TEST_REPO}/docs" "${GIT_TEST_REPO}/src"
    printf '# Docs\n' > "${GIT_TEST_REPO}/docs/index.md"
    printf '# More\n' > "${GIT_TEST_REPO}/docs/guide.md"
    printf 'package main\n' > "${GIT_TEST_REPO}/src/main.go"
    git -C "${GIT_TEST_REPO}" add .
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    git_test_repo_run "bash '${DETECT_SCRIPT}' --scope all"
    [ "$status" -eq 0 ]
    run jq -e '
        .status == "ok"
        and .scope == "all"
        and .skip == false
        and (.affected_docs | index("docs/index.md") != null)
        and (.affected_docs | index("docs/guide.md") != null)
    ' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_changes all scope honors DOCS_UPDATER_DOC_GLOBS filter" {
    git_test_repo_setup
    mkdir -p "${GIT_TEST_REPO}/docs" "${GIT_TEST_REPO}/notes"
    printf '# Docs\n' > "${GIT_TEST_REPO}/docs/index.md"
    printf '# Notes\n' > "${GIT_TEST_REPO}/notes/only.md"
    git -C "${GIT_TEST_REPO}" add .
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    git_test_repo_run "DOCS_UPDATER_DOC_GLOBS='docs/**' bash '${DETECT_SCRIPT}' --scope all"
    [ "$status" -eq 0 ]
    run jq -e '
        .status == "ok"
        and (.affected_docs | index("docs/index.md") != null)
        and (.affected_docs | index("notes/only.md") == null)
    ' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_changes staged scope still skips when only markdown changes" {
    git_test_repo_setup
    mkdir -p "${GIT_TEST_REPO}/docs"
    printf '# Docs\n' > "${GIT_TEST_REPO}/docs/index.md"
    git -C "${GIT_TEST_REPO}" add .
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    printf '\npara\n' >> "${GIT_TEST_REPO}/docs/index.md"
    git -C "${GIT_TEST_REPO}" add docs/index.md
    git_test_repo_run "bash '${DETECT_SCRIPT}' --scope staged"
    [ "$status" -eq 0 ]
    run jq -e '.status == "ok" and .skip == true' <<< "${output}"
    [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `bats test/bats/.apm/packages/common/docs-updater/detect_changes.bats --filter 'all scope enumerates'`

Expected: FAIL — current `all` uses HEAD diff; clean tree ⇒ no `has_relevant_change` ⇒ empty `affected_docs` / `skip: true`.

- [ ] **Step 3: Implement `--scope all` enumeration**

In `detect_changes.sh`:

1. Update header + `show_usage`:

```text
all: enumerate all candidate documentation paths (DOC_GLOBS or default markdown discovery); not git diff HEAD
staged: git diff --cached only (hook)
range: git diff <ref>..HEAD (requires --since)
```

2. Add `collect_all_candidate_docs`:

```bash
function collect_all_candidate_docs {
    AFFECTED_DOCS=()
    if [[ -n ${DOCS_UPDATER_DOC_GLOBS:-} ]]; then
        append_docs_from_globs "${DOCS_UPDATER_DOC_GLOBS}"
        append_docs_from_extra_files
    else
        append_docs_from_find
        append_docs_from_extra_files
        append_unique_doc "${DOCS_UPDATER_SITE_CONFIG}"
    fi
}
```

3. Change `main`:

```bash
function main {
    ensure_dependencies bash git jq
    configure_detect_environment
    parse_arguments "$@"
    if [[ ${SCOPE} == "all" ]]; then
        COMMIT_RANGE="all"
        CHANGED_FILES=()
        DELETED_FILES=()
        RENAMED_FILES=()
        collect_all_candidate_docs
    else
        collect_changes
        collect_affected_docs
    fi
    output_json
}
```

4. Remove or dead-code the old `collect_changes` branch that treated `all` as `git diff HEAD` + untracked (the `if [[ ${SCOPE} == "all" ]]; then git ls-files --others` block). After this change, `collect_changes` should only handle `staged` and `range`.

5. In `collect_affected_docs`, the branch `elif [[ ${SCOPE} == "staged" || ${SCOPE} == "all" ]]` should become `elif [[ ${SCOPE} == "staged" ]]` only (hook path).

- [ ] **Step 4: Run full docs-updater detect Bats**

Run: `bats test/bats/.apm/packages/common/docs-updater/detect_changes.bats`

Expected: all tests PASS (including new ones; existing range/staged tests unchanged in intent).

- [ ] **Step 5: Update `category-input-schema.md` field text for `scope`**

Document:

```markdown
| `scope` | string | `staged` (index / hook), `all` (full candidate-doc enumeration), or `range` (`--since`..HEAD) |
```

- [ ] **Step 6: Do not commit** (unless the user asked)

---

### Task 4: Align other detect script usage headers (no behavior change unless proven)

**Files:**
- Modify: `.apm/packages/common/.apm/skills/refactor/scripts/detect_refactor.sh` (header/`show_usage` only unless tests require more)
- Modify: `.apm/packages/common/.apm/skills/tech-debt/scripts/detect_tech_debt.sh`
- Modify: `.apm/packages/common/.apm/skills/changelog/scripts/detect_changelog_commits.sh`
- Modify: `.apm/packages/common/.apm/skills/ci-sweeper/scripts/detect_ci_failures.sh`
- Modify: matching `category-input-schema.md` scope blurbs where they contradict the axis

**Interfaces:**
- Consumes: Spec domain mapping
- Produces: Usage text Agents/humans read; behavior remains current except documented noops

- [ ] **Step 1: Update each script’s Usage block to cursor-axis wording**

Pattern for file skills (refactor):

```text
--scope    Cursor axis (default: all)
           all: enumerate eligible files, then REFACTOR_SCAN_GLOBS filter when set
           range: files changed in <since>..HEAD matching filter (--since required)
           staged: git diff --cached only ∩ filter
```

ci-sweeper: state `staged` is accepted for CLI parity but **noop / deprecated**.

tech-debt: `all` = full sensor universe; `staged` noop/deprecated; `range` = document actual current behavior in one sentence (parity accept today).

changelog: `all` = cap-bounded commits without since; `range` = since..HEAD.

- [ ] **Step 2: Run existing related Bats (no new failures)**

Run:

```bash
bats test/bats/scripts/detect_refactor.bats
bats test/bats/.apm/packages/common/docs-updater/detect_changes.bats
```

If changelog/ci-sweeper/tech-debt suites exist under `test/bats/.apm/packages/common/`, run those too:

```bash
ls test/bats/.apm/packages/common/
bats test/bats/.apm/packages/common/changelog/*.bats
bats test/bats/.apm/packages/common/ci-sweeper/*.bats
bats test/bats/.apm/packages/common/tech-debt/*.bats
```

Expected: PASS (usage-only changes).

- [ ] **Step 3: Do not commit** (unless the user asked)

---

### Task 5: Maintainer docs for docs-updater breaking `all`

**Files:**
- Modify if they mention old `all`: `docs/explanation/loop-engineering/workflows/loop-docs-updater-workflow-design.md`
- Modify if needed: any hook example under `docs/` that says docs-updater `--scope all` for worktree sync

**Interfaces:**
- Consumes: Spec migration table
- Produces: Maintainer-facing Breaking note

- [ ] **Step 1: Search maintainer docs**

Run: `rg -n 'detect_changes|--scope all|scope all' docs/explanation/loop-engineering docs/reference --glob '*docs*'`

- [ ] **Step 2: Patch call sites**

For each hit that means “HEAD + untracked”:
- Loop path: document `range --since` (unchanged ownership).
- Hook/manual worktree sync: document `staged`.
- Add one Breaking sentence: Interactive/`--scope all` now enumerates candidate docs.

Do **not** put `on-loop-docs-updater` names into package skill sources.

- [ ] **Step 3: Do not commit** (unless the user asked)

---

### Task 6: Sync distributed skill copies and audit

**Files:**
- Generated/synced: `.agents/skills/*`, `.claude/skills/*` via sync only
- Possibly: `apm.lock.yaml`

- [ ] **Step 1: Sync**

Run: `bash scripts/self/apm/sync_apm_artifacts.sh apm-install`

Expected: package skill trees mirrored to agent roots; lockfile updated if that is normal for this repo.

- [ ] **Step 2: Audit**

Run: `apm audit --ci`

Expected: exit 0 (or repo-documented success).

- [ ] **Step 3: Final regression**

Run:

```bash
bats test/bats/.apm/packages/common/docs-updater/detect_changes.bats
bats test/bats/scripts/detect_refactor.bats
```

Expected: PASS.

- [ ] **Step 4: Do not commit** (unless the user asked) — when committing, prefer separate commits: (1) skill contract refs+SKILL, (2) docs-updater detect+bats, (3) usage headers + maintainer docs + sync/lock — or one commit if the user prefers a single squashed change.

---

## Spec coverage checklist

| Spec item | Task |
| --------- | ---- |
| Cursor axis normative table | Task 1 |
| File enumerate → glob filter | Task 1 + Task 3 (`DOCS_UPDATER_DOC_GLOBS`) |
| Domain mapping rows | Task 1 |
| Interactive detect-when-absent + complement | Task 2 |
| ci-sweeper Interactive keep detect + URL primary | Task 1 (ci-sweeper section) + Task 2 |
| docs-updater `all` meaning change | Task 3 |
| No new `workdir` scope | Task 3 (hook=`staged`) |
| Usage/noop clarity on other detects | Task 4 |
| Thin portable references + spec as normative | Task 1; spec already landed |
| Maintainer migration notes | Task 5 |
| Sync agent copies | Task 6 |
| tech-debt `range` not silently redefined | Task 4 (document only) |

## Out of scope (per spec)

- New detect hint kinds
- tech-debt sensor performance redesign
- Splitting file vs event CLIs
- Implementing `workdir`
