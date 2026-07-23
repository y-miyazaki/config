# AGENTS.md

Maintainer routing for `.apm/packages/**` work in this repository.

---

## Scope

- Applies when creating or updating files under `.apm/packages/**`.
- Package sources are **distribution artifacts**: `apm install` materializes them into this repository and into consumer repositories.

## Canonical references

| Topic                                           | Where                                                                                                                                                            |
| ----------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Edit targets, sync, post-change workflow        | [CLAUDE.md § Edit Targets](../CLAUDE.md#edit-targets)                                                                                                            |
| Configuration philosophy (MCP / hooks / skills) | [architecture.md](../docs/explanation/architecture.md#configuration-philosophy), [specification.md](../docs/reference/specification.md#configuration-philosophy) |
| Repository-neutral distributable content        | companion rules (stem `instructions`, `agent-skills`) — DIST-01 / DIST-02                                                                                        |
| Instruction file structure and category sync    | [instructions-sync-workflow.md](../docs/explanation/instructions-sync-workflow.md)                                                                               |
| SKILL authoring and eval packaging              | companion rules (stem `agent-skills`) and `agent-skills-review` skill                                                                                            |
| Test pairing                                    | companion domain rules (stem `shell-script`, `go`, `bats`) — TEST-00                                                                                             |

## Maintainer-only (not in distributable rules)

### Repository CI and eval release bar

- Mock eval passing verifies **contract structure**, not production behavior.
- Full behavior verification lives in this repository: `test/bats/`, `scripts/*/validate.sh`, `waza run --baseline` / real executor.
- Treat **mock eval green + repo CI green** as the release bar for skills shipped from this repository.

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

General repository security: [CLAUDE.md § Security Guidelines](../CLAUDE.md#security-guidelines) and [AGENTS.md](../AGENTS.md). Package-source specifics are in companion rules (stem `agent-skills`, `instructions`) — DIST-01 and Security chapters.
