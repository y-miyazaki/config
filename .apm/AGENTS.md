# AGENTS.md

Behavioral rules for editing APM package sources under `.apm/packages/`. Self-contained for package authors and agents.

---

## Scope

- Applies when creating or updating files under `.apm/packages/**`.
- These packages are **distribution artifacts**: `apm install` materializes them into consumer repositories (`.cursor/`, `.claude/`, `.agents/`, and similar).
- Consumer-specific conventions belong in the consumer repository, not in package sources.

## Configuration Philosophy

APM packages distribute **configuration**, not a complete toolchain. Tool execution rules differ by layer — do not apply MCP rules to hooks or skills.

| Layer  | Purpose                           | Tool resolution                               | When tool absent                              |
| ------ | --------------------------------- | --------------------------------------------- | --------------------------------------------- |
| MCP    | Agent capabilities at runtime     | `npx` / `uvx` with pinned versions (required) | Server fails to start; fix runtime or network |
| Hooks  | Optional in-session lint/format   | `PATH` lookup for native binaries             | Exit 0 — do not block agent sessions          |
| Skills | On-demand validation when invoked | `PATH` lookup via `scripts/validate.sh`       | Report `SKIP` in structured output            |

**Minimal consumer prerequisites**: APM CLI, Node.js (`npx`) and/or Python with [uv](https://docs.astral.sh/uv/) (`uvx`), plus network for MCP runtime fetch. Per-linter global installs are not required.

**Recommended dev setup**: Install linters on `PATH` (for example via [mise](https://mise.jdx.dev/)) so hooks and skills run fully. This is an optimization, not an APM package requirement.

See [Config Repository Architecture](../docs/explanation/architecture.md#configuration-philosophy) and [Config Repository Functional Specification](../docs/reference/specification.md#configuration-philosophy).

### MCP — Runtime Resolution

- Declare `command: npx` or `command: uvx` with pinned versions in `args`. Use `-y` with `npx` for non-interactive fetch.
- Do not document per-MCP global installs as required consumer steps.
- **Exceptions**: MCP servers with no npm/PyPI distribution (for example `codebase-memory-mcp`) use a bare binary command and are **optional** — document that consumers must install the binary separately or omit the server.

### Hooks — Optional Enforcement

- Hooks are **not** a quality gate. They provide best-effort lint/format when tools happen to be on `PATH`.
- Use `command -v tool || exit 0` before running native binaries (`actionlint`, `golangci-lint`, `shellcheck`, and similar). Most hook tools are **not** available via `npx`/`uvx`.
- Do not block agent sessions when linters are absent.
- Prefer emitting a skip notice to stderr when skipping (for example `actionlint not installed — hook skipped`) so users know enforcement did not run.

### Skills — Explicit Validation

- Skills run only when an agent invokes them. Route checks through `scripts/validate.sh`; do not assume tools are installed.
- When a tool is missing, record `SKIP` (with reason) in structured output — not silent success.
- Use `npx`/`uvx` inside skill scripts only when the tool is published to npm or PyPI. Most domain linters remain native binaries on `PATH`.

## Distributable Content

### Repository-Neutral Rules

Package instructions, skills, and references must work in any consumer project. Do **not** embed:

- Paths or names from this config repository (for example `.github/actions/loop-*`, `.apm/packages/loop-*`, internal script filenames).
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

| Edit here (source of truth)          | Do not edit (generated by `apm install`)                 |
| ------------------------------------ | -------------------------------------------------------- |
| `.apm/packages/<name>/`              | `.cursor/`, `.claude/`, `.agents/`, `.kiro/`, `.vscode/` |
| `scripts/lib/` (then sync to skills) | `.apm/packages/*/skills/*/scripts/lib/` directly         |

After package changes:

1. Run `scripts/apm/sync_guidelines_from_categories.pl` when `category-*.md` or sync-mapped instructions change.
2. Run `apm install --update`.
3. Verify with `apm audit --ci`.

## Instructions Maintenance

### Sync-Managed Files

`scripts/apm/sync_guidelines_from_categories.pl` regenerates `## Guidelines` (and `common-checklist.md`) from `category-*.md` for mapped review skills. See [Instructions Sync Workflow](../docs/explanation/instructions-sync-workflow.md).

- Edit review criteria in `.apm/packages/<pkg>/.apm/skills/<skill>-review/references/category-*.md`.
- Re-run the sync script; do not hand-edit generated guideline bullets unless you accept they will be overwritten.
- `### Anti-Patterns` and other guideline subsections must live in a `category-*.md` file or they disappear on sync.

### Manually Maintained Instruction Files

Not regenerated by the sync script — edit directly and run re-evaluation:

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
- Shared shell libraries: edit `scripts/lib/`, then `bash scripts/ai/sync_skill_lib.sh`, then `apm install --update`.
- Do not create skill-specific minimal copies of `scripts/lib/` (for example a `json.sh`-only loader).

## Security

- Do not place real secrets, tokens, or internal URLs in package instructions, skills, or eval fixtures.
- Use obvious placeholders in examples and document redaction where relevant.
