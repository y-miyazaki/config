# CI Healing Loops Design

> **This document was split.** Use the links below to avoid duplication.

| Topic                                          | Document                                                                   |
| ---------------------------------------------- | -------------------------------------------------------------------------- |
| Platform (targets, `LOOP_*`, state)            | [Multi-Branch Loops Design](multi-branch-loops-design.md)                  |
| Shared `on-loop-*.yaml` layout                 | [Loop Caller Workflows Design](loop-caller-workflows-design.md)            |
| **loop-ci-sweeper** workflow + detect + CI env | [CI Sweeper Workflow Design](workflows/loop-ci-sweeper-workflow-design.md) |
| Loop invariants + L3 gates                     | [Loop Engineering Design](loop-engineering-design.md)                      |

## Summary

- One **ci-sweeper** engine handles integration branches and PR heads (`LOOP_INTEGRATION_BRANCHES`, `LOOP_PULL_REQUESTS`).
- No separate `loop-pr-ci-healer` package.
- Default **`DEFAULT_LEVEL=L2`**; L3 paths opt-in after promotion gate.
- Bot PRs excluded by default (`LOOP_PR_INCLUDE_BOTS` to opt in).
