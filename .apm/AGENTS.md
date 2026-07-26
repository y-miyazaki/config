# AGENTS.md

Maintainer routing for `.apm/packages/**` work in this repository.

---

## Scope

- Applies when creating or updating files under `.apm/packages/**`.
- Package sources are **distribution artifacts**: `apm install` materializes them into this repository and into consumer repositories.

## Project-specific vs distributable (MUST)

**This repository only** — write APM-related maintainer rules, workflows, Loop platform behavior, sync/edit targets, and any wording that assumes this layout or CI here:

- [.apm/AGENTS.md](AGENTS.md) — package authoring routing and maintainer-only policy
- [CLAUDE.md § Repository Rules](../CLAUDE.md#repository-rules) — edit targets and repo conventions agents load with every task
- `docs/` — deeper design (Loop Engineering, package design, and similar)

**Distributable** — `.apm/packages/**` ships to **other repositories** via `apm install`. Every sentence in package sources (`*.instructions.md`, `SKILL.md`, `references/`, hooks, MCP config) MUST be **generalized**: portable paths, consumer-neutral contracts, and behavior any adopter can follow without this repository's scripts, Loop callers, or directory layout. If a rule applies only here, do not put it in a package — put it in `.apm/AGENTS.md` or `CLAUDE.md` instead.

## Canonical references

| Topic                                                                                   | Where                                                                                                                                                                                                                       |
| --------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Package design principles** (skill vs product)                                        | [apm-package-design.md](../docs/explanation/apm-package-design.md)                                                                                                                                                          |
| **Distributable vs maintainer-only** (no domain-specific content in `.apm/packages/**`) | [.apm/AGENTS.md § Distributable content policy](#distributable-content-policy-must), [apm-package-design.md § Distributable vs maintainer-only](../docs/explanation/apm-package-design.md#distributable-vs-maintainer-only) |
| Edit targets (source of truth)                                                          | [CLAUDE.md § Edit Targets](../CLAUDE.md#edit-targets)                                                                                                                                                                       |
| Configuration philosophy (MCP / hooks / skills)                                         | [architecture.md](../docs/explanation/architecture.md#configuration-philosophy), [specification.md](../docs/reference/specification.md#configuration-philosophy)                                                            |
| Repository-neutral distributable content                                                | [.apm/AGENTS.md § Redistribution policy (DIST)](#redistribution-policy-dist--this-repository-only)                                                                                                                          |
| Instruction file structure and category sync                                            | [instructions-sync-workflow.md](../docs/explanation/instructions-sync-workflow.md)                                                                                                                                          |
| SKILL authoring and eval packaging                                                      | companion rules (stem `agent-skills`) and `agent-skills-review` skill; eval release bar below                                                                                                                               |
| Automation edit gate (`may_edit` in Constraints)                                        | per-skill `category-automation-envelope.md`; skills branch on `may_edit` and `write_target` only — see [apm-package-design.md](../docs/explanation/apm-package-design.md#skill-authoring-contract-vs-product)               |
| Loop platform (this consumer)                                                           | [Loop Engineering](../docs/explanation/loop-engineering/index.md), [loop-pr-body-skill-contract.md](../docs/explanation/loop-engineering/loop-pr-body-skill-contract.md)                                                    |
| Test pairing                                                                            | companion domain rules (stem `shell-script`, `go`, `bats`) — TEST-00                                                                                                                                                        |

## Distributable content policy (MUST)

Everything under `.apm/packages/**` is a **distribution artifact**. After package sync it lands in consumer trees (`<agent-root>/skills/`, `.cursor/rules/`, hooks, agents, …) in repositories that may not use this layout, CI, or Loop platform. **Non-portable or this-repo-only wording in package sources breaks other consumers** — keep those rules in [.apm/AGENTS.md](AGENTS.md) or [CLAUDE.md](../CLAUDE.md) per [§ Project-specific vs distributable](#project-specific-vs-distributable-must).

**Write in `.apm/packages/**` only:**

- Generalized rules and contracts any consumer can follow (portable skill schemas, domain behavior that does not assume this repository).
- In-skill paths (`scripts/`, `references/`, `assets/` inside the same skill directory).
- Stem-based companion cross-links — not package-tooling commands as normative user steps.

**Do not write in `.apm/packages/**` (put in maintainer docs instead):**

- This repository's paths, scripts, or sync workflows — for example `scripts/self/`, `sync_*`, `apm_modules/`, default `docs/report/…` as a required layout → [CLAUDE.md § Edit Targets](../CLAUDE.md#edit-targets), this file
- Package-manager commands as portability rules — for example `apm install`, `.apm/packages/**` in consumer-facing normative steps → this file, [apm-package-design.md](../docs/explanation/apm-package-design.md)
- Loop caller, workflow, or action names for this consumer → [Loop Engineering](../docs/explanation/loop-engineering/index.md)
- Repo-specific checklist APIs in skill `references/` — for example private `validate_*` helpers, test-suite `assert_*` APIs, internal `scripts/lib/` paths, hook names → consumer `AGENTS.md` / `docs/` for local-only skills; [§ Redistribution policy (DIST)](#redistribution-policy-dist--this-repository-only) for package sources
- Fixed test-directory mandates as universal rules — for example `test/bats/` only → companion bats rules document repository-established layout
- Review rules that Fail consumer-local domain skills for portability → `agent-skills-review` uses generalized checks only; consumer policy lives in that repository's `AGENTS.md` / `docs/`

**Review skills** (`agent-skills-review`, `instructions-review`) ship inside packages and may run in external repositories. They must encode **generalized** checks only — not this repository's redistribution maintainer policy (DIST).

Full design: [apm-package-design.md § Distributable vs maintainer-only](../docs/explanation/apm-package-design.md#distributable-vs-maintainer-only).

### Redistribution policy (DIST) — this repository only

Applies when authoring under `.apm/packages/**` for redistribution via `apm install`. **Not** an `agent-skills-review` or `instructions-review` checklist ItemID — maintainers enforce via this section and PR judgment.

**Intent**

- Package sources are distribution artifacts; consumers may not share this repository's layout, CI, hooks, or Loop platform.
- Distributable skills and instructions stay **generalized**; do not use package text to restrict how other projects structure local-only skills or paths.

**Do not embed in `.apm/packages/**` (skills, instructions, `references/`)**

- This config repository's paths, directory trees, or sync workflows (`scripts/self/`, `sync_*`, `apm_modules/`, `.apm/packages/**` as a consumer norm)
- Internal automation or CI names tied to this repository only
- Maintainer tooling commands as required user steps (`apm install`, package sync scripts)
- Loop platform caller, workflow, or action names for this consumer
- Authoring-repository symbols in redistributable `references/` — private `validate_*` helpers, Bats `assert_*` APIs, internal `scripts/lib/` paths, hook names
- Single canonical file paths presented as the only valid layout ("always use `path/to/foo` in every consumer")
- Large regression corpora or datasets in skill packages (eval archives belong in the authoring repository, not the distributable skill tree)

**Prefer in distributable package sources**

- Portable contracts in checklist/category items — schema fields, dependency declarations, exit semantics
- In-skill relative paths (`scripts/`, `references/`, `assets/`)
- Stem-based companion cross-links and stable `https://` references
- Product- or deployment-specific paths only inside Execution Scope when the skill's purpose is explicitly single-target

**Local-only skills** (under `<agent-root>/skills/` in a consumer repo, not redistributed)

- Repo-specific checklist wording, test helpers, and internal paths belong in that repository's `AGENTS.md` or `docs/` — not in package sources intended for reuse.

## Maintainer-only (not in distributable rules)

### Repository CI and eval release bar

- Mock eval passing verifies **contract structure**, not production behavior.
- Full behavior verification lives in this repository: `test/bats/`, `scripts/*/validate.sh`, `waza run --baseline` / real executor.
- Treat **mock eval green + repo CI green** as the release bar for skills shipped from this repository.
- **E-01 / E-03 (SHOULD, maintainer judgment):** prefer a thin eval harness (`eval.yaml`, task YAMLs) and avoid large eval corpora in distributable skill trees — testing tooling varies (`waza`, skill-creator, etc.); not enforced as review ItemIDs.

### Validation Scripts Mirror (`scripts/` ↔ skill)

Path-layout transforms applied by `sync_validate_mirror.sh` (edit repo `scripts/<domain>/` only — do not hand-edit skill copies). See [CLAUDE.md § Edit Targets](../CLAUDE.md#edit-targets).

| Domain         | Mirrored files (repo `scripts/<domain>/` → skill `scripts/`) |
| -------------- | ------------------------------------------------------------ |
| `shell-script` | `validate.sh`, `fix_function_doc_order.sh`                   |
| `go`           | `validate.sh`                                                |
| `terraform`    | `validate.sh`                                                |

**Path layout (applied only by `sync_validate_mirror.sh`):**

| Setting          | Skill copy (`…/skills/*/scripts/`)      | `scripts/<domain>/` copy               |
| ---------------- | --------------------------------------- | -------------------------------------- |
| Library import   | `source "${SCRIPT_DIR}/lib/all.sh"`     | `source "${SCRIPT_DIR}/../lib/all.sh"` |
| `shellcheck`     | `# shellcheck source=./lib/all.sh`      | `# shellcheck source=../lib/all.sh`    |
| `WORKSPACE_ROOT` | `$(cd "${SCRIPT_DIR}/../../.." && pwd)` | `$(cd "${SCRIPT_DIR}/../.." && pwd)`   |

`WORKSPACE_ROOT` differs only for `shell-script` `validate.sh` (skill tree is deeper). `go` and `terraform` differ only in the library import lines. `fix_function_doc_order.sh` differs only in library import lines.

## Security Guidelines

General repository security: [AGENTS.md § Safety](../AGENTS.md#safety) and [AGENTS.md](../AGENTS.md). Package-source specifics are in companion rules (stem `agent-skills`, `instructions`) — Security chapters.
