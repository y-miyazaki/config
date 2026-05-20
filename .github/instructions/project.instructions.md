---
applyTo: "**"
description: "Repository-specific operational rules"
---

# AI Assistant Instructions for Project

## Scope

- These rules apply to the entire repository.

## Standards

### Naming Conventions

| Component           | Rule                                 | Example                                        |
| ------------------- | ------------------------------------ | ---------------------------------------------- |
| Instruction file    | `project.instructions.md`            | `.github/instructions/project.instructions.md` |
| Temporary artifacts | Use an ignored repository-local path | `tmp/report.txt`                               |

### Repository Rules

- Write temporary and generated artifacts under `tmp/` unless a more specific ignored path is defined.
- Keep generated files out of version control unless they are intentionally committed.
- Prefer repository-local paths and conventions when adding or updating artifacts.
- If a workflow generates files that must be committed, document the intent in the relevant change.

### Anti-Patterns

- Do not place repository-specific operational rules in `AGENTS.md`.
- Do not rely on ignored paths for instructions that must be tracked.
- Do not duplicate the same rule in multiple instruction files unless there is a clear ownership split.

### Code Modification Guidelines

- Make the smallest safe change.
- Update the relevant instruction file when repository rules change.
- Re-run the applicable validation after changing instruction files.

## Testing and Validation

- Validate the repository rules after changes to this file.

```bash
apm install --update
apm audit --ci
markdownlint .github/instructions/*.instructions.md
git diff --check
```

## Security Guidelines

- Do not store secrets, tokens, or credentials in instruction files.
- Do not make destructive operations the default in command examples.
- Keep operational guidance concise and reviewable.
