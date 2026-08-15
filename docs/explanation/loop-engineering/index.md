# Loop Engineering

Understanding-oriented design docs for autonomous CI and documentation loops in this repository.

Documents sit in one folder on disk. **Read them by layer**, not as a flat list. Per-loop callers already live under [`workflows/`](workflows/loop-caller-inputs-reference.md); platform and cross-cutting contracts do not.

```text
Layer A  Nesting (shared job graph)
         on-loop-* → ci-loop-caller → ci-loop-agent (L1 | L2/L3)
Layer B  Per-loop workflow
         one on-loop-<name>.yaml + workflows/loop-<name>-workflow-design.md
Layer C  Cross-cutting contracts
         PR body, notify, detect I/O, report shapes — not a fourth pipeline stage
```

## Layer A — Nesting (shared platform)

Job graph, phases, and which **workflow / action files** own them. Optional jobs such as `ack-trigger` are caller UX on this graph, not a new phase.

| Read                                                                   | Owns                                                             | Target files                                                  |
| ---------------------------------------------------------------------- | ---------------------------------------------------------------- | ------------------------------------------------------------- |
| [Ubiquitous Language](CONTEXT.md)                                      | Phase names (detect / execute / verify / finalize)               | —                                                             |
| [Loop Engineering Design](loop-engineering-design.md)                  | Invariants, L1/L2/L3, retry, full-stack diagram (draw once)      | `.github/actions/loop-*`, detect script envelope              |
| [Loop Caller Workflows Design](loop-caller-workflows-design.md)        | Shared `on-loop-*.yaml` shell: detect → execute → record-skip    | `on-loop-*.yaml`, `ci-loop-caller.yaml`, `ci-loop-agent.yaml` |
| [Loop Caller Reusable Workflow Design](loop-caller-reusable-design.md) | `ci-loop-caller` jobs, optional `ack-trigger`, `with:` vs `env:` | `ci-loop-caller.yaml`, `ci-loop-agent.yaml`                   |
| [Multi-Branch Loops Design](multi-branch-loops-design.md)              | Targets, matrix, state, caller input map                         | state files, `loop-detect` handoff                            |
| [Loop-Capable Skills](loop-capable-skills.md)                          | Skill family bound to loops                                      | `.apm/packages/**/skills/`                                    |

## Layer B — Per-loop workflow

Each loop is a thin `on-loop-<name>.yaml` plus a design page. Input key lookup is **not** a platform design doc; it is the shared reference for those callers.

| Loop                 | Design                                                                  | Caller file                         |
| -------------------- | ----------------------------------------------------------------------- | ----------------------------------- |
| (all)                | [Caller Inputs Reference](workflows/loop-caller-inputs-reference.md)    | `ci-loop-caller.yaml` `with:` keys  |
| changelog            | [Changelog](workflows/loop-changelog-workflow-design.md)                | `on-loop-changelog.yaml`            |
| ci-sweeper           | [CI Sweeper](workflows/loop-ci-sweeper-workflow-design.md)              | `on-loop-ci-sweeper.yaml`           |
| docs-updater         | [Docs Updater](workflows/loop-docs-updater-workflow-design.md)          | `on-loop-docs-updater.yaml`         |
| refactor             | [Refactor](workflows/loop-refactor-workflow-design.md)                  | `on-loop-refactor.yaml`             |
| tech-debt            | [Report Tech Debt](workflows/loop-tech-debt-workflow-design.md)         | `on-loop-tech-debt.yaml`            |
| github-issue-triage  | [Issue Triage](workflows/loop-github-issue-triage-workflow-design.md)   | `on-loop-github-issue-triage.yaml`  |
| github-issue-autofix | [Issue Autofix](workflows/loop-github-issue-autofix-workflow-design.md) | `on-loop-github-issue-autofix.yaml` |
| github-pr-revise     | [PR Revise](workflows/loop-github-pr-revise-workflow-design.md)         | `on-loop-github-pr-revise.yaml`     |

Also listed from [Multi-Branch Loops Design — Workflow Design Documents](multi-branch-loops-design.md#workflow-design-documents).

## Layer C — Cross-cutting contracts

Shared shapes that apply to many loops. They are **not** nested jobs.

| Topic                                     | Document                                                                        | Target files                                             |
| ----------------------------------------- | ------------------------------------------------------------------------------- | -------------------------------------------------------- |
| Action / detect I/O                       | [Specification](../../reference/specification.md)                               | `.github/actions/loop-*`, `detect_*.sh`                  |
| PR body (templates, Created By, validate) | [Loop PR Body Skill Contract](loop-pr-body-skill-contract.md)                   | `render_pr_body.sh`, skill `assets/pr-body-template*.md` |
| Survey/apply report shape                 | [Loop Automation Report Format](common-loop-triage-format.md)                   | skill output comments                                    |
| PR comment notify                         | [loop-notify-pr Specification](../../reference/loop-notify-pr-specification.md) | `.github/actions/loop-notify-pr/`                        |
| New-loop author checklist                 | [Loop Engineering Checklist](../../reference/loop-engineering-checklist.md)     | —                                                        |
| Canonical map / when to edit docs         | [Documentation Maintenance](documentation-maintenance.md)                       | this `docs/explanation/loop-engineering/` tree           |

## Out of the reading path

Dated Superpowers specs and plans under `docs/superpowers/` are implementation history. Do not treat them as the live platform map.

## Reading order (first time)

1. Layer A: [Design](loop-engineering-design.md) → [Reusable caller](loop-caller-reusable-design.md)
2. Layer B: the loop you are changing
3. Layer C: only the contract that matches the files you touch
