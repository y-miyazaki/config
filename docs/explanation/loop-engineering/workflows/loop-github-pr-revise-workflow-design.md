# PR Revise Workflow Design

| Layer        | Document                                                                                                                           |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| Platform     | [Multi-Branch Loops Design](../multi-branch-loops-design.md)                                                                       |
| Caller shell | [Loop Caller Reusable Design](../loop-caller-reusable-design.md) (branch / PR-head)                                                |
| Spec         | [Issue Autofix and PR Revise Full Design](../../../superpowers/specs/2026-08-11-issue-autofix-pr-revise-full-design.md)            |
| Boundaries   | [Entity Caller Responsibility Separation](../../../superpowers/specs/2026-08-11-entity-caller-responsibility-separation-design.md) |
| Invariants   | [Loop Engineering Design](../loop-engineering-design.md)                                                                           |

**Artifacts:** `on-loop-github-pr-revise.yaml` · skill `github-pr-revise` · `detect_pr_revise.sh` · `ci-loop-caller.yaml`

## Purpose

Single intake for PR revision from human feedback: conversation or review comments containing default **`@loop`** (caller `mention` overrides) + `repository_dispatch` / `workflow_dispatch` → **branch / PR-head** caller.

Detect skips bots and comments without the mention token. Default landing: `git_landing_pull_request=push_head` (stacked via `open_pr`).

## Caller shape

```text
on-loop-github-pr-revise.yaml
  loop → uses ci-loop-caller.yaml
           detect  → detect_pr_revise.sh
           execute → ci-loop-agent (may_edit=true)
           finalize → push_head (default) or open_pr
```

`issue_comment` jobs run only when `github.event.issue.pull_request` is set.

## Trigger UX (ACK + thread reply)

After detect proceeds on a comment webhook:

| Stage | Behavior |
| ----- | -------- |
| Start ACK | `eyes` reaction on `comment.id` (`ci-loop-caller`) |
| Done reply | Inline review: threaded REST reply; conversation comment: follow-up PR comment (`loop-notify-pr`) |
| Marker | Run-level `loop-notify-pr` marker comment unchanged |
| Resolve | Human only — no auto-resolve |

Detect JSON includes `result.comment_id`, `result.event_name`, and inline review fields (`path`, `line`, `side`, `diff_hunk`) when hydrated from the webhook. See [Detect result](#detect-result).

## Detect result

`detect_pr_revise.sh` emits `result` facts consumed via file-backed detect JSON / loop-detect prompt:

| Field | Source | Notes |
| ----- | ------ | ----- |
| `pr_number` | PR / issue / dispatch payload | Required to proceed |
| `mention` | `PR_MENTION` (default `@loop`) | Mention gate on comment webhooks |
| `comment_body` | `comment.body` or dispatch feedback | Mention matched against this |
| `comment_id` | `comment.id` | JSON number when present |
| `event_name` | `GITHUB_EVENT_NAME` | When set on webhook path |
| `path` | `comment.path` | Set for `pull_request_review_comment`; empty for `issue_comment` |
| `line` | `comment.line` or `comment.original_line` | JSON number when present |
| `side` | `comment.side` | `LEFT` / `RIGHT` when present |
| `diff_hunk` | `comment.diff_hunk` | Inline hunk text when present |
| `actor` | comment user or sender login | Informational |



--- Rules in scope for this file ---
[From: /workspace/tmp/wt-690/CLAUDE.md]
@AGENTS.md

# Project Instructions

## Edit routing (MUST)

| Edit here (source of truth)                                                                                          | Do not edit                                                                         |
| -------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| `.apm/packages/<pkg>/` (instructions, skills, hooks, MCP config)                                                     | `.agents/`, `.claude/`, `.codex/`, `.cursor/`, `.kiro/`, `.vscode/`, `apm_modules/` |
| `scripts/lib/`                                                                                                       | `.apm/packages/*/.apm/skills/*/scripts/lib/`                                        |
| `scripts/{shell-script,go,terraform}/validate.sh`, `scripts/shell-script/fix_function_doc_order.sh`                  | Paired skill `scripts/` copy                                                        |
| `.apm/packages/<pkg>/.apm/skills/<skill>-review/references/category-*.md`                                            | Generated `## Guidelines` in instructions (unless accepting overwrite on next sync) |
| Repo-only paths (for example `scripts/terraform/module_updater.sh`, `.github/actions/**/lib/`, `.github/workflows/`) | —                                                                                   |

**Distributable vs maintainer-only:** `.apm/packages/**` ships to other repositories — portable wording only. This-repo rules → [.apm/AGENTS.md](.apm/AGENTS.md) or this file, never package sources.

## Conventions

| Topic           | Rule             |
| --------------- | ---------------- |
| Temporary files | Write to `tmp/`. |

[From: /workspace/tmp/wt-690/AGENTS.md]
# AGENTS.md

Operational constitution for AI-assisted development agents. Self-contained — no external file is required.

---

## Execution

- Minimal surgical diffs; no unrelated refactor, cleanup, modernization, or optimization unless approved.
- Stay within requested scope; label off-scope suggestions explicitly.
- Never fabricate APIs, commands, paths, or behavior; state "unknown" when uncertain.
- Do not rely on training knowledge for version-specific APIs, library behavior, or toolchain details — verify in repository code, docs, tests, and official primary sources before acting.
- Read existing code before modifying; search related implementations and shared interfaces.
- Stop and Ask before: destructive operations, conflicting requirements, unclear specifications, irreversible architectural decisions, security-sensitive ambiguity, or disproportionate cost.
- Do not expose secrets, credentials, or sensitive tokens in outputs, logs, or commits.
- After two failed attempts on the same approach: diagnose root cause and switch strategy; do not patch incrementally.
- No placeholder implementations unless explicitly requested.
- Test-first for code changes: write or update tests with sufficient cases before or alongside implementation; code modifications MUST include corresponding test additions or updates.
- Prefer behavior and tests over re-running mechanical lint/format; state what was not verified and why.
- MUST NOT weaken, remove, or bypass tests or validations solely to make checks pass.

## Completion (MUST state in final response)

1. **Implementation:** Overview of changes made.
2. **Verification:** What was verified (behavior/tests), deferred, or unavailable — lint/format re-runs are not required proof.
3. **Risks:** Assumptions made and residual risks.

[… 2 more rule(s) omitted — use auto_inject_rules=false to disable]

--- tip: run 'lean-ctx setup' to configure agent rules for optimal AI integration ---
