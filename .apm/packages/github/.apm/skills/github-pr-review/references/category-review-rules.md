# Review Rules

## Evidence kinds

Report a finding only when it has one of three evidence kinds. No evidence, no finding.

| Kind       | Evidence                                                                                                                | Required fields                        |
| ---------- | ----------------------------------------------------------------------------------------------------------------------- | -------------------------------------- |
| `rule`     | Verbatim text from an agent instruction file (such as AGENTS.md or CLAUDE.md, including nested and path-scoped rules)   | `evidence.path`, `evidence.quote`      |
| `criteria` | Verbatim text of an ID-tagged item in a domain review reference (`references/category-*.md`) that matches the file type | `evidence.path`, `evidence.quote`      |
| `bug`      | The diff line and the concrete input or state that makes it fail; no rule is needed                                     | `evidence.quote` (line plus the input) |

- Read rules and criteria from the **base commit** (the working tree), never from the PR head. A PR that edits a rule does not change what it is reviewed against.
- Quote exactly: no paraphrase, no whitespace normalization. If the verbatim text cannot be found at base, drop the finding.
- A `bug` finding states a failure that can be reproduced by reasoning from the diff line, for example "empty array input: `items[0]` is undefined at line 42". "Might be a problem" is not a bug.

## Severity

| Severity     | Use for                                                                       |
| ------------ | ----------------------------------------------------------------------------- |
| `Critical`   | Data loss, security exposure, broken build or deploy, or a MUST-level rule    |
| `Warning`    | Likely defect or a SHOULD-level rule violation with real impact               |
| `Suggestion` | Low-impact improvement still backed by a rule, criteria item, or concrete bug |

Use only these three values.

## Pre-existing problems

Report only problems caused by lines the PR adds or changes. Do not report a problem that already existed at the base commit, even if the PR touches nearby lines or the file.

## Do not report

- Generated files, lock files, and tool-regenerated diffs
- Items that hooks and CI already detect (lint, format, secrets)
- Preferences that no rule or criteria item states
- Theoretical risks that need unrealistic assumptions to occur
- Pre-existing problems
- Repeated findings: merge duplicates into one; avoid nit floods

## Context first

Before drafting findings, read the PR body, linked Issues, and related specs. A finding that contradicts the stated intent without acknowledging it is "no context" and must be dropped. Record what you read in `premises`.

## Open changed files at base

Do not rely on the diff alone. Open each changed file in the working tree (the base commit) so the engine loads rules scoped to that path. Do not list rule file paths from memory; use the rules the engine loaded and the files you opened. Read the head version and the diff with read-only `gh pr diff` / `gh api`.

## Response language

Decide the language of agent-written prose in this order:

1. `response_language` in `## Constraints` (MUST follow when present)
2. Language of the PR title and body
3. English when undetermined

Write in that language: `summary`, finding `title`, `impact`, and `premises` text. Keep in English: headings, field names, severities, evidence kinds, fixed phrases, and the marker. Keep verbatim: quotes, code, paths, identifiers, commands.
