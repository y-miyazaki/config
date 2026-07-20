# loop-tech-debt Detect Layer Design

**Status:** Implemented  
**Date:** 2026-07-20  
**Package:** `.apm/packages/loop-tech-debt`  
**Skill:** `loop-tech-debt` (Execute / classify already exists; this design adds Detect)

## Problem

`loop-tech-debt` classifies injected `signals[]` / `hotspots[]` and writes reports, but there is **no `detect_*.sh`**. Without a facts-only detect script, the loop cannot run end-to-end under `loop-detect`. Mechanical sensors must cover what lint does **not**, scan the **whole repository** by default, and match sibling loop script quality (DOC-01, structure, bats).

## Goals

- Add `detect_report_tech_debt.sh` that emits facts-only JSON matching `.apm/packages/loop-report-tech-debt/.apm/skills/loop-report-tech-debt/references/category-input-schema.md` (closed `kind` set + optional `warnings[]`).
- Default scan: **full repository** (`scope=all`). Git range is optional debug only; not the debt observation model.
- Sensors: **core** deps + docs (via self-contained `markdown-link-check`) + churn; **secondary** TODO/FIXME/HACK/XXX for report enrichment.
- Exclude lint/SAST territory (complexity, style, unused, naming).
- No new-technology / migration playbook in the skill.
- Script authoring matches existing loop detect scripts and `shell-script.instructions.md`.
- Same change includes matching Bats suite (TEST-00).

## Non-Goals

- `on-loop-tech-debt.yaml` / L2 PR caller (follow-up).
- CVE database lookups, exploit writing, dependency upgrade PRs.
- Dual path for broken links (no bash “file exists only” fallback alongside mlc).
- Complexity / LOC hotspot metrics (lint/Sonar territory).
- Changing Execute skill to run detection itself.

## Decisions

| Topic             | Choice                                                                                                                                                                             |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Architecture      | Single entry `detect_tech_debt.sh`; sensor logic as functions (a-z) in the same file (or sourced siblings only if size demands — prefer one file first like other detects).        |
| Default scope     | `all` (full tree). Accept `staged`/`range` for `loop-detect` CLI parity; `range` does not narrow sensors unless explicitly useful for churn window override later.                 |
| Markers           | Include; secondary; skill defaults toward Watch unless systemic.                                                                                                                   |
| Docs links        | Self-contained install of pinned `markdown-link-check` under skill/cache or `$TMPDIR`; use tool fully when Node available; on failure → `warnings[]` + skip docs-link sensor only. |
| Deps              | Parse known manifests (`go.mod`, `package.json` / lock) for `pin_drift`, `version_range`, `eol_hint` (caller EOL list or in-file deprecated notes only — no CVE DB).               |
| Churn             | `git log --since` path counts; default window `90d`; top K; min commits threshold.                                                                                                 |
| New tech guidance | Explicitly out of scope (one line in taxonomy/checklist).                                                                                                                          |
| Phase deliverable | Detect + schema/taxonomy/checklist updates + bats. No workflow.                                                                                                                    |

## Closed `signals[].kind` set

| kind                                       | Sensor  | Role                                                                     |
| ------------------------------------------ | ------- | ------------------------------------------------------------------------ |
| `todo_comment` / `fixme` / `hack` / `xxx`  | markers | Secondary                                                                |
| `pin_drift` / `version_range` / `eol_hint` | deps    | Core                                                                     |
| `broken_doc_ref` / `stale_doc`             | docs    | Core (`broken_doc_ref` from mlc; `stale_doc` from mtime/last commit age) |
| (hotspots only)                            | churn   | Core — `hotspots[].metric=churn`                                         |

Unknown kinds must not be emitted by detect. Skill treats unexpected kinds as Watch/Noise.

## Architecture

```text
detect_tech_debt.sh
  parse_arguments (--scope|--since|--help)
  collect_marker_signals
  collect_dependency_signals
  ensure_markdown_link_check   # pin + local install; or warn+skip
  collect_doc_signals           # mlc + stale
  collect_churn_hotspots
  output_json                   # status, skip, signals, hotspots, warnings
        │
        ▼
loop-prompt-generate → loop-tech-debt skill (LLM classifies; hint optional)
```

