# AGENTS.md

Rules for authoring under `.apm/packages/**`. Package sources are **distribution artifacts** — `apm install` copies them into this repository and into consumer repositories.

Edit targets and sync: [CLAUDE.md § Edit routing](../CLAUDE.md#edit-routing-must). Design depth: [apm-package-design.md](../docs/explanation/apm-package-design.md).

---

## Distributable vs maintainer-only (MUST)

| Write in `.apm/packages/**`                                    | Write in maintainer docs instead (`CLAUDE.md`, this file, `docs/`)                                                                                              |
| -------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Portable contracts any consumer can follow                     | This repository's paths, CI, sync scripts, Loop caller/action names                                                                                             |
| In-skill relative paths (`scripts/`, `references/`, `assets/`) | `apm install` / `sync_*` as normative user steps                                                                                                                |
| Stem-based companion cross-links                               | Repo-specific `validate_*`, Bats `assert_*`, `scripts/lib/` paths in redistributable `references/`                                                              |
| Behavior that does not assume this layout                      | Fixed universal directory mandates (`test/bats/` only, `docs/report/…` required)                                                                                |
|                                                                | `may_edit` / automation envelope **for this consumer** — see [loop-pr-body-skill-contract](../docs/explanation/loop-engineering/loop-pr-body-skill-contract.md) |

If a sentence applies only in this repository, it does **not** belong in a package source.

---

## Skill design (MUST)

Normative rules for **all** skills under `.apm/packages/**`. Design depth: [apm-package-design.md § Skill authoring](../docs/explanation/apm-package-design.md#skill-authoring-contract-vs-product).

| Rule                            | Requirement                                                                                                                                                                                   |
| ------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Self-contained interactive path | **MUST** run from user prompt + in-skill `references/` without requiring sibling skills, loop callers, or detect scripts                                                                      |
| Optional automation assets      | Detect scripts and `hints[]` JSON are **optional** caller inputs — document them as hints, not prerequisites                                                                                  |
| Consumer context wins           | Repository norms (testing, lint, paths, security) live in consumer `AGENTS.md`, steering rules, and user prompt — **MUST NOT** embed repo-specific principles in package `references/`        |
| No other skill prerequisites    | **MUST NOT** treat any other skill as a required prerequisite for interactive execution; optional routing via session `## Instructions` or consumer context does not create a hard dependency |
| Portable scope only             | Path scope in skills: user allowlist/denylist, automation `## Constraints`, and portable skill limits — **MUST NOT** document ambient tool behavior (ignore files, default VCS exclusions)    |
| Portable verification           | Describe gate **procedure** (run what the repo already uses) — **MUST NOT** embed language/stack command tables in distributable `references/`                                                |

Violations are **blocking portability defects** on package PRs — same severity as DIST table rows below.

## Package placement (MUST)

Place new skills by **forge/runtime**, never by “this is a loop skill”:

| If the skill requires                        | Package                             |
| -------------------------------------------- | ----------------------------------- |
| No forge API; in-repo files                  | `repo-maintenance`                  |
| GitHub Issue/PR / `gh`                       | `github`                            |
| GitHub Actions YAML only                     | `github-actions`                    |
| Generic loop checker (not a domain)          | `loop`                              |
| Review/markdown/docs authoring with no forge | `common`                            |
| Language stack                               | `go` / `shell-script` / `terraform` |

Loop-capable skills (Interactive + Automation) are a **family**. Cross-cutting envelope, report shape, description triggers, and detect JSON changes MUST follow [Loop-Capable Skills](../docs/explanation/loop-engineering/loop-capable-skills.md) — do not patch a single loop entry skill’s shared contract in isolation.

YAML `description` on those skills MUST mention conversation use first or equally with automation; MUST NOT read as workflow-only.

---

## Redistribution (DIST) — maintainer judgment

Enforce via PR review and this file. **Not** an `agent-skills-review` or `instructions-review` ItemID — those skills run in external repos and must stay generalized.

| In package sources                   | Judgment                                                                                                                                                                                                    |
| ------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **MUST NOT** embed                   | Config-repo paths/trees, internal automation names, maintainer CLI as required steps, Loop platform names for this consumer, single canonical paths for all consumers, large eval corpora in the skill tree |
| **SHOULD** use                       | Portable checklist contracts, in-skill paths, stem cross-links, stable `https://` references                                                                                                                |
| Local-only skills in a consumer repo | Repo-specific rules live in that repo's `AGENTS.md` / `docs/` — not in redistributable package sources                                                                                                      |

Review skills (`agent-skills-review`, `instructions-review`) **MUST** encode generalized checks only.

---

## Release bar (this repository only)

| Rule           | Requirement                                                                                                                                                             |
| -------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Mock eval      | Verifies contract structure — not production behavior.                                                                                                                  |
| Behavior       | **MUST** be covered by `test/bats/`, `scripts/*/validate.sh`, and/or real executor / `waza run --baseline` in this repo.                                                |
| Ship decision  | **Mock eval green + repo CI green** before releasing skills from this repository.                                                                                       |
| Eval packaging | **SHOULD** keep a thin harness (`eval.yaml`, task YAMLs); avoid large corpora inside distributable skill trees (E-01 / E-03 — maintainer judgment, not review ItemIDs). |

---

## Validation scripts mirror (MUST)

Edit repo `scripts/<domain>/` only — do not hand-edit skill copies. Transforms: `sync_validate_mirror.sh`.

| Domain            | Mirrored files                             |
| ----------------- | ------------------------------------------ |
| `shell-script`    | `validate.sh`, `fix_function_doc_order.sh` |
| `go`, `terraform` | `validate.sh`                              |

Path layout differs only in library import lines and `WORKSPACE_ROOT` depth for `shell-script` `validate.sh` — see `sync_validate_mirror.sh` and [CLAUDE.md § Edit routing](../CLAUDE.md#edit-routing-must).

---

## Pointers (not rules)

| Topic                                 | Document                                                                           |
| ------------------------------------- | ---------------------------------------------------------------------------------- |
| Skill self-containment (all skills)   | This file — [§ Skill design (MUST)](#skill-design-must)                            |
| Skill vs product, automation envelope | [apm-package-design.md](../docs/explanation/apm-package-design.md)                 |
| Instruction sync                      | [instructions-sync-workflow.md](../docs/explanation/instructions-sync-workflow.md) |
| Loop platform (this consumer)         | [Loop Engineering](../docs/explanation/loop-engineering/index.md)                  |
| SKILL authoring stems                 | companion `agent-skills` rules; `agent-skills-review` skill                        |
