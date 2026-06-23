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
- DOC-00 (MUST): Preserve Existing Structure
  - Check: Does the change modify only the relevant section without unnecessary reorganization?
- DOC-01 (SHOULD): Document Splitting
  - Check: Is the document becoming difficult to navigate, review, or maintain as a single file?
- DOC-02 (SHOULD): Image Optimization
  - Check: When image metadata is available, are images PNG for diagrams and JPEG for photos, preferably under 500KB, and sized for readability?
- DOC-03 (SHOULD): Reuse Existing Documentation Structure
  - Check: Can the information be added to an existing document before creating a new file or directory?
- DOC-04 (SHOULD): Preserve Rationale
  - Check: When simplifying documentation, is important context or rationale preserved?
- DOC-05 (MUST): Use Relative Path Links with Document Title in docs/
  - Check: Are cross-references within `docs/` written as relative Markdown links (`.md` extension) with the link text set to the target document's title (H1 heading or section heading)? Do not use file names, file paths, raw URLs, or generic labels such as "here" as link text. MkDocs resolves `.md` relative links into navigable site links — using file paths as link text results in `docs/...` labels in the rendered site.
  - ✅ `[Architecture Decision Records](../reference/adr.md)` (link text = target H1 title)
  - ❌ `[adr.md](../reference/adr.md)` (link text = file name)
  - ❌ `[../reference/adr.md](../reference/adr.md)` (link text = file path)
  - ❌ `[click here](../reference/adr.md)` (generic label)

### Terminology and Consistency (TERM)
- TERM-01 (MUST): Use Official Product Names
  - Check: Are product names written in their official form (e.g., PostgreSQL not postgres/Postgres, GitHub Actions not github actions, Terraform not terraform in prose)?
- TERM-02 (SHOULD): Consistent Terminology Within Context
  - Check: Are terms used consistently within the same section or paragraph without unexplained alternation (e.g., do not switch between "repository" and "repo" without first establishing the short form)?
- TERM-03 (SHOULD): Define Abbreviations on First Use
  - Check: Are abbreviations spelled out on first occurrence with the short form in parentheses (e.g., "Architecture Decision Record (ADR)")?
- TERM-04 (SHOULD): Avoid Ambiguous Pronouns and Vague References
  - Check: Are subjects explicit instead of using "it", "this", "that" without a clear antecedent?
- TERM-05 (SHOULD): Keep Information Fresh
  - Check: Are version numbers, dates, and URLs current and not obviously stale? Do not invent versions or dates.
- TERM-06 (SHOULD): Prefer Active Voice in Procedures
  - Check: Are instructions written in active voice with a clear actor (e.g., "Run the script" not "The script should be run")?
- TERM-07 (SHOULD): Specify Code Block Language
  - Check: Do fenced code blocks include a language identifier (e.g., ```bash,```json, ```yaml)?
- TERM-08 (SHOULD): Verify Against Repository State
  - Check: Are commands, file paths, and documented behaviors consistent with the current repository contents?
- TERM-09 (MUST): Do Not Invent Documentation
  - Check: Is every documented feature, command, file path, or workflow supported by repository contents or provided context?

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

Markdown checks run automatically via pre-commit hooks on commit. Manual execution is for debugging only.

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
- Do not expose internal infrastructure details, private repository URLs, or organization-specific identifiers (AWS account IDs, internal hostnames, Slack/Jira URLs).
- Do not make destructive operations the default in command examples; add warnings when required.
- Prefer trustworthy primary sources for external links and avoid unclear shortened URLs.
- If code samples include dummy credentials, explicitly label them as dummy values.
