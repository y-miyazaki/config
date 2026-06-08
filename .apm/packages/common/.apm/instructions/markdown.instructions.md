---
applyTo: "README.md,CONTRIBUTING.md,docs/**/*.md"
description: "AI Assistant Instructions for Markdown Documentation"
---

# AI Assistant Instructions for Markdown

## Scope

- Scope is limited to documentation maintenance for `README.md`, `CONTRIBUTING.md`, and `docs/**/*.md`.
- This file defines repository-specific documentation operations rather than general Markdown theory.

## Standards

### Naming Conventions

| Component    | Rule       | Example                   |
| ------------ | ---------- | ------------------------- |
| File (docs/) | kebab-case | getting-started.md        |
| Image file   | kebab-case | architecture-overview.png |
| Directory    | kebab-case | docs/user-guide/          |

## Guidelines

### Structure and Formatting (DOC)
- DOC-01 (MUST): README.md Section Order
  - Check: Does README.md follow the order: Title+Badge → Description → Features → Installation/Setup → Usage/Examples → Configuration → License/Contributing?
- DOC-02 (SHOULD): Table of Contents
  - Check: Is a TOC present when the document has three or more H2 sections?
- DOC-03 (SHOULD): Document Splitting
  - Check: Are large documents split into logical sections rather than kept as single monolithic files?
- DOC-04 (SHOULD): Image Optimization
  - Check: Are images PNG for diagrams and JPEG for photos, kept under 500KB, and sized for readability without excessive resolution?

### Terminology and Consistency (TERM)
- TERM-01 (MUST): Use Official Product Names
  - Check: Are product names written in their official form (e.g., PostgreSQL not postgres/Postgres, GitHub Actions not github actions, Terraform not terraform in prose)?
- TERM-02 (MUST): No Abbreviation Drift
  - Check: Is the same term used consistently throughout a document (e.g., infrastructure not mixed with infra, repository not mixed with repo)?
- TERM-03 (SHOULD): Define Abbreviations on First Use
  - Check: Are abbreviations spelled out on first occurrence with the short form in parentheses (e.g., "Architecture Decision Record (ADR)")?
- TERM-04 (SHOULD): Avoid Ambiguous Pronouns and Vague References
  - Check: Are subjects explicit instead of using "it", "this", "that" without a clear antecedent?
- TERM-05 (SHOULD): Keep Information Fresh
  - Check: Are version numbers, dates, URLs, and file paths verified against current state and not stale?
- TERM-06 (SHOULD): Prefer Active Voice in Procedures
  - Check: Are instructions written in active voice with a clear actor (e.g., "Run the script" not "The script should be run")?
- TERM-07 (SHOULD): Specify Code Block Language
  - Check: Do fenced code blocks include a language identifier (e.g., ```bash,```json, ```yaml)?

### Revision Process

1. Identify the target section.
2. Review existing content.
3. Check consistency with related files.
4. Apply updates.
5. Verify formatting.

### Code Modification Guidelines

- After changes, prioritize the validation workflow from markdown-validation skill.
- Use individual checks for broken links and table formatting only during debugging.

## Testing and Validation

**Entry point (recommended)**:

```bash
bash <agent-root>/skills/markdown-validation/scripts/validate.sh
```

**Individual execution (debugging)**:

```bash
markdownlint-cli2 "docs/**"
markdown-link-check --quiet README.md
```

**Detailed guide**: See markdown-validation skill SKILL.md.

## Security Guidelines

- Do not include sensitive information (tokens, keys, internal URLs, personal data) in documentation.
- Do not make destructive operations the default in command examples; add warnings when required.
- Prefer trustworthy primary sources for external links and avoid unclear shortened URLs.
- If code samples include dummy credentials, explicitly label them as dummy values.
