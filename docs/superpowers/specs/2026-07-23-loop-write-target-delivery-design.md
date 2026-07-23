# Loop Write Target and Delivery Design

**Status:** Approved (design session 2026-07-23)  
**Date:** 2026-07-23  
**Related:** [Loop Engineering Design](../../explanation/loop-engineering/loop-engineering-design.md), [Loop PR Body Skill Contract](../../explanation/loop-engineering/loop-pr-body-skill-contract.md), [Loop Caller Inputs Reference](../../explanation/loop-engineering/workflows/loop-caller-inputs-reference.md), [common-loop-triage-format](../../explanation/loop-engineering/common-loop-triage-format.md)

## Problem

Loop automation conflates three independent concerns:

1. **Autonomy** — human review vs auto-merge vs read-only observation (`level` L1/L2/L3).
2. **Worktree edits** — whether the agent persists changes in git (`may_edit`).
3. **Artifact kind** — fix source files vs write a structured report (`write_target`).

Today `loop-prompt-generate` maps `L2`/`L3` → `may_edit: true` and injects _"a report alone is not sufficient when may_edit is true"_. That makes every L2+ loop an implicit **fix** loop. Report-only loops (e.g. tech-debt) work only by narrowing `allowlist` to `docs/report/**` — a skill-specific hack.

External delivery (GitHub Issue, Notion, PR comment) is not modeled. Skills should not embed platform integrations.

## Goals

- Separate **four planes** so new skills and workflows extend without redesigning agent contracts.
- Keep **Agent Skills** aware only of worktree edit semantics (`may_edit`, `write_target`, `report_file`).
- Keep **LE workflow / finalize** responsible for **delivery** outside the worktree (`open_pr`, `issue`, `notion`, `log`, `none`).
- Retain `level` as an **autonomy preset** (worktree job selection, auto-merge) — not as a proxy for fix vs report.
- Generalize `report_file` across all skills; tech-debt is the first consumer, not a special case.

## Non-Goals

- Phase 1 implementation of Notion / Backlog connectors (design the `delivery` enum and caller contract only).
- Composite delivery (`open_pr` + `issue` in one run) — defer; use two loops or a later ADR.
- Putting `delivery` or external API details into `## Constraints` or skill `category-automation-envelope.md`.
- Removing `level` from callers — it remains required for platform job routing.

## Architecture: Four Planes

```text
┌─────────────────────────────────────────────────────────────────┐
│ 1. Autonomy (platform)     level: L1 | L2 | L3                  │
│    → worktree on/off, auto-merge preset                         │
├─────────────────────────────────────────────────────────────────┤
│ 2. Edit gate (agent)       may_edit: true | false               │
│    → persist to worktree or survey-only                         │
├─────────────────────────────────────────────────────────────────┤
│ 3. Artifact (agent)        write_target: fix | report           │
│    report_file (when report)                                    │
│    → what git tracks after the agent run                        │
├─────────────────────────────────────────────────────────────────┤
│ 4. Delivery (platform)     delivery: open_pr | issue | notion  │
│                            | log | none                         │
│    → how approved outcomes reach humans/systems outside git     │
└─────────────────────────────────────────────────────────────────┘
```

**Separation rule:**

| Plane     | Question                         | Seen by skill?              |
| --------- | -------------------------------- | --------------------------- |
| Autonomy  | How much human gate / automerge? | No                          |
| Edit gate | Touch worktree?                  | Yes                         |
| Artifact  | What in git?                     | Yes (when `may_edit: true`) |
| Delivery  | Where after APPROVE?             | No                          |

One-line mnemonic: **`write_target` = git inside; `delivery` = world outside.**

## Field Definitions

### `level` (caller — Autonomy preset)

| Value | Platform behavior                                           | Does **not** imply         |
| ----- | ----------------------------------------------------------- | -------------------------- |
| `L1`  | `agent-l1` job; no worktree; no finalize PR path by default | `may_edit`, `write_target` |
| `L2`  | `agent-l2` + finalize; human merge on bot PR                | fix vs report              |
| `L3`  | Same as L2 + GitHub auto-merge on bot PR                    | fix vs report              |

`level` must **not** derive `may_edit` or `write_target` after this change. Callers supply those explicitly (defaults below are documentation presets only, not code-derived).

### `may_edit` (caller → `## Constraints` — Edit gate)

