# Issue Autofix and PR Revise Full Implementation Design

**Status:** Implemented (detect, skills, branch callers, Bats; dogfood L2 in progress)  
**Date:** 2026-08-11  
**Primary consumers:** `issue-autofix`, `pr-revise`, `issue-triage` (dispatch handoff), Loop Engineering platform  
**Related:** [Entity Caller Responsibility Separation](2026-08-11-entity-caller-responsibility-separation-design.md), [Issue Triage Entity Loops](2026-08-11-issue-triage-entity-loops-design.md) (partially superseded), [Loop write target & delivery](2026-07-23-loop-write-target-delivery-design.md), [Loop PR body skill contract](../../explanation/loop-engineering/loop-pr-body-skill-contract.md)

## Problem

*(Resolved.)* Previously `issue-autofix` and `pr-revise` were skip-always stubs. Triage could label and comment, but humans could not drive Issue→PR or PR feedback→push through Loop Engineering without leaving the four-plane model.

## Goals

- Ship **full L2** loops for autofix and PR revise on the existing **branch / PR-head caller** (`ci-loop-caller`), not a new profile.
- Keep **thin callers**: domain facts and skip rules live in skill detect scripts.
- Wire **triage → autofix** via a trusted post-detect hook that fires `repository_dispatch` (Agent never performs HTTP dispatch).
- Reuse existing LE planes: `level`, `may_edit`, `write_target`, `delivery`, and existing `git_landing_*` inputs.
- Match other loop skills for **PR body**: skill `assets/pr-body-template.md` (+ survey variant); optional repo `.github/PULL_REQUEST_TEMPLATE.md` via `github-pr-body` when present.
- Do not push half-finished stubs: detect, execute, finalize, hook, tests, and docs land together before publish.

## Non-Goals

- Auto-merge.
- Copilot Coding Agent as the implementer.
- Mention-less “any comment starts revise”.
- Backlog / Notion adapters (platform remains opaque; no new caller profile).
- Replacing label FSM progress SoT with `.loop/state`.

## Decisions

| Topic | Choice |
| --- | --- |
| Implementer | LE Agent via `ci-loop-agent` (not Copilot). |
| Autofix intake | `labeled(autofix)` **or** `repository_dispatch` (`loop-issue-autofix`) **or** `workflow_dispatch`. |
| Autofix PR state | Caller input `pr_draft` (boolean). **Default false → open PR.** |
| Autofix double-start | Concurrency per issue number + detect **skip** when an open/draft PR already references `Fixes #<N>`. |
| Triage→autofix dispatch | When Issue has **`triage:ready` and `autofix`**, detect emits dispatch flags; trusted skill hook performs `repository_dispatch`. Category (bug/feature/…) does **not** gate dispatch. |
| PR revise trigger | Human conversation or review comment containing default **`@loop`** (caller `inputs.mention` overrides). Bots skipped. Also explicit dispatch / `workflow_dispatch`. |
| PR revise landing | Default **`git_landing_pull_request=push_head`**. Stacked PR via `open_pr`. |
| PR body | Same as other loops: skill `assets/pr-body-template.md`. Repo `PULL_REQUEST_TEMPLATE.md` used when present (`github-pr-body`); if absent, baseline / skill template only — no free-form section invention. Autofix body **must** include `Fixes #<N>`. |
| Caller profile | Autofix and revise stay on **`ci-loop-caller`**. Entity caller remains triage / observe. |

## Architecture

```text
on-loop-issue-triage (entity)
  detect_issue.sh
    → labels/comments (L1)
    → if triage:ready ∧ autofix: set dispatch_requested + payload
  trusted hook (triage skill) on_detect_dispatch.sh
    → repository_dispatch type=loop-issue-autofix

on-loop-issue-autofix (branch caller)
  detect_autofix.sh
    → skip if Fixes #N open/draft PR exists
  execute (L2, may_edit=true, write_target=fix)
  finalize (delivery=open_pr, pr_draft from inputs)

on-loop-pr-revise (branch / PR-head caller)
  detect_pr_revise.sh
    → require @mention (default @loop) on human comment
  execute (L2, may_edit=true, write_target=fix)
  finalize (push_head default, or open_pr when stacked)
```

### Four-plane mapping

| Loop | level | may_edit | write_target | delivery | Landing |
| --- | --- | --- | --- | --- | --- |
| issue-triage | L1 | false | — | none | entity (unchanged) |
| issue-autofix | L2 | true | fix | open_pr | `git_landing_integration=open_pr` |
| pr-revise | L2 | true | fix | open_pr | default `git_landing_pull_request=push_head`; stacked → `open_pr` |

Skills branch only on `may_edit` / `write_target`. They do not read `delivery` or invent finalize behavior.

## Components

### Skill: `issue-autofix`

