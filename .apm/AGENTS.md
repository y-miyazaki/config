# AGENTS.md

Behavioral rules for APM package authoring under `.apm/packages/`. Self-contained for package work  - includes validation-mirror and skill-lib sync obligations that also appear in [CLAUDE.md](../CLAUDE.md) for repository-wide `scripts/` edits.

---

## Scope

- Applies when creating or updating files under `.apm/packages/**`.
- Package sources are **distribution artifacts**: `apm install` materializes them into this repository (`.agents/`, `.claude/`, `.codex/`, `.cursor/`, `.kiro/`, `.vscode/`, `apm_modules/`) and into consumer repositories.
- Direct edits to generated directories are overwritten on the next `apm install`.
- Consumer-specific conventions belong in the consumer repository, not in package sources.
- For `scripts/**` or `.github/actions/**/lib/**` work (mirrors, Bats pairing, repo-only scripts), follow [CLAUDE.md section Scripts and Skill Mirrors](../CLAUDE.md#scripts-and-skill-mirrors).

## Configuration Philosophy

APM packages distribute **configuration**, not a complete toolchain. Tool execution rules differ by layer  - do not apply MCP rules to hooks or skills.

| Layer  | Purpose                           | Tool resolution                               | When tool absent                              |
| ------ | --------------------------------- | --------------------------------------------- | --------------------------------------------- |
| MCP    | Agent capabilities at runtime     | `npx` / `uvx` with pinned versions (required) | Server fails to start; fix runtime or network |
| Hooks  | Optional in-session lint/format   | `PATH` lookup for native binaries             | Exit 0  - do not block agent sessions          |
| Skills | On-demand validation when invoked | `PATH` lookup via `scripts/validate.sh`       | Report `SKIP` in structured output            |

**Minimal consumer prerequisites**: APM CLI, Node.js (`npx`) and/or Python with [uv](https://docs.astral.sh/uv/) (`uvx`), plus network for MCP runtime fetch. Per-linter global installs are not required.

**Recommended dev setup**: Install linters on `PATH` (for example via [mise](https://mise.jdx.dev/)) so hooks and skills run fully. This is an optimization, not an APM package requirement.

See [Config Repository Architecture](../docs/explanation/architecture.md#configuration-philosophy) and [Config Repository Functional Specification](../docs/reference/specification.md#configuration-philosophy).

### MCP  - Runtime Resolution

- Declare `command: npx` or `command: uvx` with pinned versions in `args`. Use `-y` with `npx` for non-interactive fetch.
- Do not document per-MCP global installs as required consumer steps.
- **Exceptions**: MCP servers with no npm/PyPI distribution (for example `codebase-memory-mcp`) use a bare binary command and are **optional**  - document that consumers must install the binary separately or omit the server.

### Hooks  - Optional Enforcement

- Hooks are **not** a quality gate. They provide best-effort lint/format when tools happen to be on `PATH`.
- Use `command -v tool || exit 0` before running native binaries (`actionlint`, `golangci-lint`, `shellcheck`, and similar). Most hook tools are **not** available via `npx`/`uvx`.
- Do not block agent sessions when linters are absent.
- Prefer emitting a skip notice to stderr when skipping (for example `actionlint not installed  - hook skipped`) so users know enforcement did not run.

### Skills  - Explicit Validation

- Skills run only when an agent invokes them. Route checks through `scripts/validate.sh`; do not assume tools are installed.
- When a tool is missing, record `SKIP` (with reason) in structured output  - not silent success.
- Use `npx`/`uvx` inside skill scripts only when the tool is published to npm or PyPI. Most domain linters remain native binaries on `PATH`.

## Distributable Content

### Repository-Neutral Rules

Package instructions, skills, and references must work in any consumer project. Do **not** embed:

- Paths or names from this config repository (for example `.github/actions/loop-*`, internal script filenames).
- References to a single file as the canonical example ("use `path/to/specific.sh` as the reference").
- Test helpers, fixtures, or support APIs that exist only in this repository (`bats_source_apm_skill`, project-local `common.bash` contracts, and similar).
- Domain jargon tied to one consumer's layout unless expressed as a generic pattern (for example `lib/*.sh`, `scripts/lib/*.sh`).

Prefer:

- Generic path patterns and naming rules.
- "Match sibling files in the same directory" for comment style, separators, and layout.
- Cross-links between package instruction files (for example stem `shell-script` ↔ stem `bats`) instead of duplicating rules. In **agent-facing** text, prefer stem-based wording such as companion Bats rules (stem `bats`) because APM renames files per target (Cursor: `.cursor/rules/bats.mdc`, Claude: `.claude/rules/bats.md`; package source stays `bats.instructions.md`).
- External, stable references when citing industry practice (for example [Google eng-practices](https://google.github.io/eng-practices/review/developer/small-cls.html#test_code), [bats-core docs](https://bats-core.readthedocs.io/en/stable/writing-tests.html)).

### Pair Production Code With Tests

| Package        | Rule                                                                                                                 |
| -------------- | -------------------------------------------------------------------------------------------------------------------- |
| `shell-script` | Add or update Bats suites in the same change as script changes (TEST-00); follow companion Bats rules (stem `bats`). |
| `go`           | Add or update `*_test.go` in the same change as behavior changes (TEST-00).                                          |

Loop-only or single-consumer packages (`loop-*`) may document consumer-specific paths in their own skill scope, but **shared domain packages** (`common`, `go`, `shell-script`, `terraform`) must stay neutral.

## Edit Targets

| Edit here (source of truth)                                        | Do not edit (generated by `apm install`)                                                             |
| ------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------- |
| `.apm/packages/<pkg>/`                                            | `.agents/`, `.claude/`, `.codex/`, `.cursor/`, `.kiro/`, `.vscode/`, `apm_modules/`                  |
| `scripts/lib/` (then sync to skills)                               | `.apm/packages/*/.apm/skills/*/scripts/lib/` directly                                                |
| `scripts/{shell-script,go,terraform}/validate.sh` and `scripts/shell-script/fix_function_doc_order.sh` | See [Validation Scripts Mirror](#validation-scripts-mirror-scripts--skill)  - sync via `sync_validate_mirror.sh`; do not hand-edit both sides |

To modify agent instructions or skills:

1. Edit the source under `.apm/packages/<pkg>/` (for example `.apm/packages/common/.apm/skills/refactor/SKILL.md` for a skill, or `.apm/packages/shell-script/.apm/instructions/` for instructions).
2. Follow [After package changes](#after-package-changes) below.

### After package changes

1. Run `scripts/apm/sync_guidelines_from_categories.pl` when `category-*.md` or sync-mapped instructions change.
2. Run `apm install --update`.
3. Verify with `apm audit --ci`.

## Repository Execution Layer (reference)

`scripts/**` and `.github/actions/**/lib/**` are repository-only  - not shipped to consumers.

**Canonical sync obligations:** [CLAUDE.md section Scripts and Skill Mirrors](../CLAUDE.md#scripts-and-skill-mirrors) (do not duplicate the workflow table here).

Path-layout detail for validation mirrors (skill vs repo import paths): [Validation Scripts Mirror](#validation-scripts-mirror-scripts--skill) below  - applied only by `sync_validate_mirror.sh`.

## Instructions Maintenance

### Sync-Managed Files

`scripts/apm/sync_guidelines_from_categories.pl` regenerates `## Guidelines` (and `common-checklist.md`) from `category-*.md` for mapped review skills. See [Instructions Sync Workflow](../docs/explanation/instructions-sync-workflow.md).

- Edit review criteria in `.apm/packages/<pkg>/.apm/skills/<skill>-review/references/category-*.md`.
- Re-run the sync script; do not hand-edit generated guideline bullets unless you accept they will be overwritten.
- `### Anti-Patterns` and other guideline subsections must live in a `category-*.md` file or they disappear on sync.

### Manually Maintained Instruction Files

Not regenerated by the sync script  - edit directly and run re-evaluation:

| File                                                                                        | Notes                                                    |
| ------------------------------------------------------------------------------------------- | -------------------------------------------------------- |
| `*.instructions.md` → `## Standards`, `## Testing and Validation`, `## Security Guidelines` | Operational and structural content for sync-mapped files |
| `bats.instructions.md`                                                                      | Bats conventions; keep repository-neutral                |
| `markdown.instructions.md`                                                                  | No category sync mapping                                 |

Every `*.instructions.md` file uses five H2 chapters in order: Scope → Standards → Guidelines → Testing and Validation → Security Guidelines.

### Re-Evaluation

After any `*.instructions.md` change:

```bash
for f in .apm/packages/*/.apm/instructions/*.instructions.md; do
  awk 'BEGIN{s=0;st=0;g=0;t=0;sec=0} /^## Scope$/{s=NR} /^## Standards$/{st=NR} /^## Guidelines$/{g=NR} /^## Testing and Validation$/{t=NR} /^## Security Guidelines$/{sec=NR} END{print FILENAME, (s<st && st<g && g<t && t<sec)?"OK":"NG"}' "$f"
done
```

## Skills and Shared Libraries

- Skill authoring standards: `agent-skills` instruction and `agent-skills-review` skill.
- Shared shell libraries: edit `scripts/lib/`, then `bash scripts/ai/sync_skill_lib.sh`, then `apm install --update` (see [CLAUDE.md section Scripts and Skill Mirrors](../CLAUDE.md#scripts-and-skill-mirrors)).
- Do not create skill-specific minimal copies of `scripts/lib/` (for example a `json.sh`-only loader).

### SKILL.md documentation level (sibling consistency)

**Priority:** Keep **the same documentation level across sibling skills** in a package and across **shared domain packages** (`common`, `go`, `shell-script`, `terraform`). Validation/review pairs in the same domain (for example `go-validation` ↔ `go-review`) should share Reference Files Guide load-contract phrasing and `### Error Handling` table format. Misaligned depth, section layout, or reference-load wording causes execution drift between skills  - that is a higher risk than token count.

**Token budget:** External tooling may warn when `SKILL.md` exceeds ~500 tokens. Treat that as **advisory only**. Do **not** compress one skill in isolation to satisfy a token gate if sibling skills remain at full depth. Token reduction, when desired, is a **package-wide** pass after structure is aligned.

**Canonical patterns** (match `ci-sweeper`, `changelog`, `docs-updater`, `report-tech-debt` unless the whole family is revised together):

| Element | Convention |
| ------- | ---------- |
| `## Workflow` | **S-01 MUST**  - one of five required H2 sections; numbered steps or explicit `###` path branches (Q-03 SHOULD) |
| Utility skills | Lead with `**UTILITY SKILL**  - …` when the skill patches/syncs rather than authors content |
| Loop skills | `## Operating levels` H2 pointing at `category-*-input-schema.md#operating-levels` |
| Dual-path skills | Separate `### Loop path` / `### Interactive` (or hook) under `## Workflow` with numbered steps |
| `## Reference Files Guide` | One bullet per file; explicit load contract on every line |
| `### Error Handling` | **Q-10 SHOULD**  - table under `## Workflow` (not a sixth H2). Required for loop/utility/review skills with recoverable or fatal branches; match sibling table format |

**S-01 vs Q-10:** `agent-skills-review` requires `## Workflow` (MUST). It does **not** require a top-level `## Error Handling` H2  - that was removed as redundant with standard tool behavior. Error paths belong in `### Error Handling` **inside** Workflow (condition \| severity \| action), per Q-10 (SHOULD). When one loop skill has this table, siblings in the same family should too.

**Reference Files Guide  - load contracts (determinism):**

Use a fixed phrase per line so agents do not infer load timing from prose elsewhere.

| Phrase | When to use |
| ------ | ----------- |
| `(always read)` | Load on every run for this skill |
| `(always read  - loop path)` | Load when `## Workflow` loop branch runs |
| `(always read  - interactive path)` | Load when interactive/hook branch runs |
| `(read on failure)` | Optional diagnostics only (`common-troubleshooting.md`, debug command catalogs) |

**Avoid** vague triggers such as `Read when parsing context`, `- apply`, or `- loop` without `(always read …)`  - they duplicate workflow conditions and diverge across skills. If workflow step 1 always parses a schema, that schema is `(always read)` (or path-qualified), not conditional.

When adding or changing one skill's `SKILL.md`, compare against siblings in the same package **and the matching skill in sibling domain packages** (validation ↔ review pairs), then align section depth and reference phrasing in the **same change**.

### Skill eval packaging (waza / skill-creator)

Ship **thin eval harnesses inside each skill**; keep **heavy verification outside** the distributable package.

| Layer | Location | Purpose | Download cost |
| ----- | -------- | ------- | ------------- |
| **Contract eval** | `skills/<name>/eval.yaml` + `evals/tasks/*.yaml` | Output sections, boundary guardrails, mock-smoke | Small (YAML only; keep in skill) |
| **Optional fixtures** | `evals/files/` only when mock requires paths | Minimal stubs; avoid large binaries | Small if tiny text files; skip when prompt can embed context |
| **Behavior verification** | Repo CI: `test/bats/`, `scripts/*/validate.sh`, `waza run --baseline` / real executor | Scripts, integration, with-vs-without-skill | Not shipped to consumers |
| **Description tuning** | `tmp/` or maintainer workspace | Trigger optimization experiments | Not shipped |

**Rules:**

- Every skill SHOULD have `eval.yaml` with at least: output-contract, one happy path, one boundary/trigger-negative where applicable.
- Prefer **inline JSON/context in prompts** over `evals/files/` for mock runs (mock echoes prompts; fixtures add bytes without improving discrimination).
- Do **not** bundle large test corpora in APM packages  - consumers download skills for execution instructions, not regression datasets.
- Mock eval passing means **structure/regression of the contract**, not that the skill works in production. Treat **100% mock + CI green** as the release bar for this repository.

`evals/evals.json` (skill-creator format) is optional and maintainer-facing; use for A/B description or subagent benchmarks, not required in every skill.

### Validation Scripts Mirror (`scripts/` ↔ skill)

Domain validation entrypoints exist in **two places** in this repository. Keep them aligned via `bash scripts/ai/sync_validate_mirror.sh`  - edit one side, run the sync script; do not hand-edit the paired copy.

| Domain         | Mirrored files (repo `scripts/<domain>/` → skill `scripts/`) |
| -------------- | ------------------------------------------------------------ |
| `shell-script` | `validate.sh`, `fix_function_doc_order.sh`                   |
| `go`           | `validate.sh`                                                |
| `terraform`    | `validate.sh`                                                |

**Path layout (applied only by `sync_validate_mirror.sh`  - do not hand-edit both sides or apply these transforms manually)**:

| Setting          | Skill copy (`…/skills/*/scripts/`)      | `scripts/<domain>/` copy               |
| ---------------- | --------------------------------------- | -------------------------------------- |
| Library import   | `source "${SCRIPT_DIR}/lib/all.sh"`     | `source "${SCRIPT_DIR}/../lib/all.sh"` |
| `shellcheck`     | `# shellcheck source=./lib/all.sh`      | `# shellcheck source=../lib/all.sh`    |
| `WORKSPACE_ROOT` | `$(cd "${SCRIPT_DIR}/../../.." && pwd)` | `$(cd "${SCRIPT_DIR}/../.." && pwd)`   |

`WORKSPACE_ROOT` differs only for `shell-script` `validate.sh` (skill tree is deeper). `go` and `terraform` differ only in the library import lines. `fix_function_doc_order.sh` differs only in library import lines.

**Workflow**:

1. Edit the repo or skill copy (not both manually).
2. Run `bash scripts/ai/sync_validate_mirror.sh` (or `--from-skill` when the skill copy was edited; `--domain` to limit scope).
3. Run the relevant Bats suites under `test/bats/scripts/<domain>/` when behavior changes.

`scripts/lib/` follows the one-way sync in [CLAUDE.md section Scripts and Skill Mirrors](../CLAUDE.md#scripts-and-skill-mirrors). Do not edit skill `scripts/lib/` directly.

## Security Guidelines

General repository security rules live in [CLAUDE.md § Security Guidelines](../CLAUDE.md#security-guidelines) and [AGENTS.md](../AGENTS.md). Additionally for package sources:

- Do not place real secrets, tokens, or internal URLs in package instructions, skills, or eval fixtures.
- Use obvious placeholders in examples and document redaction where relevant.