| Value   | Agent behavior                                                                            |
| ------- | ----------------------------------------------------------------------------------------- |
| `false` | Survey shape (`### Candidates`); no worktree edits; omit `### Changes`, `## Verification` |
| `true`  | Apply shape; persist within allowlist                                                     |

### `write_target` (caller → `## Constraints` — Artifact)

Valid only when `may_edit: true`. Omit or treat as ignored when `may_edit: false`.

| Value    | Agent writes                              | Typical allowlist                      |
| -------- | ----------------------------------------- | -------------------------------------- |
| `fix`    | Source/docs/manifests to resolve findings | `src/**`, `docs/**`, `CHANGELOG.md`, … |
| `report` | Structured report at `report_file`        | `docs/report/<domain>/**`              |

Optional **secondary** closed-set fixes (tech-debt today): caller narrows an additional fix allowlist (e.g. `docs/**`, `package.json`) without a third enum value — `write_target` stays `report`; verifier enforces diff scope.

### `report_file` (detect → `target_json` and/or `## Constraints`)

| Condition              | Required?                                                                                    |
| ---------------------- | -------------------------------------------------------------------------------------------- |
| `write_target: report` | **Yes** — detect script or caller supplies path (e.g. `docs/report/tech-debt/2026-07-23.md`) |
| `write_target: fix`    | Optional — secondary artifact path if skill emits a report in addition to fixes              |

All loop skills **may** receive `report_file` in detect JSON; only report-mode loops require a non-empty value at verify time.

### `delivery` (caller only — platform)

Not injected into skill `## Constraints`.

| Value     | When used                | Input to finalize                               |
| --------- | ------------------------ | ----------------------------------------------- |
| `open_pr` | L2/L3 worktree loops     | `git diff` + agent `## Overview` / `## Summary` |
| `issue`   | Triage without git edits | Agent session report (structured markdown)      |
| `notion`  | External doc systems     | Same as `issue`                                 |
| `log`     | L1 observation           | Run-log / state only                            |
| `none`    | Dry-run / local          | No external action                              |

Existing `loop-notify-pr` (comment on human PR) remains a **platform** concern triggered by `pull_request` mode + finalize, not a skill field.

## Caller Workflow Shape

Alphabetical `with:` keys per repository convention.

### Action loop (fix)

```yaml
delivery: open_pr
level: L2
may_edit: true
write_target: fix
allowlist: src/**,tests/**
```

### Report loop

```yaml
delivery: open_pr
level: L2
may_edit: true
write_target: report
allowlist: docs/report/tech-debt/**/*.md
detect_domain_env_json: '{"TECH_DEBT_DIR":"docs/report/tech-debt"}'
# report_file: supplied by detect in target_json / detect result
```

### Observation / Issue-only

```yaml
delivery: issue
level: L1
may_edit: false
# write_target and report_file omitted
```

## `## Constraints` Injection (skill-visible)

`loop-prompt-generate` emits only planes 2–3:

```text
## Constraints
may_edit: true
write_target: report
report_file: docs/report/tech-debt/2026-07-23.md
Allowed paths: docs/report/tech-debt/**/*.md.
Do NOT modify any other files.
Do not claim files were modified unless git would show real changes.
```

Replace today's unconditional line _"a report alone is not sufficient when may_edit is true"_ with target-aware text:

| `write_target` | Persistence obligation                                                                                                                               |
| -------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `fix`          | Must persist fixes within allowlist; survey-only output is insufficient                                                                              |
| `report`       | Must persist `report_file` within allowlist; source fixes outside allowlist are forbidden unless caller adds secondary fix globs and verifier allows |

## Valid Combinations (normative)

| `may_edit` | `write_target` | `delivery` | Example loop                                 |    Valid    |
| :--------: | :------------: | :--------: | -------------------------------------------- | :---------: |
|  `false`   |       —        |   `log`    | L1 observe                                   |     Yes     |
|  `false`   |       —        |  `issue`   | Issue triage                                 |     Yes     |
|  `false`   |       —        |  `notion`  | External doc triage                          |     Yes     |
|  `false`   |       —        | `open_pr`  | —                                            |   **No**    |
|   `true`   |     `fix`      | `open_pr`  | ci-sweeper, refactor, docs-triage, changelog |     Yes     |
|   `true`   |    `report`    | `open_pr`  | tech-debt                                    |     Yes     |
|   `true`   |    `report`    |  `issue`   | Duplicate channels                           | **No** (v1) |
|   `true`   |     `fix`      |   `none`   | Local experiment                             | Yes (rare)  |