- Replace stub detect with real intake hydration (`GITHUB_EVENT_PATH` / `ISSUE_NUMBER` / dispatch payload).
- Skip: missing issue number; open/draft PR whose body/title matches a GitHub closing keyword for `#N` (`fix(es|ed)?`, `close(s|d)?`, `resolve(s|d)?`); budget handled by platform.
- SKILL.md: implement fix on integration branch worktree; ensure PR body carries `Fixes #<N>`; load `assets/pr-body-template.md` at synthesis time.
- Ship `assets/pr-body-template.md` and `assets/pr-body-template-survey.md` like other loop skills.

### Skill: `pr-revise`

- Detect: resolve PR number; require human actor; require mention token (default `@loop`, overridable via domain env / caller input).
- Events: `issue_comment` on PRs, `pull_request_review_comment`, plus dispatch / `workflow_dispatch`.
- SKILL.md: apply feedback to the PR head (or stacked branch when landing is `open_pr`); PR body via skill templates.
- Ship PR body assets like other loop skills.

### Skill: `issue-triage` (delta)

- When labels include both `triage:ready` and `autofix`, emit:
  - `result.dispatch_requested: true`
  - `result.dispatch_event_type: "loop-issue-autofix"`
  - `result.dispatch_client_payload: { issue_number: "<N>" }`
- Own trusted hook `scripts/hooks/on_detect_dispatch.sh`: when `dispatch_requested` is true, perform live `repository_dispatch` (migrate the current stub under `issue-autofix/scripts/hooks/` into triage). Agent does not dispatch.

### Platform

1. **`pr_draft` input** on `ci-loop-caller` → `ci-loop-agent` / `loop-finalize` → `create_pr.sh` adds `--draft` when true. Default **false** (open).
2. **Post-detect hook invoke** on the entity detect path (and any path that runs triage detect): if skill hook exists and detect JSON requests dispatch, run the hook with a trusted token. Fail the job on hook failure; do not retry inside the Agent.
3. No new caller workflow family.

### Thin callers

- `on-loop-issue-autofix.yaml`: set L2 planes, pass `ISSUE_NUMBER` via opaque `detect_domain_env_json`, expose `pr_draft` (default false), concurrency per issue.
- `on-loop-pr-revise.yaml`: triggers for mentionable comments + dispatch; pass `PR_NUMBER` / `mention`; wire `git_landing_pull_request` (default `push_head`).
- `on-loop-issue-triage.yaml`: unchanged profile; gains platform hook invocation after detect.

## Error handling and re-entry

| Case | Behavior |
| --- | --- |
| Triage hard failure | Apply `triage:failed`; detect skips until human clears it. |
| Autofix / revise failure | Record via existing run-log / failure helpers; concurrency + budget limit repeats. |
| Dispatch hook failure | Non-zero exit → workflow failure (visible). Agent does not retry dispatch. |
| Autofix re-entry | Relabel / dispatch again; still skip if `Fixes #N` PR exists. |
| Revise re-entry | New `@loop` (or configured mention) comment, or explicit dispatch. |

## Security

- Skip bot / App authors for triage and revise triggers.
- Mention match is substring/token on comment body; actor must be human/User.
- Only the trusted hook may call `repository_dispatch`.
- Keep job-level `permissions`, zizmor ignore patterns consistent with other `on-loop-*` workflows.
- Do not interpolate untrusted comment text into shell; use env + `jq`.

## Testing

- Bats: `detect_autofix` (skip when Fixes PR exists; proceed when not), `detect_pr_revise` (mention / bot / missing PR), triage detect dispatch flags, live hook unit tests with `gh` mocked or dry-run mode if required for CI.
- Bats: `create_pr.sh` / finalize path honors `pr_draft`.
- Workflow lint: actionlint, ghalint `job_permissions`, zizmor policy alignment.
- Contract: `check_loop_pr_body_contract.sh` includes new skills once assets exist.

## Documentation

- Replace skeleton workflow design pages for autofix / pr-revise with full caller shapes.
- Update loop engineering status table (stub → dogfood L2 / in progress).
- Pointer from responsibility-separation and triage specs to this document for implementation scope.

## Completion criteria

1. Label or dispatch starts autofix and opens a PR with `Fixes #N` (draft selectable via input; default open).
2. Existing open/draft `Fixes #N` PR causes autofix detect skip.
3. Human `@loop` (or configured mention) on PR conversation or review comment updates the PR head (default landing).
4. Triage with `triage:ready` + `autofix` fires autofix via trusted hook dispatch.
5. PR bodies follow skill templates (and repo template when present via existing `github-pr-body` path).
6. Related Bats and GHA lint gates pass; no skip-always stubs left for these two axes.

## Out of scope reminders

- L3 auto_merge.
- Automatic autofix without the `autofix` label (dispatch without label remains a human/explicit path).
- Half-shipped detect-only PRs.