**Prune paths** (align with docs-triage find prune): `.git`, hidden dirs, `.agents`/`.cursor`/`.claude`/`.codex`/`.kiro`/`.vscode`, `apm_modules`, `node_modules`, `dist`/`build`/`bin`, `docs/report/**` (avoid self-noise).

## Script authoring contract (normative)

Match **sibling loop detects** (`detect_changes.sh`, `detect_ci_failures.sh`) and package instructions `.apm/packages/shell-script/.apm/instructions/shell-script.instructions.md`. Do not invent a lighter comment style.

### File structure (executable entry)

1. `#!/bin/bash`
2. Header block wrapped in `#######################################` with: **Description**, **Usage**, **Output**, **Design Rules**, **Dependencies**, **Optional environment** (same sections/order as ci-sweeper/docs-triage detects).
3. `set -euo pipefail` + `umask 027` + `export LC_ALL=C.UTF-8`
4. `SCRIPT_DIR=...` then `source "${SCRIPT_DIR}/lib/all.sh"` (copy via `scripts/ai/sync_skill_lib.sh`; do not hand-edit skill `scripts/lib/`).
5. `# Global variables` block with purpose comments where non-obvious (DOC-05).
6. Functions: `show_usage` → `parse_arguments` → remaining functions **a-z** → `main` last (G-03).
7. Entry: `if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then main "$@"; fi`

### Documentation level

- Every function: separator + one-line summary + **Arguments** / **Global Variables** / **Returns** (use `None` when N/A) + **Usage** when helpful — same density as `detect_ci_failures.sh`, not stripped stubs.
- Comments in **English** (DOC-06).
- Header Design Rules must state: facts only; exit 0 always; JSON via `lib/json.sh`; per-sensor recoverable failures → `warnings[]`.

### CLI / JSON contract

- Always **exit 0**; errors → `status=error`, `message`, empty arrays, `skip=true` as appropriate.
- `status=ok` with partial sensors: include `warnings[]` (string array).
- `skip=true` iff both `signals` and `hotspots` are empty.
- `show_usage` documents options/examples and exits 0.
- Accept `--scope staged|all|range` and `--since` for loop-detect parity; **default `SCOPE=all`**.

### Dependencies documented in header

| Required  | Optional / self-managed                                                                     |
| --------- | ------------------------------------------------------------------------------------------- |
| bash, git | node + npm (docs sensor); pinned `markdown-link-check` installed into local cache by detect |

Missing node/npm or mlc install failure: warning + skip docs-link sensor; do not `status=error` the whole run.

### Testing (TEST-00)

- Add `test/bats/...` suite mirroring the skill script path (follow stem `bats` rules after `apm install`).
- Cover: empty → skip; markers; deps fixture; docs with pre-seeded mlc cache or mocked install; churn threshold; one sensor failure → warnings + others continue; always exit 0.

## Skill / reference updates (same change)

- `category-input-schema.md`: closed `kind` list; optional `warnings[]`; note default detect scope is full-repo.
- `category-debt-taxonomy.md` / `common-checklist.md`: lint exclusion; markers secondary; no migration playbook.
- `SKILL.md`: keep “do not run detection”; no workflow yet.

## Error handling

| Condition                                       | Behavior                                                    |
| ----------------------------------------------- | ----------------------------------------------------------- |
| Not a git repo                                  | `status=error`, exit 0                                      |
| Invalid `--scope` / missing `--since` for range | `status=error`, exit 0                                      |
| Single sensor failure                           | that sensor empty + `warnings[]`; continue                  |
| mlc install/run fail                            | warn; skip `broken_doc_ref` only; `stale_doc` may still run |
| Unknown manifest                                | skip that ecosystem silently or warn once                   |

## Out of scope / follow-ups

- `on-loop-tech-debt.yaml` cron caller.
- Shared EOL policy file injection from caller env.
- Optional split of sensors into sourced modules if the entry file exceeds maintainability (~FUNC-01).

## Spec self-review

- No TBD placeholders for v1 sensor set or script DOC contract.
- Consistent with full-repo default and lint non-overlap.
- Deliverable scoped to detect + refs + bats only.
- mlc: self-install required; no dual broken-link implementations.