`loop-detect` or caller validation should reject invalid rows before execute.

## Skill Contract Changes

Every loop automation skill:

1. Branch on `may_edit` and `write_target` from `## Constraints` — **never** on `level` or `delivery`.
2. Load `category-automation-envelope.md` on automation path; document `write_target` and `report_file` fields.
3. Keep unified output shapes in `common-output-format.md` (`Overview`, `Summary`, `Changes`/`Candidates`, `Deferred`, `Verification`).
4. Persisted report body sections remain skill-specific (e.g. tech-debt Critical/High tables).

Skills **must not** reference GitHub Issue, Notion, Backlog APIs, or `delivery`.

## Platform Changes (implementation phases)

### Phase 0 — Spec and docs (this document)

- Adopt four-plane model in loop-engineering docs.
- Deprecate wording "L2 = file fix" in workflow design docs; use `write_target`.

### Phase 1 — Caller inputs + constraints

- Add `may_edit`, `write_target`, `delivery` to `ci-loop-caller.yaml` inputs (explicit; stop deriving `may_edit` from `level` in `build_constraints.sh`).
- Pass `may_edit`, `write_target`, `report_file` into `emit_loop_constraints`.
- Enrich `target_json` with `report_file` when detect supplies it (generalize beyond tech-debt).
- Caller validation script: combination matrix above.

### Phase 2 — Migrate dogfood callers

| Caller                | `may_edit` | `write_target` | `delivery` |
| --------------------- | :--------: | :------------: | :--------: |
| `on-loop-changelog`   |   `true`   |     `fix`      | `open_pr`  |
| `on-loop-ci-sweeper`  |   `true`   |     `fix`      | `open_pr`  |
| `on-loop-docs-triage` |   `true`   |     `fix`      | `open_pr`  |
| `on-loop-refactor`    |   `true`   |     `fix`      | `open_pr`  |
| `on-loop-tech-debt`   |   `true`   |    `report`    | `open_pr`  |

### Phase 3 — Skills

- Update `category-automation-envelope.md` for all loop skills (changelog, ci-sweeper, docs-updater, refactor, tech-debt).
- Align tech-debt workflow design doc with skill (report primary; optional closed-set doc/manifest fixes via allowlist).
- Eval tasks for `write_target: report` on non-tech-debt skills (optional, when those loops ship).

### Phase 4 — Delivery adapters

- `delivery: issue` finalize adapter (consumes agent report; no skill changes).
- `notion` / `backlog` as additional finalize backends behind same interface.

## `target_json` Extension

```json
{
  "mode": "integration",
  "key": "integration:main",
  "from": { "branch": "main", "ref": "abc123" },
  "to": { "branch": "main" },
  "finalize": "open_pr",
  "report_file": "docs/report/tech-debt/2026-07-23.md"
}
```

`delivery` stays on caller / detect env — not required inside `target_json` unless detect needs per-target delivery overrides later. `target.finalize` is derived from `delivery` (and optional `git_landing_*` on `loop-detect` when `delivery: open_pr`).

## Migration Notes

- **Backward compatibility:** `may_edit` and `write_target` are **required** on callers; `loop-detect` fail-closes with `skip_reason: config_error` when omitted. `emit_loop_constraints_from_level` remains deprecated for prompt-generation tests only — not for detect. Reject `L1` + `may_edit: true` at validation (read-only `agent-l1` routing).
- **`loop-report-*` naming:** Report loops are `write_target: report`, not a separate skill family requirement. Name prefix `loop-report-<domain>` remains optional documentation convention.
- **tech-debt closed-set fixes:** Keep as allowlist + verifier rule, not `write_target: hybrid`.

## References

- [Implementation plan](../plans/2026-07-23-loop-write-target-delivery.md) — phased tasks (platform → callers → skills)
- [Loop PR Body Skill Contract](../../explanation/loop-engineering/loop-pr-body-skill-contract.md) — skill owns narrative; platform owns mechanical delivery
- [loop-notify-pr Specification](../../reference/loop-notify-pr-specification.md) — platform comment delivery
- `build_constraints.sh` — constraints injection (to be updated Phase 1)
