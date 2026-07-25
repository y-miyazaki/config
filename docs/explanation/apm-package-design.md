# APM Package Design Principles

Design principles for authoring content under `.apm/packages/**` that ships via `apm install` into arbitrary consumer repositories.

**Out of scope here:** this repository's GitHub Actions workflows, Loop Engineering caller YAML, and platform job graphs — see [Loop Engineering](loop-engineering/index.md).

## Distribution model

- Sources under `.apm/packages/` are **distribution artifacts**; `apm install` materializes them into consumer trees (for example `.agents/`, `.claude/`, `.cursor/`).
- Packages must be usable without this repository's `docs/`, workflows, or `.loop/` layout.
- Maintainer workflows for **this** repository live in [.apm/AGENTS.md](../../.apm/AGENTS.md) and `docs/` — not inside distributable skill references.

## Layer responsibilities

| Layer        | Ships                                            | Portability                                         |
| ------------ | ------------------------------------------------ | --------------------------------------------------- |
| Skills       | `SKILL.md`, `references/`, `assets/`, `scripts/` | **Required** — generic contract + domain logic only |
| Instructions | `*.instructions.md`                              | **Required** — repository-neutral (DIST-01)         |
| Hooks        | portable scripts; JSON per target                | Scripts portable across agents                      |
| Repo `docs/` | design indexes, maintainer maps                  | Consumer overlay — OK                               |

Runtime layering (MCP / hooks / skills) is described in [Configuration Philosophy](architecture.md#configuration-philosophy).

## Skill authoring: contract vs product

Skills are **utility modules**. They carry the automation **contract** and domain behavior, not a consumer product's platform rules.

### Write in the skill (portable)

| Topic                                                        | Typical files                                                                                  |
| ------------------------------------------------------------ | ---------------------------------------------------------------------------------------------- |
| Input JSON schema (`findings[]`, `failures[]`, `hints[]`, …) | `category-input-schema.md`                                                                     |
| Edit gate (`may_edit`, `write_target`, `report_file`)        | `category-automation-envelope.md`                                                              |
| Path scope (interactive vs automation allowlist)             | `category-scope.md`                                                                            |
| Survey / apply report shapes, PR synthesis rules             | `common-output-format.md`, `common-output-format-automation.md`, `assets/pr-body-template*.md` |
| Domain classification, checklists, troubleshooting           | `category-*.md`, `common-checklist.md`                                                         |

### Do not write in the skill (product / platform)

- Canonical documentation path tables for a specific repository
- Caller workflow or action names (`on-loop-*`, `ci-loop-caller`, finalize action names)
- Platform autonomy planes (`level`, `delivery`) as branching rules — skills branch on `may_edit` and `write_target` only
- Per-repository allowlist/denylist examples in `references/` (configure callers or repo `AGENTS.md` instead)
- Any rule that only makes sense when Loop Engineering (or another host platform) is deployed

If content describes **when to update docs for loop workflows**, it belongs in a consumer maintainer doc (for example [Documentation Maintenance](loop-engineering/documentation-maintenance.md)), not in a distributable skill reference.

### Automation path vs interactive path

| Path               | Trigger                 | `may_edit` source                                  | Detect role                                                        |
| ------------------ | ----------------------- | -------------------------------------------------- | ------------------------------------------------------------------ |
| Interactive / hook | User or hook            | Natural language or structured JSON in the session | Skill or hook runs detect script                                   |
| Automation         | Caller-assembled prompt | `## Constraints` injected by caller                | Detect emits facts; caller maps to schema arrays; skill classifies |

Detect scripts emit **mechanical facts** only. Semantic triage (`findings[]` reasons, priority, deferrals) is the skill's job on the automation path.

## Repository overlay

Consumers (including this repo) may publish:

- Maintainer guides under `docs/explanation/**`
- Stack routing in caller `prompt_instructions` / `## Instructions` (A′ plane)
- Checklist appendices keyed to local paths

Skills link to generic principles (for example documentation deduplication) and point maintainers to **consumer `docs/`** for domain maps — they do not embed those maps.

## Portable reference paths

`SKILL.md` and `references/` must link only to:

- files inside the same skill directory (`references/`, `assets/`, `scripts/`)
- absolute `https://` URLs

Forbidden in distributable skills: `../` escapes, `docs/...` repository paths, or prose like `repository \`docs/...\``.

Enforced in review via `agent-skills-review` (S-07) — portability checks, not product specifications.

## Companion rules boundary

Companion rules (stem `agent-skills`, `instructions`) enforce **structure and portability** for any consumer repository.

They are **not** the place to encode:

- This repository's Loop Engineering specification
- Product-specific path tables or workflow triggers
- Rules that fail when another repository installs the package without our platform

Normative portability rules live in companion instructions; product contracts live in `docs/` and caller configuration.

## Related documents

| Topic                                | Document                                                                                           |
| ------------------------------------ | -------------------------------------------------------------------------------------------------- |
| MCP / hooks / skills runtime model   | [Architecture — Configuration Philosophy](architecture.md#configuration-philosophy)                |
| Functional specification             | [Specification — Configuration Philosophy](../reference/specification.md#configuration-philosophy) |
| Instruction neutrality & sync        | [Instructions Sync Workflow](instructions-sync-workflow.md)                                        |
| Maintainer routing (this repo)       | [.apm/AGENTS.md](../../.apm/AGENTS.md)                                                             |
| Loop platform (this consumer)        | [Loop Engineering](loop-engineering/index.md)                                                      |
| Automation PR body platform contract | [Loop PR Body Skill Contract](loop-engineering/loop-pr-body-skill-contract.md)                     |
