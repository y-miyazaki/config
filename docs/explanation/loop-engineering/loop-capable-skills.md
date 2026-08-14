# Loop-Capable Skills

Maintainer map for skills that have **both** an Interactive (chat) path and an Automation (Loop Engineering caller) path. Agents MUST use this file when changing envelope, detect JSON, report shape, `may_edit`, or description triggers — those edits are **family-wide**, not one-skill local.

Loop **callers** (`on-loop-*.yaml`, `ci-loop-caller`) live in this repository. Skills are distributable. Skill **names** use domain stems (`ci-sweeper`, never `loop-ci-sweeper`); skills in the `github` package use a `github-` prefix (`github-issue-triage`, not `issue-triage`). `loop_name` matches the skill name (e.g. `github-issue-triage`); workflow files are `on-loop-<loop_name>.yaml`.

## Package placement

Forge and runtime — not “loop vs chat”:

| Package            | Install when                                 | Skills                                                                              |
| ------------------ | -------------------------------------------- | ----------------------------------------------------------------------------------- |
| `common`           | Always (forge-neutral review/docs)           | `agent-skills-review`, `instructions-review`, `markdown-validation`, `docs-creator` |
| `repo-maintenance` | Git + in-repo files; GitLab OK               | `changelog`, `ci-sweeper`, `docs-updater`, `refactor`, `tech-debt`                  |
| `github`           | GitHub Issue/PR (`gh`); no GHA YAML required | `github-issue-triage`, `github-issue-autofix`, `github-pr-revise`, `github-pr-body` |
| `github-actions`   | `.github/workflows` review/validation        | `github-actions-review`, `github-actions-validation`                                |
| `loop`             | Loop execute checker (generic)               | `loop-verifier`                                                                     |

`github-pr-body` is GitHub-forge and Interactive; it is **not** a loop entry skill. `loop-verifier` is loop-generic and **not** a domain entry skill. `agent_verifier_criteria` stays on each `on-loop-*.yaml`.

After `apm install`, callers still use `.agents/skills/<name>/` regardless of package.

## Loop entry skills (canonical list)

Update this table in the **same change** as adding or renaming a loop caller `skill_name`.

| Skill                  | Package            | Caller (this repo)                  | Interactive trigger (chat)          | Automation trigger                   |
| ---------------------- | ------------------ | ----------------------------------- | ----------------------------------- | ------------------------------------ |
| `changelog`            | `repo-maintenance` | `on-loop-changelog.yaml`            | check/review/update changelog       | detect JSON + `## Constraints`       |
| `ci-sweeper`           | `repo-maintenance` | `on-loop-ci-sweeper.yaml`           | triage/fix CI failures              | failed workflow detect JSON          |
| `docs-updater`         | `repo-maintenance` | `on-loop-docs-updater.yaml`         | sync/update docs after code changes | range/hook/detect JSON               |
| `refactor`             | `repo-maintenance` | `on-loop-refactor.yaml`             | survey/apply structural refactors   | `hints[]` detect JSON                |
| `tech-debt`            | `repo-maintenance` | `on-loop-tech-debt.yaml`            | survey/fix safe debt                | scheduled detect JSON                |
| `github-issue-triage`  | `github`           | `on-loop-github-issue-triage.yaml`  | triage this Issue (URL/number)      | Issue event detect JSON              |
| `github-issue-autofix` | `github`           | `on-loop-github-issue-autofix.yaml` | implement/fix this Issue            | autofix label / dispatch detect JSON |
| `github-pr-revise`     | `github`           | `on-loop-github-pr-revise.yaml`     | apply this PR feedback              | mention-gated comment detect JSON    |

## Description contract (skill triggering)

`SKILL.md` YAML `description` is how agents **decide to load** the skill. Loop-capable skills MUST:

1. State **what** the skill does in one clause.
2. State **Interactive** use (“when the user asks …”) with concrete verbs — not only L2/workflow jargon.
3. State **Automation** use (detect JSON / Constraints) as a second clause.
4. State the **edit gate**: Interactive default survey; explicit apply/fix language or `may_edit: true` applies.
5. **MUST NOT** imply the skill is workflow-only (`Use for L2 …` as the only “when”).

Automation-only detect details (`repository_dispatch`, `@loop` mention) belong in Input/Workflow, not as the sole description trigger.

## Cross-cutting edit checklist

When changing **any** row in the family below, apply the same class of edit to **every loop entry skill** that shares that artifact (or record an explicit exception in the PR).

| Change class                                   | Touch                                                                                                                                                                                                                     |
| ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Survey/apply report headings                   | each skill `references/common-output-format.md` (+ `-automation.md` when split)                                                                                                                                           |
| `may_edit` / `write_target` / `## Constraints` | `references/category-automation-envelope.md`                                                                                                                                                                              |
| PR body templates                              | `assets/pr-body-template.md`, `assets/pr-body-template-survey.md`                                                                                                                                                         |
| PR body link rules                             | `references/category-pr-body-links.md` + `scripts/self/apm/check_loop_pr_body_contract.sh`                                                                                                                                |
| Detect JSON envelope                           | each `scripts/detect_*.sh` + `references/category-input-schema.md`                                                                                                                                                        |
| Description triggers                           | each `SKILL.md` frontmatter (this file’s contract)                                                                                                                                                                        |
| Verifier domain rubric                         | matching `on-loop-*.yaml` `agent_verifier_criteria` — **not** `loop-verifier`                                                                                                                                             |
| New loop caller verifier wiring                | each `on-loop-*.yaml`: `skill_name` + `verifier_skill_name: loop-verifier` + domain `agent_verifier_criteria`                                                                                                             |
| Generic checker prompt                         | Caller passes `verifier_skill_name` into `loop-execute`. Execute slash-loads `/skill <SKILL.md>` (same pattern as implementer `prompt_file`) and lists the path as Input. Do not hardcode `loop-verifier` inside execute. |
| Install drift list                             | `scripts/self/apm/check_apm_skill_install_drift.sh` `LOOP_SKILLS`                                                                                                                                                         |
| Package move                                   | this table, [architecture.md](../architecture.md), [specification.md](../../reference/specification.md), consumer `apm.yml` examples                                                                                      |

Do **not** “fix only ci-sweeper” for envelope wording that all loop entry skills share.

## Interactive vs Loop (not a package split)

| Path        | How it starts                             | Detect script                           | `on-loop-*.yaml`          |
| ----------- | ----------------------------------------- | --------------------------------------- | ------------------------- |
| Interactive | User prompt                               | Optional; gather from prompt if missing | Not required              |
| Automation  | Caller prompt + detect JSON + Constraints | Caller-provided                         | Required in **this** repo |

`.apm/AGENTS.md` Skill design: Interactive MUST run without loop callers.

## Related

- [APM Package Design](../apm-package-design.md)
- [Loop Engineering Design](loop-engineering-design.md)
- [Loop PR Body Skill Contract](loop-pr-body-skill-contract.md)
- [Package forge split spec](../../superpowers/specs/2026-08-14-apm-package-forge-split-design.md)
