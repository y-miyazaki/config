# APM Package Forge Split Design

**Status:** Approved  
**Date:** 2026-08-14

## Problem

`.apm/packages/common` ships forge-neutral skills (`changelog`, `refactor`, review stems) next to GitHub-only skills (`github-issue-triage`, `github-pr-body`, GitHub MCP). The package name implies portability. A GitLab consumer who installs `common` gets `gh`-shaped Issue/PR skills they cannot run.

A second confusion is grouping by **loop vs interactive**. Loop is a caller channel, not a domain. Re-introducing `loop-*` skill or package prefixes would undo [loop-skill-consolidation-design](2026-07-21-loop-skill-consolidation-design.md).

## Goals

- Package boundaries match **what a consumer must already run** (git + files vs GitHub API vs GHA files vs loop checker).
- GitLab (or other forge) consumers can install maintenance skills without GitHub Issue/PR skills or GitHub MCP.
- Skill **names** stay domain names (`ci-sweeper`, not `loop-ci-sweeper`).
- `apm install` still flattens to `.agents/skills/<name>/` so loop callers (`skill_name`, `detect_script`) do not change paths solely because of package moves.

## Independent decisions (locked if this spec is approved)

| Topic                                     | Decision                                                                                                              | Why                                                                                                                                                                         |
| ----------------------------------------- | --------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| First axis                                | **Forge / runtime**, not loop vs interactive                                                                          | Loop is a caller. Portability fails on `gh` / GitHub MCP, not on `on-loop-*.yaml`.                                                                                          |
| `common` rename                           | **Keep `common`**. Do not rename to `core`.                                                                           | Breaking for every consumer `apm.yml`. Remainder after the split _is_ the portable set.                                                                                     |
| `loop-` package prefix on domains         | **Forbidden**                                                                                                         | Repeats the 2026-07 consolidation failure (`loop-changelog` vs `changelog`).                                                                                                |
| `github-actions` as its own package       | **Yes**                                                                                                               | Reviewing `.github/workflows` is a file/CI-config domain (like `terraform`). Issue/PR `gh` API is a forge domain. Mixing them in one `github` package blurs install intent. |
| `maintenance` vs `automation` naming      | Use **`repo-maintenance`**, **`github`**, **`github-actions`**.                                                       | `github` = forge entities (Issue/PR). `github-actions` = GHA YAML. Do not use `loop-` prefixes.                                                                             |
| GitHub MCP                                | Move from `common` `apm.yml` to **`github`**.                                                                         | Issue/PR skills need it. GHA review skills do not.                                                                                                                          |
| `github-actions-workflow.instructions.md` | Move to **`github-actions`**.                                                                                         | Instruction is GHA YAML, not Issue/PR.                                                                                                                                      |
| Immediate skill file move                 | **After this spec is approved**, one implementation plan. Not in the same change as inventing `loop-verifier` wiring. | Two independent migrations. Mixing them hides regressions.                                                                                                                  |

## Target packages

```text
.apm/packages/
  common/              # forge-neutral remainder + shared MCP (context7, fetch, lean-ctx, …)
  repo-maintenance/    # git + in-repo files; no required GitHub API
  github/              # GitHub forge: Issue/PR via gh + GitHub MCP
  github-actions/      # GitHub Actions YAML review/validation + GHA instructions
  loop/                # generic loop *agent* skills only (checker), not domain skills
  go/, shell-script/, terraform/, aws/   # unchanged stack packages
```

Loop workflows are **callers**, not a package membership test. Skills below that name an Interactive path MUST run from a chat prompt without `on-loop-*.yaml`.

`common-hooks-*` stay as they are (agent-target hooks, not forge skills). Do not invent `github-hooks-*` unless a hook is GitHub-API-only.

### `common` (remainder)

| Kind         | Names                                                                               |
| ------------ | ----------------------------------------------------------------------------------- |
| Skills       | `agent-skills-review`, `instructions-review`, `markdown-validation`, `docs-creator` |
| Instructions | `agent-skills`, `instructions`, `markdown` (not GHA)                                |
| MCP          | Non-GitHub servers currently in `common`                                            |

### `repo-maintenance`

| Skill          | Note                                                                                                                                                                                                                                              |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `changelog`    | File edit of CHANGELOG                                                                                                                                                                                                                            |
| `docs-updater` | Doc drift vs git range                                                                                                                                                                                                                            |
| `tech-debt`    | Report + closed-set doc/manifest fixes                                                                                                                                                                                                            |
| `refactor`     | Structural edits in-repo                                                                                                                                                                                                                          |
| `ci-sweeper`   | **Boundary:** apply path is logs → file edits. Bundled detect may call GitHub Actions APIs. GitLab CI consumers keep the skill and replace detect in the caller. Do **not** put the skill in `github` solely because this repo’s detect uses GHA. |

### `github` (forge: Issue / PR)

Interactive-capable. Installing this package does **not** require Loop Engineering workflows.

| Skill / other          | Chat (no `on-loop-*`)                                           | Loop caller                                            |
| ---------------------- | --------------------------------------------------------------- | ------------------------------------------------------ |
| `github-issue-triage`  | Issue URL/number → labels/comments via `gh`                     | `on-loop-github-issue-triage.yaml`                     |
| `github-issue-autofix` | Issue number + explicit fix language → implement + `Fixes #<N>` | `on-loop-github-issue-autofix.yaml`                    |
| `github-pr-revise`     | PR URL/number + the human feedback to apply                     | `on-loop-github-pr-revise.yaml` (mention-gated detect) |
| `github-pr-body`       | PR number + `gh`; no loop envelope                              | Not a loop entry skill                                 |
| GitHub MCP             | Used by chat and loops                                          | —                                                      |

