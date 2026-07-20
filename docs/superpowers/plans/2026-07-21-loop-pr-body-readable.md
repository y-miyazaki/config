# Loop PR Body Readable Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make loop PR bodies human-readable with agent-owned Overview/Summary tables and finalize-owned Run Metadata.

**Architecture:** Extend `notify_context.sh` to extract `## Overview` and `## Summary`; update `render_pr_body.sh` section order and Run Metadata table; add `assets/pr-body-template.md` per loop skill (mirroring [apm-triage-panel `assets/triage-template.md`](https://github.com/microsoft/apm/blob/main/.agents/skills/apm-triage-panel/assets/triage-template.md)); document contract in [Loop PR Body Skill Contract](../../explanation/loop-engineering/loop-pr-body-skill-contract.md).

**Tech Stack:** bash, jq, bats

## Global Constraints

- Pure composition in `render_pr_body.sh` (no `gh`/git).
- Redact/truncate patterns aligned with `notify_context.sh`.
- Edit skill sources under `.apm/packages/loop-*/` only (not generated `.agents/`).
- Caller workflow keys alphabetically ordered.

---

### Task 1: Platform — extract Overview + render new PR body

**Files:**

- Modify: `.github/actions/loop-execute/lib/notify_context.sh`
- Modify: `.github/actions/loop-finalize/lib/render_pr_body.sh`
- Modify: `.github/actions/loop-finalize/lib/create_pr_body.sh`
- Test: `test/bats/.github/actions/loop-execute/lib/notify_context.bats`
- Test: `test/bats/.github/actions/loop-finalize/lib/render_pr_body.bats`
- Test: `test/bats/.github/actions/loop-finalize/lib/create_pr_body.bats`

**Interfaces:**

- Produces: `agent_report_overview`, `agent_report_summary` in `notify_context_json`
- Produces: `render_run_metadata`, `render_agent_overview_section` in `render_pr_body.sh`

- [x] Add `extract_agent_report_overview`; add `agent_report_overview` to notify JSON
- [x] Replace `render_footer` with `render_run_metadata` table
- [x] Reorder: Overview → Failure context → Summary → Changes → Run Metadata → disclaimer
- [x] Update bats

### Task 2: Skills — output format contract

**Files:**

- Modify: `.apm/packages/loop-docs-triage/.apm/skills/loop-docs-triage/references/common-output-format.md`
- Modify: `.apm/packages/loop-ci-sweeper/.apm/skills/loop-ci-sweeper/references/common-output-format.md`
- Modify: `.apm/packages/loop-report-tech-debt/.apm/skills/loop-report-tech-debt/references/common-output-format.md`
- Modify: `.apm/packages/loop-changelog/.apm/skills/loop-changelog/references/common-output-format.md`

- [x] Rename session `## Summary` → `## Session Metrics` (Field \| Value table)
- [x] Add `## Overview` + `## Summary` PR body contract with tables per loop
- [x] Document per-skill Overview contract (trigger → problem → action; good/bad examples)

### Task 3: Callers + notify + docs

**Files:**

- Modify: `.github/workflows/on-loop-*.yaml` (4 callers + 4 examples)
- Modify: `.github/actions/loop-notify-pr/lib/notify.sh`
- Modify: `docs/superpowers/specs/2026-07-17-loop-pr-body-hybrid-design.md` (superseded note)
- Modify: `docs/reference/loop-notify-pr-specification.md`
- Modify: `docs/explanation/loop-engineering/workflows/loop-caller-inputs-reference.md`

- [x] Set `pr_body: ""` (disclaimer owned by finalize)
- [x] Notify: render Overview + Summary from notify context
- [x] Update design docs

## Verification (completed)

- [x] `apm install --update` + `apm.lock.yaml` (pr-body-template assets deployed)
- [x] shellcheck: `render_pr_body.sh`, `create_pr_body.sh`, `notify_context.sh`, `notify.sh`
- [x] bats: 46/46 (render_pr_body, create_pr_body, notify_context, notify)
- [x] markdown-validation: `docs/explanation/loop-engineering`, `docs/superpowers`, `loop-notify-pr-specification.md`
- [x] github-actions-validation: `.github/workflows`
- [x] waza eval: loop-docs-triage, loop-ci-sweeper, loop-changelog, loop-report-tech-debt (100% each; eval.yaml v1.2 + task prompt contract suffix)
