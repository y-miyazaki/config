## Validation Commands

Run applicable checks after edits (use project validation skills):

| Changed area | Command |
|---|---|
| GitHub Actions workflows | `bash <agent-root>/skills/github-actions-validation/scripts/validate.sh` |
| Shell scripts | `bash <agent-root>/skills/shell-script-validation/scripts/validate.sh` |
| Markdown docs | `bash <agent-root>/skills/markdown-validation/scripts/validate.sh` |
| Go sources | `bash <agent-root>/skills/go-validation/scripts/validate.sh` |
| APM packages | `apm audit --ci` |

`<agent-root>` is one of: `.github`, `.agents`, `.claude`, `.cursor`, `.kiro`.

List commands run and their outcome in the report **Summary** section.