Description frontmatter of `github-issue-autofix` / `github-pr-revise` **leads with L2 automation**, which makes them look workflow-only. That is marketing/trigger copy, not the contract. `.apm/AGENTS.md` Skill design: interactive path MUST run from user prompt without loop callers or detect scripts.

### `github-actions` (GHA YAML)

No GitHub Issue/PR API required. Consumer with GHA files can install this without `github`.

| Skill / other                             | Note                               |
| ----------------------------------------- | ---------------------------------- |
| `github-actions-review`                   | Judgment review of workflow YAML   |
| `github-actions-validation`               | actionlint / ghalint / zizmor      |
| `github-actions-workflow.instructions.md` | From today’s `common` instructions |

### `loop`

| Skill           | Note                                                                                                                                                             |
| --------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `loop-verifier` | Generic maker/checker: default REJECT, INITIAL/REGRESSION modes, JSON verdict contract, scope/secrets/hallucination. **Not** per-loop `agent_verifier_criteria`. |

`loop` does **not** contain `ci-sweeper`, `github-issue-triage`, or other domain skills.

## `loop-verifier` placement (detail)

| Layer                                                 | Owner                 | Location after this design                                                                                                                          |
| ----------------------------------------------------- | --------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| Generic checker behavior                              | `loop-verifier` skill | `.apm/packages/loop/.apm/skills/loop-verifier/` (`SKILL.md`, `references/common-checklist.md`, `references/common-output-format.md`)                |
| Checker skill binding                                 | Caller + execute      | `verifier_skill_name` on `on-loop-*.yaml` / `ci-loop-caller` → `loop-execute`; execute slash-loads `/skill <SKILL.md>` (does not inline skill body) |
| Domain APPROVE/REJECT appendix                        | Caller                | `on-loop-*.yaml` `agent_verifier_criteria` — **stays**                                                                                              |
| INITIAL / REGRESSION mode intros                      | Platform              | `load_default_prompts` in `loop-execute/lib/common.sh` — attempt orchestration, not checker skill content                                           |
| Path guards, retry loop, report-format machine checks | Platform              | `loop-execute` / `verifier.sh` — **stays**                                                                                                          |
| Embedded verifier fallbacks                           | Platform              | `common.sh` when checker skill files are missing (warning + legacy strings)                                                                         |

**Implemented (post package-split):** `loop-execute` resolves `verifier_skill_name`, slash-loads the checker skill, and appends caller `agent_verifier_criteria` as domain rubric. Do not put domain REJECT rules in `loop-verifier`.

`loop-verifier` is not GitHub-specific (no `gh`, no GHA). It must not live in `github`. It is not repo file maintenance. It must not live in `repo-maintenance`. Putting it in `common` would again mix “any repo” with “loop execute contract.”

## Consumer install examples

GitLab, file maintenance only:

```yaml
dependencies:
  apm:
    - github.com/y-miyazaki/config/.apm/packages/common
    - github.com/y-miyazaki/config/.apm/packages/repo-maintenance
```

GitHub Issues/PRs in chat, no loops:

```yaml
dependencies:
  apm:
    - github.com/y-miyazaki/config/.apm/packages/common
    - github.com/y-miyazaki/config/.apm/packages/github
```

GHA YAML only (no Issue/PR skills):

```yaml
dependencies:
  apm:
    - github.com/y-miyazaki/config/.apm/packages/common
    - github.com/y-miyazaki/config/.apm/packages/github-actions
```

This repository (GitHub + GHA + loops):

```yaml
dependencies:
  apm:
    - ./.apm/packages/common
    - ./.apm/packages/repo-maintenance
    - ./.apm/packages/github
    - ./.apm/packages/github-actions
    - ./.apm/packages/loop
```

## Non-goals

- Extracting `loop-budget` / `loop-constraints` from Actions into skills.
- Domain-complete commonization of `agent_verifier_criteria`.
- Renaming skill stems (`ci-sweeper` stays `ci-sweeper`).
- Moving `go` / `shell-script` / `terraform` skills.
- Splitting `common-hooks-*`.

## Risks

| Risk                                                                                     | Mitigation                                                                                                                                               |
| ---------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Bats and `check_apm_skill_install_drift.sh` hardcode `.apm/packages/common/.apm/skills/` | Update path lists in the same implementation PR; keep install dest `.agents/skills/<name>`.                                                              |
| Docs still say “all loop skills live in common”                                          | Update `architecture.md`, `specification.md`, getting-started, loop-engineering index.                                                                   |
| `ci-sweeper` detect is GHA-shaped while the package is `repo-maintenance`                | Document in skill Execution Scope: detect script is optional/caller-replaceable; interactive path must work from logs without GitHub.                    |
| Two sources of truth for verifier prompts                                                | Checker skill is canonical for generic behavior; `common.sh` keeps INITIAL/REGRESSION orchestration and embedded fallbacks when skill files are missing. |
| Consumer who still depends on `common` alone loses Issue skills                          | Changelog / breaking note: GitHub skills moved; add `github` package to `apm.yml`.                                                                       |

## Implementation order (after approval)

1. Add empty `repo-maintenance`, `github`, `loop` package manifests (`apm.yml`) matching `go` shape.
2. Git-move skills and the GHA instruction; move GitHub MCP into `github`.
3. Point this repo’s `apm.yml` at the new packages; refresh install + drift checks.
4. Docs: architecture, getting-started, specification loop-skills sentence, this-repo CLAUDE/AGENTS only where they name package paths.
5. **Done:** author `loop-verifier` SKILL.md and wire `loop-execute` via caller `verifier_skill_name` (slash-load; domain rubric stays on caller).
