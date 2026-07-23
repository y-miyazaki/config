# Loop Triage Format Unification — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans.

**Goal:** Unify loop triage skills on survey/apply output shapes with substance-rich Overview text.

**Architecture:** Canonical format in `docs/explanation/loop-engineering/common-loop-triage-format.md`; each skill references it; `validate_agent_report.sh` validates survey vs apply.

**Tech Stack:** APM skill packages, Bats, loop-execute shell validation.

## Global Constraints

- Edit `.apm/packages/` only; run `apm install --update` after package changes.
- Do not edit generated `.agents/`, `.cursor/`, etc.
- Overview must name substance (categories/files), not counts alone.

---

## Task 1: Platform docs and validation ✅

- [x] `common-loop-triage-format.md`
- [x] Design spec `docs/superpowers/specs/2026-07-23-loop-triage-format-unification-design.md`
- [x] `validate_agent_report.sh` survey detection
- [x] `agent_output_format_criteria.md`
- [x] Bats for survey mode

## Task 2: tech-debt skill ✅

- [x] SKILL.md v2.0.0 survey/apply workflow
- [x] common-output-format, templates, input schema, checklist, scope

## Task 3: Sibling skills ✅

- [x] ci-sweeper, docs-updater, changelog output formats + survey templates
- [x] refactor Overview examples

## Task 4: Verify

- [ ] `bats test/bats/.github/actions/loop-execute/lib/validate_agent_report.bats`
- [ ] `apm install --update && apm audit --ci`

## Task 5: Review

- [ ] Bugbot on branch/uncommitted changes
- [ ] Conditional review skills per changed file types
