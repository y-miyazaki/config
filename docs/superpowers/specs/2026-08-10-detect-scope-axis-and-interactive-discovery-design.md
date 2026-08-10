# Detect Scope Axis and Interactive Discovery Design

**Status:** Approved (grill-me session 2026-08-10)  
**Date:** 2026-08-10  
**Primary consumers:** utility skills with detect scripts — `changelog`, `ci-sweeper`, `docs-updater`, `refactor`, `tech-debt`  
**Related:** [Refactor skill & loop design](2026-07-21-refactor-skill-and-loop-design.md), [Loop skill consolidation](2026-07-21-loop-skill-consolidation-design.md), [APM package design](../../explanation/apm-package-design.md), [.apm/AGENTS.md](https://github.com/y-miyazaki/config/blob/main/.apm/AGENTS.md) (portable skill design)

## Problem

1. **`--scope` vocabulary drift** — Sibling detect scripts share CLI tokens `staged` | `all` | `range`, but `all` means different things (glob-filtered tree, HEAD working-tree diff, recent commits, recent CI failures). Agents and humans misread Interactive “full survey” as whatever that skill’s `all` happens to do.
2. **Interactive discovery under-specified** — Automation paths document `hints[]` / detect JSON clearly. Interactive paths often say only “explore” or “when helpful,” so Agents skip detect, under-survey, or treat Loop-only machinery as irrelevant.
3. **Detect completeness myth** — Mechanical detect is capped and kind-limited. Without an explicit Agent complement step, empty or thin detect output becomes a false no-op.

## Goals

- Define one **cursor axis** for `--scope` and a **domain mapping table** per skill (same words, explicit projections).
- Make Interactive discovery **self-contained**: resolve universe → run detect (default) → Agent complements → survey/apply per `may_edit`.
- Frame file-oriented `all` as **enumerate then optional glob filter**, not “glob is the universe from the start.”
- Document first (this spec + thin portable skill references), then align SKILL.md / detect usage / docs-updater `all` behavior in one implementation wave.
- Keep package sources portable (no this-repo Loop workflow names in `.apm/packages/**`).

## Non-Goals

- Adding new scope tokens (for example `workdir`).
- Splitting file-scope vs event-scope into separate CLIs.
- Removing noop scopes that exist only for detect CLI parity (prefer deprecated/noop over breaking callers).
- Changing Loop finalize / state-cursor ownership.
- Making detect exhaustive or removing hint caps (`REFACTOR_MAX_HINTS`, CI run limits, changelog commit caps).

## Decisions (from grill-me)

| ID  | Topic                  | Choice                                                                                                                   |
| --- | ---------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| D1  | Scope of work          | Normalize `--scope` semantics **and** Interactive discovery across siblings; document then SKILL/detect cleanup          |
| D2  | Normalization style    | **Common cursor axis + per-skill domain mapping** (not identical file semantics; not CLI fork)                           |
| D3  | Axis definition        | `range` = commit cursor; `all` = no cursor, full domain enumeration; `staged` = index cursor (file skills)               |
| D4  | docs-updater `all`     | Change meaning to **candidate-docs full enumeration** (not `git diff HEAD` + untracked)                                  |
| D5  | Former workdir diff    | No new token — hook → `staged`; Loop → `range`; Interactive free-form → `all`                                            |
| D6  | File universe          | Enumerate eligible files first; apply skill glob filter when configured; unset glob ⇒ no filter                          |
| D7  | Interactive detect     | **Always run** detect when JSON not already supplied (sibling-unified); Agent complements beyond detect                  |
| D8  | ci-sweeper Interactive | Keep detect on Interactive path (A) for contract unity; run URL remains primary evidence when supplied                   |
| D9  | Doc placement          | Spec is normative; each skill ships a **thin portable** axis + own mapping row in `references/`                          |
| D10 | Delivery order         | Spec → shared reference wording → SKILL Interactive steps → docs-updater detect behavior + tests → other usage/noop docs |

## Architecture

### Cursor axis (normative)

`--scope` selects **how the domain universe is cut**, not a universal file meaning.

| Value    | Cursor                      | Common meaning                                                                      | Typical caller            |
| -------- | --------------------------- | ----------------------------------------------------------------------------------- | ------------------------- |
| `range`  | Commit (`--since` required) | Universe members related to `<since>..HEAD`                                         | Automation / state cursor |
| `all`    | None                        | Full enumeration of the domain universe, then domain caps/filters                   | Interactive free-form     |
| `staged` | Index (`--cached`)          | Universe members present in the index; **meaningful for file-oriented skills only** | git hook / pre-commit     |

Rules:

1. Same token ⇒ same axis meaning. Domain differences live only in the mapping table.
2. Scopes that cannot project onto a domain (for example `staged` on CI runs) are **accepted-but-noop / deprecated** in usage text — keep CLI parity; do not invent fake staged CI semantics.
3. Missing `--since` on `range` remains fatal.
4. Interactive with no path/diff/SHA cue ⇒ Agent uses `all` after resolving the universe from speech (default skill config when unspecified).
5. **`all` is not unbounded:** domain caps still apply (hint caps, max commits, max failed runs, etc.). Cap hits must be visible in detect JSON or Agent Overview.

### File-oriented enumeration (normative)

For skills whose natural units are files (`refactor`, `tech-debt` tree walk, `docs-updater` candidate docs):

```text
enumerate eligible paths (e.g. tracked / discovered docs)
  → if skill glob env/default is set: keep matches only
  → if unset/empty: no glob filter
  → apply --scope cursor (all | range ∩ changes | staged ∩ index)
  → emit mechanical facts
```

Interactive narrowing: Agent **resolves the universe from user speech first** (path/glob allowlist), then runs detect with that universe (via env globs or equivalent). Do not run default-wide `all` and discard most results afterward when the user already named a subtree.

### Non-file domains

| Skill        | Natural units               | Notes                                                                                    |
| ------------ | --------------------------- | ---------------------------------------------------------------------------------------- |
| `changelog`  | Commits / version narrative | Same axis tokens; projection is commit sets, not files                                   |
| `ci-sweeper` | Failed CI runs / jobs       | Same axis tokens; local Interactive is secondary to automation but **remains supported** |

## Domain mapping

| Skill          | Domain universe                                                                                                  | `all`                                                | `range`                                                                                                                    | `staged`                                 |
| -------------- | ---------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------- |
| `refactor`     | Enumerated code/config paths, then `REFACTOR_SCAN_GLOBS` when set (default today: `.apm/packages/**,scripts/**`) | Full enumerated∩filter scan → `hints[]`              | Changed paths in `<since>..HEAD` ∩ filter                                                                                  | Cached paths ∩ filter                    |
| `tech-debt`    | Repository sensor universe (full tree walk today)                                                                | Full sensor pass                                     | Document current behavior in implementation: parity accept and/or narrow sensors; must not silently redefine without tests | noop / deprecated                        |
| `docs-updater` | Candidate docs (`DOCS_UPDATER_DOC_GLOBS` or default `*.md` discovery)                                            | **Full candidate-doc enumeration** (behavior change) | Impact from `<since>..HEAD` changes                                                                                        | Impact from cached diff (hook)           |
| `changelog`    | Commit set with `CHANGELOG_MAX_COMMITS` (or successor) cap                                                       | Cap-bounded commits without since-cursor             | `<since>..HEAD` commits                                                                                                    | Not applicable if unsupported; else noop |
| `ci-sweeper`   | Failed runs on the relevant branch with scan limit                                                               | Limit-bounded failure enumeration                    | Failures related to `--since` window                                                                                       | **noop / deprecated**                    |

### Path roles (docs-updater example; portable wording)

| Path                                    | `--scope`             | Notes                                                             |
| --------------------------------------- | --------------------- | ----------------------------------------------------------------- |
| Interactive free-form (“docs 更新して”) | `all`                 | Full candidate-doc survey; Agent complements                      |
| git hook / pre-commit                   | `staged`              | Index only; untracked not visible without add — accepted residual |
| Automation with state cursor            | `range --since <sha>` | Unchanged Loop ownership                                          |

“Hook” means **git hook** (for example pre-commit), not GitHub webhook.

## Interactive discovery contract (all listed siblings)

Applies when the user invokes the skill without a complete caller detect JSON envelope.

1. Resolve **may_edit** / write target per that skill’s existing table.
2. Resolve **universe** from prompt + Constraints (default = skill config).
3. If detect JSON is absent: run that skill’s optional detect script with the resolved scope (default `all`).
4. On detect non-zero / `status: "error"`: read stdout; stop or fall back per skill Error Handling — do not treat as success-path JSON.
5. Classify mechanical outputs (`hints[]`, `signals[]`, failures, commits, doc impacts, …).
6. **Agent complement:** read targets; add structural/debt/CI/doc candidates that detect cannot see; user-supplied run URL, path, or symbol is **primary evidence** when present (especially `ci-sweeper`).
7. Empty detect alone does **not** force no-op if Agent complement found in-scope work.
8. Emit survey or apply shape per existing output contracts.

### ci-sweeper Interactive (D8)

- Keep “principle: run detect” for sibling unity.
- When the user supplies a workflow run URL / job id / log excerpt, treat that as primary evidence; detect branch enumeration is auxiliary, not a reason to bury the named run.
- If `gh`/auth/tools are missing: fall back to user-supplied context; do not silent no-op.

## Documentation layout

| Artifact                        | Role                                                                                                           |
| ------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| This spec                       | Normative design for maintainers and implementation plans                                                      |
| Each skill `references/` (thin) | Portable cursor-axis summary + **that skill’s mapping row** + Interactive steps pointer — no `on-loop-*` names |
| SKILL.md Workflow               | Interactive path: universe → detect → complement (match `docs-updater` / `tech-debt` depth)                    |
| Maintainer loop/hook docs       | Update only where callers still assume old docs-updater `all`                                                  |

## Migration

### Breaking

- **docs-updater `--scope all`:** stops meaning “git diff HEAD + untracked”; means full candidate-doc enumeration. Callers/hooks using `all` for worktree sync must switch to `staged` or `range`.
- Skill descriptions that claim Interactive is diff-only must be updated for docs-updater / shared Interactive wording.

### Non-breaking / clarifying

- ci-sweeper / tech-debt `staged` documented as noop/deprecated.
- refactor/tech-debt/changelog `all` aligned to axis language; behavior stays enumeration∩filter/caps unless tests prove otherwise.
- Interactive “run detect when helpful” → “run detect when JSON absent” across siblings.

### Residual risks (accepted)

1. Hook `staged`-only misses untracked docs (no Agent in hook path).
2. Interactive `all` on docs-updater shifts toward drift survey vs pure change-sync — update USE FOR / description.
3. Domain caps mean `all` ≠ infinite history.
4. Expensive detects (tech-debt sensors, ci-sweeper `gh`) on Interactive — mitigate with caps and auth fallbacks.
5. Narrow user path still runs detect, but on the **resolved smaller universe**.

## Implementation wave (approach 1)

1. Land this spec.
2. Add/adjust portable reference text in each utility skill; wire Reference Files Guide load triggers (`interactive path` / detect script).
3. Rewrite Interactive Workflow steps for siblings that lack “detect then complement.”
4. Change `docs-updater` `detect_changes.sh` `all` + Bats; update hook examples to `staged`.
5. Align other detect usage headers and noop notes; add/adjust Bats where behavior assertions exist.
6. Touch maintainer loop/hook explanation docs only as needed for the docs-updater breaking change.

## Out of scope for the first implementation plan

- Redesigning tech-debt `range` sensor narrowing policy beyond documenting current behavior.
- Performance redesign of full-repo sensors.
- New detect hint kinds for refactor.

## Open implementation details (non-blocking)

These do not reopen grill decisions; resolve in the implementation plan with tests:

- Exact docs-updater `all` enumeration API (reuse glob discovery vs new walker).
- Whether tech-debt `range` remains parity-only or gains real narrowing.
- Shared vs per-skill filename for the thin reference (`category-detect-scope.md` vs section in `category-input-schema.md`).
