## Debt Taxonomy

Classify every finding with **category**, **severity**, and optional **nature**.
Rules below map to public standards — do not invent private taxonomies.

### Sources (canonical)

| Topic                         | Source                                                                                                                                     | Use for                                                  |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------- |
| Debt metaphor / nature        | [Martin Fowler — Technical Debt Quadrant](https://martinfowler.com/bliki/TechnicalDebtQuadrant.html)                                       | `nature` labels                                          |
| Code review axes              | [Google eng-practices — What to look for](https://google.github.io/eng-practices/review/reviewer/looking-for.html)                         | `code_quality`, `test_gap`, `architecture`               |
| Software qualities + severity | [SonarQube — Clean Code / software qualities](https://docs.sonarsource.com/sonarqube-server/latest/core-concepts/clean-code/introduction/) | severity scale; security / reliability / maintainability |
| Dependency versioning         | [Semantic Versioning](https://semver.org/)                                                                                                 | `dependency_version`                                     |
| Documentation form            | [Diátaxis](https://diataxis.fr/)                                                                                                           | `documentation`                                          |

### Categories

Assign exactly one primary `category` per finding:

| Category             | Include when                                                                                                                           | Exclude / send elsewhere                                                      |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| `code_quality`       | Complexity, poor naming, duplicated logic, brittle structure, maintainability smells (Google Complexity/Naming; Sonar Maintainability) | One-off style nits without evidence → `noise`                                 |
| `test_gap`           | Missing or weak tests for changed/critical paths (Google Tests)                                                                        | Flaky CI infrastructure repair → loop-ci-sweeper                              |
| `architecture`       | Wrong boundary, premature abstraction, deliberate shortcut that blocks change (Google Design; Fowler deliberate debt)                  | Local tidy-ups without design impact → `code_quality`                         |
| `dependency_version` | Version lock, version promiscuity, EOL / unsupported major, pin drift that blocks safe upgrades (SemVer)                               | Security CVE remediation PRs → security-advisory / human                      |
| `documentation`      | Wrong Diátaxis form, stale paths, missing required docs type, broken cross-refs                                                        | Doc-only fix loops already owned by loop-docs-triage when that loop is active |
| `security`           | Authz gaps, secret-handling smells, unsafe defaults (Sonar Security) — **report only**                                                 | Exploit writing, credential rotation, production incident response            |
| `operational`        | Fragile scripts, missing runbooks, non-reproducible tooling                                                                            | Routine changelog / CI green-up owned by other loops                          |

### Severity

Align with Sonar software-quality severity names; map into report sections:

| Severity (Sonar) | Report section | Rule of thumb                                                                        |
| ---------------- | -------------- | ------------------------------------------------------------------------------------ |
| Blocker          | Critical       | Likely severe unintended consequences (crash, data loss, auth bypass) if left unpaid |
| High             | High-Priority  | High impact; clear remediation path; fix soon                                        |
| Medium / Low     | Watch          | Real debt but weak urgency, needs human judgment, or incomplete evidence             |
| Info             | Noise / Ignore | No expected application impact; marker noise; duplicate                              |

### Nature (optional, Fowler quadrant)

When evidence supports it, add `nature`:

| Nature                 | Meaning                                                  |
| ---------------------- | -------------------------------------------------------- |
| `prudent-deliberate`   | Conscious trade-off for delivery; plan exists to repay   |
| `reckless-deliberate`  | Knew better; chose quick-and-dirty without repay plan    |
| `reckless-inadvertent` | Unaware of good practice; accidental mess                |
| `prudent-inadvertent`  | Clean at ship time; later learning shows a better design |

Omit `nature` when the signal does not support a confident label.

### Detect vs lint

Detect covers mechanical facts the loop can observe without linters: dependency manifests, docs links/staleness, git churn, and code markers. Do **not** restate linter or SAST findings (complexity, style, unused code, naming nits). Markers may appear in reports — usually **Watch** unless evidence shows systemic impact.

### Out of scope

Do not recommend new-technology or tool migration playbooks. Report EOL/deprecation **facts** from detect (`eol_hint`, `stale_doc`) only; do not propose replacement stacks or rewrite plans.

### Category decision order

1. Security-adjacent with blocker/high impact → `security` + Critical/High-Priority
2. Dependency/EOL/version-range hell → `dependency_version`
3. Missing/wrong/stale docs (Diátaxis or broken refs) → `documentation`
4. Missing/weak tests as the primary gap → `test_gap`
5. Boundary / system-shape issue → `architecture`
6. Local maintainability/complexity/naming → `code_quality`
7. Tooling/runbook fragility → `operational`
8. Else → Watch or Noise per severity rules
