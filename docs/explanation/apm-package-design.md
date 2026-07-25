# APM Package Design Principles

Design principles for authoring content under `.apm/packages/**` that ships via `apm install` into arbitrary consumer repositories.

**Out of scope here:** this repository's GitHub Actions workflows, Loop Engineering caller YAML, and platform job graphs — see [Loop Engineering](loop-engineering/index.md).

## Distribution model

- Sources under `.apm/packages/` are **distribution artifacts**; `apm install` materializes them into consumer trees (for example `.agents/`, `.claude/`, `.cursor/`).
- Packages must be usable without this repository's `docs/`, workflows, or `.loop/` layout.
- Maintainer workflows for **this** repository live in [.apm/AGENTS.md](https://github.com/y-miyazaki/config/blob/main/.apm/AGENTS.md) and `docs/` — not inside distributable skill references.

## Distributable vs maintainer-only

Package sources under `.apm/packages/**` are **distribution artifacts**. Treat every edit there as content that may appear in an unrelated consumer repository after package sync — not as internal notes for this config repo.

### Allowed in `.apm/packages/**`

| Layer                              | Content                                                                                                                                                                              |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Instructions (`*.instructions.md`) | Generalized authoring rules; stem-based companion links; runtime paths under `.cursor/rules/`, `.claude/rules/`, `.kiro/steering/` — not package-tooling commands as normative steps |
| Skills (`SKILL.md`, `references/`) | Portable contracts (schemas, exit semantics, `may_edit` / `write_target`), domain logic, in-skill `scripts/`                                                                         |
| Hooks / agents                     | Portable scripts and prompts; no consumer-tree path tables                                                                                                                           |

Use **reuse-intended** wording (skills meant for redistribution) rather than naming this repository's package layout or install commands in consumer-facing prose.

### Forbidden in `.apm/packages/**`

Do not embed **this repository's** or **single-consumer** specifics in instructions, skill `references/`, or review checklists:

- Maintainer sync paths (`scripts/self/`, `sync_*`, mirror workflows, `apm_modules/`)
- Required directory layouts unique to this repo (`docs/report/tech-debt/` as mandatory default in checklist prose)
- Loop platform caller names, this repo's workflow filenames, or CI validation command tables that duplicate what callers/CI already run
- Internal test helper names, shared lib paths, or hook identifiers in checklist ItemIDs
- Universal rejection rules that Fail consumer-local skills under `<agent-root>/skills/` when they are not redistribution targets
- Hard-coded links to this repository's `docs/` or GitHub URLs for normative policy (summarize in skill `references/` or point to companion instructions)

### Maintainer-only locations

| Topic                                       | Where                                                                                                                                     |
| ------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| Edit targets, sync, post-change workflow    | [CLAUDE.md § Edit Targets](https://github.com/y-miyazaki/config/blob/main/CLAUDE.md#edit-targets), [.apm/AGENTS.md](https://github.com/y-miyazaki/config/blob/main/.apm/AGENTS.md) |
| Loop Engineering, documentation path maps   | `docs/explanation/loop-engineering/**`, consumer `docs/` overlays                                                                         |
| Repo-specific denylist / path policy        | Root `AGENTS.md`, `docs/`, caller `## Constraints` — not skill `references/` defaults                                                     |
| Local-only domain skills in a consumer repo | That repository's `AGENTS.md` or `docs/`                                                                                                  |

When reviewing package PRs, treat any domain-specific path or maintainer workflow inside `.apm/packages/**` as a **blocking portability defect** unless it is clearly generalized (pattern + override env var, optional caller field, etc.).

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

Enforced in review via `agent-skills-review` (S-07) and companion instructions (DIST-01) — portability for **distributable** targets, not product specifications.

## Review skill scope (DIST-01, S-07)

Review skills ship inside packages and may run in arbitrary consumer repositories. **Portability is not a universal rejection rule for every skill tree.**

| Review target                                                                                | DIST-01 / S-07                                                                    |
| -------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| Package skill sources intended for reuse (this repo's `.apm/packages/**` tree or equivalent) | **Apply** — distribution artifact                                                 |
| Local-only skill under `<agent-root>/skills/` not redistributed                              | **Defer** S-07; document repo-specific wording in consumer `AGENTS.md` or `docs/` |
| Installed mirror when reviewing overlay-only skills                                          | **Defer** unless the change also touches reuse-intended package sources           |

Structural and quality checks (S-01, Q-_, P-_) apply to any SKILL.md target. Checklist neutrality in distributable `references/` is **DIST-01 Scope** in companion agent-skills instructions when authoring reuse-intended skills.

## Companion rules boundary

Companion rules (stem `agent-skills`, `instructions`) enforce **structure and portability** for reuse-intended package content.

- This repository's Loop Engineering specification
- Product-specific path tables or workflow triggers
- Rules that fail when another repository installs the package without our platform

Normative portability rules live in companion instructions; product contracts live in `docs/` and caller configuration.

## Related documents

| Topic                                | Document                                                                                           |
| ------------------------------------ | -------------------------------------------------------------------------------------------------- |
| **Distributable vs maintainer-only** | This document — [§ Distributable vs maintainer-only](#distributable-vs-maintainer-only)            |
| MCP / hooks / skills runtime model   | [Architecture — Configuration Philosophy](architecture.md#configuration-philosophy)                |
| Functional specification             | [Specification — Configuration Philosophy](../reference/specification.md#configuration-philosophy) |
| Instruction neutrality & sync        | [Instructions Sync Workflow](instructions-sync-workflow.md)                                        |
| Maintainer routing (this repo)       | [.apm/AGENTS.md](https://github.com/y-miyazaki/config/blob/main/.apm/AGENTS.md)                    |
| Loop platform (this consumer)        | [Loop Engineering](loop-engineering/index.md)                                                      |
| Automation PR body platform contract | [Loop PR Body Skill Contract](loop-engineering/loop-pr-body-skill-contract.md)                     |
