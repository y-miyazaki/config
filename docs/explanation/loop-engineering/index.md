# Loop Engineering

Understanding-oriented design docs for autonomous CI and documentation loops in this repository.

## Reading order

1. [Loop Engineering Design](loop-engineering-design.md) — invariants, L1/L2/L3, phase contract
2. [Multi-Branch Loops Design](multi-branch-loops-design.md) — platform targets, `LOOP_*`, state
3. [Loop Caller Workflows Design](loop-caller-workflows-design.md) — shared `on-loop-*.yaml` shell
4. [Loop Caller Reusable Workflow Design](loop-caller-reusable-design.md) — `ci-loop-caller.yaml` refactor
5. [Loop Engineering Checklist](../../reference/loop-engineering-checklist.md) — new loop author checklist
6. Per-loop workflow designs — see [Multi-Branch Loops Design — Workflow Design Documents](multi-branch-loops-design.md#workflow-design-documents)

## Topic index

| Topic                                              | Document                                                                               |
| -------------------------------------------------- | -------------------------------------------------------------------------------------- |
| Platform (targets, `LOOP_*`, state)                | [Multi-Branch Loops Design](multi-branch-loops-design.md)                              |
| Shared `on-loop-*.yaml` layout                     | [Loop Caller Workflows Design](loop-caller-workflows-design.md)                        |
| **loop-docs-triage** workflow + doc drift detect   | [Docs Triage Workflow Design](workflows/loop-docs-triage-workflow-design.md)           |
| **loop-ci-sweeper** workflow + detect + CI env     | [CI Sweeper Workflow Design](workflows/loop-ci-sweeper-workflow-design.md)             |
| **loop-changelog** workflow + conventional commits | [Changelog Workflow Design](workflows/loop-changelog-workflow-design.md)               |
| **loop-report-tech-debt** workflow + debt report   | [Report Tech Debt Workflow Design](workflows/loop-report-tech-debt-workflow-design.md) |
| Loop invariants + L3 gates                         | [Loop Engineering Design](loop-engineering-design.md)                                  |
| Ubiquitous language (detect, A'/B, findings)       | [Ubiquitous Language](CONTEXT.md)                                                      |

## Reference (outside this section)

- [Specification](../../reference/specification.md) — action I/O, detect script contract
- [loop-notify-pr Specification](../../reference/loop-notify-pr-specification.md)
- [Loop Engineering Checklist](../../reference/loop-engineering-checklist.md)

## CI healing summary

- One **ci-sweeper** engine handles integration branches and PR heads (`LOOP_INTEGRATION_BRANCHES`, `LOOP_PULL_REQUESTS`).
- No separate `loop-pr-ci-healer` package.
- Default **`DEFAULT_LEVEL=L2`**; L3 paths opt-in after promotion gate.
- Bot PRs excluded by default (`LOOP_PR_INCLUDE_BOTS` to opt in).
