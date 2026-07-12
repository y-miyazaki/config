# loop-changelog Checklist

## Type → Section Mapping (Keep a Changelog)

| Commit type (`commits[].type`) | Unreleased subsection |
| `feat` | Added |
| `fix` | Fixed |
| `docs` | Changed |
| `refactor`, `perf`, `style` | Changed |
| `build`, `ci`, `chore`, `test`, `revert` | Changed |
| `renovate`, `dependabot` | Changed (Dependencies) |
| `chore` with `scope=deps` | Changed (Dependencies) |
| Other explicit prefixed types | Changed |
| Breaking (`!` or `BREAKING CHANGE`) | note under subsection |

## Bullet links

When detect JSON includes `repository_url`:

- Each new bullet ends with a parenthesized commit link: opening paren, bracketed 7-char sha, URL `{repository_url}/commit/{full sha}`, closing paren
- Use the commit `subject` as the leading text (add scope in prose when helpful)
- When `repository_url` is empty, omit links (subject-only bullets)

When detect JSON includes `compare_url` and `## [Unreleased]` has no diff link yet:

- Insert one line directly under `## [Unreleased]`: `[Full diff]({compare_url})`
- Do not add compare links under released version sections

## Scope Guards

- Edit only `changelog_file` from input (must match allowlist)
- Do not remove or rewrite released version sections
- Do not bump version headers or add release dates

## Output

- Emit all report sections per `common-output-format.md`
- List every commit SHA processed in Summary

## Error Handling

- `skip` true or empty `commits` → report with Summary `No unreleased changelog commits`; stop
- `changelog_exists` false → create Keep a Changelog template, then add bullets
- Malformed existing changelog → preserve released sections; append/fix only `## [Unreleased]`
