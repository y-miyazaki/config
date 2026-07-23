# Loop Automation Report Format

> **Superseded layout:** Loop automation skills no longer sync shared `common-loop-*.md` into `references/`. Each skill owns its contract locally.

## Where rules live now

| Concern                                | Location                                                                           | When loaded                                             |
| -------------------------------------- | ---------------------------------------------------------------------------------- | ------------------------------------------------------- |
| Survey/apply report shapes             | `references/common-output-format.md` (+ `common-output-format-loop.md` when split) | Every run                                               |
| Automation constraints + PR body rules | `references/category-automation-envelope.md`                                       | Automation path only (`## Constraints` with `may_edit`) |
| PR synthesis templates                 | `assets/pr-body-template-survey.md`, `assets/pr-body-template.md`                  | Automation synthesis                                    |
| Platform PR composition                | [loop-pr-body-skill-contract.md](loop-pr-body-skill-contract.md)                   | Workflow / maintainers                                  |

## Edit gate

Automation runs branch on **`may_edit`** from `## Constraints` (injected by `loop-prompt-generate`):

| `may_edit` | Behavior                                                                          |
| ---------- | --------------------------------------------------------------------------------- |
| `false`    | Survey — emit `### Candidates`; no file edits                                     |
| `true`     | Apply — edit within allowlist; emit `### Changes` / deferrals + `## Verification` |

Interactive runs resolve `may_edit` from natural language (default survey; explicit fix language → apply). See each skill's `SKILL.md` Workflow.

## Four-plane contract (caller vs skill)

Loop callers configure four independent planes. Skills branch only on planes 2–3 from `## Constraints`; they **must not** read `level` or `delivery`.

| Plane     | Caller inputs                                                 | Visible to skill?         |
| --------- | ------------------------------------------------------------- | ------------------------- |
| Autonomy  | `level` (L1/L2/L3)                                            | No — platform job routing |
| Edit gate | `may_edit`                                                    | Yes                       |
| Artifact  | `write_target` (`fix` \| `report`), `report_file` when report | Yes                       |
| Delivery  | `delivery` (`open_pr`, `issue`, `log`, …)                     | No — `loop-finalize` only |

Spec: [Loop write target & delivery design](../../superpowers/specs/2026-07-23-loop-write-target-delivery-design.md). Caller reference: [loop-caller-inputs-reference.md](workflows/loop-caller-inputs-reference.md).

When `may_edit: true`:

| `write_target` | Agent persists                                    |
| -------------- | ------------------------------------------------- |
| `fix`          | Source/docs/manifests within allowlist            |
| `report`       | Structured file at `report_file` within allowlist |

## Skills using this pattern

| Skill        | Survey primary   | Apply primary | Skip / defer subsection                  |
| ------------ | ---------------- | ------------- | ---------------------------------------- |
| changelog    | `### Candidates` | `### Changes` | `### Skipped`                            |
| ci-sweeper   | `### Candidates` | `### Changes` | `### Deferred` (+ `### Watch` on survey) |
| docs-updater | `### Candidates` | `### Changes` | `### Deferred`                           |
| refactor     | `### Candidates` | `### Changes` | `### Deferred`                           |
| tech-debt    | `### Candidates` | `### Changes` | `### Deferred`                           |

## Overview contract

Every run emits `## Overview` first. Write 1–2 plain-language sentences (~280 characters max).

| Element   | Include                                                                   |
| --------- | ------------------------------------------------------------------------- |
| Trigger   | Scan scope, workflow/job, or commit range                                 |
| Substance | Dominant categories, named files, or failure types — **not counts alone** |
| Action    | Recorded, fixed, deferred, or no edits                                    |

Per-skill examples live in each skill's `common-output-format.md` and `assets/pr-body-template*.md`.

## Session metrics

Automation runs append `## Session Metrics` per each skill's `category-automation-envelope.md`. Session metrics are verifier/log output — not copied into PR body.
