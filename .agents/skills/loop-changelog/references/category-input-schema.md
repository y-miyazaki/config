## Input Schema

Provided via prompt context by the calling workflow (loop-prompt-generate action).

```json
{
  "changelog_file": "CHANGELOG.md",
  "changelog_exists": false,
  "commit_range": "abc1234..def5678",
  "compare_url": "https://github.com/owner/repo/compare/abc1234..def5678",
  "level": "L2",
  "repository": "owner/repo",
  "repository_url": "https://github.com/owner/repo",
  "skip": false,
  "commits": [
    {
      "sha": "def5678",
      "type": "feat",
      "scope": "changelog",
      "breaking": false,
      "subject": "add loop-changelog workflow"
    },
    {
      "sha": "abc1234",
      "type": "renovate",
      "scope": "mise",
      "breaking": false,
      "subject": "Update dependency pnpm to v11.10.0 (#313)"
    }
  ]
}
```

| Field | Type | Description |
| `changelog_file` | string | Repository-relative path to update |
| `changelog_exists` | boolean | When false, create Keep a Changelog template before editing |
| `commit_range` | string | SHA range that triggered detection |
| `compare_url` | string | Optional GitHub compare URL for the active `commit_range` (empty when unknown) |
| `level` | enum | Operating level: `L1` (report only), `L2` (edit + PR), `L3` (edit + auto-merge) |
| `repository` | string | `owner/repo` when resolved (Actions env or git remote) |
| `repository_url` | string | Web base URL for commit links (no trailing slash) |
| `skip` | boolean | When true, no unreleased changelog-worthy commits |
| `commits` | array | Commits to summarize (may be empty) |
| `commits[].sha` | string | Full commit SHA |
| `commits[].type` | string | Prefix type (`feat`, `fix`, `renovate`, `chore`, …) |
| `commits[].scope` | string | Optional scope from subject line |
| `commits[].breaking` | boolean | Whether the commit is marked breaking |
| `commits[].subject` | string | Subject text after the `type(scope):` prefix |

Path allowlist is injected in the implementer prompt `## Constraints` section from the caller (`LOOP_ALLOWLIST`). See [category-scope.md](category-scope.md).
