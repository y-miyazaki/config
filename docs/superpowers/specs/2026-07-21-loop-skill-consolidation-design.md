# Loop Skill Consolidation Design

**Status:** Approved (grill-me 2026-07-21)  
**Date:** 2026-07-21

## Problem

`loop-*` APM packages duplicate domain skills (`loop-refactor` / `refactor`, `loop-docs-triage` / `docs-updater`) or isolate small skills (`loop-ci-sweeper`, `loop-changelog`, `loop-report-tech-debt`) that fit naturally in `common`. Check criteria drift; `detect_changes.sh` exists in two divergent forks.

## Goals

- One skill per domain; loop callers pass JSON envelope + `## Constraints` — no duplicate loop entry skills.
- Move all maintenance skills into `.apm/packages/common/.apm/skills/`.
- Drop `loop-` prefix from **skill names**; keep Loop Engineering platform (`ci-loop-caller`, `on-loop-*.yaml` filenames, `loop-detect` / `loop-finalize`).
- Update callers (`skill_name`, `detect_script`, `prompt_instructions`) and necessary docs.

## Grill decisions (locked)

| Topic | Decision |
| ----- | -------- |
| `refactor` home | `common/.apm/skills/refactor/`; abolish `refactor` APM package |
| `detect_changes.sh` | `loop-docs-triage` canonical; merge useful `docs-updater` behavior |
| Workflow filenames | Keep `on-loop-*.yaml`; only references change |
| Delivery | Single effort on `main` |
| Docs | Update all docs that reference old skill/package paths |

## Target layout

```text
.apm/packages/common/.apm/skills/
  refactor/              # interactive + loop envelope; scripts/detect_refactor.sh
  docs-updater/          # hook/manual + loop findings; scripts/detect_changes.sh (unified)
  ci-sweeper/            # was loop-ci-sweeper
  changelog/             # was loop-changelog
  report-tech-debt/      # was loop-report-tech-debt
```

Delete packages: `loop-refactor`, `loop-docs-triage`, `loop-ci-sweeper`, `loop-changelog`, `loop-report-tech-debt`, `refactor`.

## Skill naming

| Old skill | New skill |
| --------- | --------- |
| `loop-refactor` | (merged into `refactor`) |
| `loop-docs-triage` | (merged into `docs-updater`) |
| `loop-ci-sweeper` | `ci-sweeper` |
| `loop-changelog` | `changelog` |
| `loop-report-tech-debt` | `report-tech-debt` |

## Non-goals

- Renaming `ci-loop-caller.yaml` or loop platform actions
- Changing `loop_name` state keys or detect envelope platform schema
- Merging unrelated domains (e.g. ci-sweeper into docs-updater)

## Risks

| Risk | Mitigation |
| ---- | ---------- |
| `detect_changes.sh` regression | Keep bats; run after merge |
| Broken `detect_script` paths in workflows | Update all five `on-loop-*.yaml` in step 3 |
| External docs cite `loop-*` skill paths | Update architecture + loop-engineering docs |
