# AGENTS.md

Maintainer routing for `.apm/packages/**` work in this repository.

---

## Scope

- Applies when creating or updating files under `.apm/packages/**`.
- Package sources are **distribution artifacts**: `apm install` materializes them into this repository and into consumer repositories.

## Canonical references

| Topic                                                                                   | Where                                                                                                                                                                                                                       |
| --------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Package design principles** (skill vs product)                                        | [apm-package-design.md](../docs/explanation/apm-package-design.md)                                                                                                                                                          |
| **Distributable vs maintainer-only** (no domain-specific content in `.apm/packages/**`) | [.apm/AGENTS.md § Distributable content policy](#distributable-content-policy-must), [apm-package-design.md § Distributable vs maintainer-only](../docs/explanation/apm-package-design.md#distributable-vs-maintainer-only) |
| Edit targets, sync, post-change workflow                                                | [CLAUDE.md § Edit Targets](../CLAUDE.md#edit-targets)                                                                                                                                                                       |
| Configuration philosophy (MCP / hooks / skills)                                         | [architecture.md](../docs/explanation/architecture.md#configuration-philosophy), [specification.md](../docs/reference/specification.md#configuration-philosophy)                                                            |
| Repository-neutral distributable content                                                | companion rules (stem `instructions`, `agent-skills`) — DIST-01 / DIST-02                                                                                                                                                   |
| Instruction file structure and category sync                                            | [instructions-sync-workflow.md](../docs/explanation/instructions-sync-workflow.md)                                                                                                                                          |
| SKILL authoring and eval packaging                                                      | companion rules (stem `agent-skills`) and `agent-skills-review` skill — **portability only for distributable targets**; see [apm-package-design.md](../docs/explanation/apm-package-design.md)                              |
| Automation edit gate (`may_edit` in Constraints)                                        | per-skill `category-automation-envelope.md`; skills branch on `may_edit` and `write_target` only — see [apm-package-design.md](../docs/explanation/apm-package-design.md#skill-authoring-contract-vs-product)               |
| Loop platform (this consumer)                                                           | [Loop Engineering](../docs/explanation/loop-engineering/index.md), [loop-pr-body-skill-contract.md](../docs/explanation/loop-engineering/loop-pr-body-skill-contract.md)                                                    |
| Test pairing                                                                            | companion domain rules (stem `shell-script`, `go`, `bats`) — TEST-00                                                                                                                                                        |

## Distributable content policy (MUST)

Everything under `.apm/packages/**` is a **distribution artifact**. After package sync it lands in consumer trees (`<agent-root>/skills/`, `.cursor/rules/`, hooks, agents, …) in repositories that may not use this layout, CI, or Loop platform.

**Write in `.apm/packages/**` only:**

- Generalized rules and contracts any consumer can follow (companion instructions DIST-01, agent-skills portability, portable skill schemas, domain behavior that does not assume this repository).
- In-skill paths (`scripts/`, `references/`, `assets/` inside the same skill directory).
- Stem-based companion cross-links — not package-tooling commands as normative user steps.

**Do not write in `.apm/packages/**` (put in maintainer docs instead):**

| Forbidden in distributable package sources                                                                                                  | Write here instead                                                                            |
| ------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| This repository's paths, scripts, or sync workflows (`scripts/self/`, `sync_*`, `apm_modules/`, default `docs/report/…` as required layout) | [CLAUDE.md § Edit Targets](../CLAUDE.md#edit-targets), root [AGENTS.md](../AGENTS.md)         |
| Package-manager commands as portability rules (`apm install`, `.apm/packages/**` in consumer-facing instructions)                           | `.apm/AGENTS.md`, [apm-package-design.md](../docs/explanation/apm-package-design.md)          |
| Loop caller / workflow / action names for this consumer                                                                                     | [Loop Engineering](../docs/explanation/loop-engineering/index.md)                             |
| Repo-specific checklist APIs (`assert_*_ok_json`, internal `scripts/lib/`, hook names) in skill `references/`                               | Consumer `AGENTS.md` / `docs/` for local-only skills; DIST-01 Scope for reuse-intended skills |
| Fixed test directory mandates (`test/bats/` only)                                                                                           | companion bats rules — repository-established layout                                          |
| Review rules that reject consumer-local domain skills as Fail                                                                               | `agent-skills-review` defers portability for local-only targets; see below                    |

**Review skills** (`agent-skills-review`, `instructions-review`) ship inside packages and may run in external repositories. They must encode **generalized** checks only; defer or scope portability ItemIDs when the target is not reuse-intended.

Full design: [apm-package-design.md § Distributable vs maintainer-only](../docs/explanation/apm-package-design.md#distributable-vs-maintainer-only).

## Maintainer-only (not in distributable rules)

### Repository CI and eval release bar

- Mock eval passing verifies **contract structure**, not production behavior.
- Full behavior verification lives in this repository: `test/bats/`, `scripts/*/validate.sh`, `waza run --baseline` / real executor.
- Treat **mock eval green + repo CI green** as the release bar for skills shipped from this repository.

### `agent-skills-review` vs consumer-local skills

- **DIST-01 / S-07** apply to skills **authored under `.apm/packages/**`** (distribution artifacts consumed via `apm install`). Checklist wording in distributable `references/` is covered by DIST-01 Scope — there is no separate S-08 ItemID.
- When a consumer repository runs `agent-skills-review` against **local domain skills** (`<agent-root>/skills/` with no APM package source), defer S-07 — portability is consumer maintainer policy in `docs/` or `AGENTS.md`.
- Repo-specific checklist prose (Bats `assert_*`, `scripts/lib/`, hook names) for consumer-only skills belongs in that repository's `AGENTS.md` or `docs/`, not in distributable skill `references/`.

### Validation Scripts Mirror (`scripts/` ↔ skill)

Path-layout transforms applied by `sync_validate_mirror.sh` (do not hand-edit both sides or apply manually). Sync workflow: [CLAUDE.md § Edit Targets](../CLAUDE.md#edit-targets).

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

General repository security: [AGENTS.md § Safety](../AGENTS.md#safety) and [AGENTS.md](../AGENTS.md). Package-source specifics are in companion rules (stem `agent-skills`, `instructions`) — DIST-01 and Security chapters.
