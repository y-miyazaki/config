# Loop Engineering Documentation Maintenance

Repository maintainer guide for loop platform and caller documentation. The distributable **docs-updater** skill carries generic deduplication rules in `category-documentation-maintenance.md`; this page is the Loop Engineering canonical map and trigger table for **this repo only**.

Reader map (nesting vs per-loop vs contracts): [index.md](index.md). Do not add a fourth uncategorized design page at this folder root; put per-loop pages under `workflows/` and cross-cutting contracts in Layer C.

## Canonical sources (edit here only)

| Topic                             | Canonical path                                                                                                                   |
| --------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| Invariants, retry, phase contract | [loop-engineering-design.md](loop-engineering-design.md)                                                                         |
| Targets, state, caller input map  | [multi-branch-loops-design.md](multi-branch-loops-design.md)                                                                     |
| Job graph, triggers, finalize     | [loop-caller-workflows-design.md](loop-caller-workflows-design.md)                                                               |
| Reusable caller, profiles         | [loop-caller-reusable-design.md](loop-caller-reusable-design.md)                                                                 |
| Caller `with:` keys               | [workflows/loop-caller-inputs-reference.md](workflows/loop-caller-inputs-reference.md)                                           |
| Per-loop behavior                 | [Workflow Design Documents](multi-branch-loops-design.md#workflow-design-documents) (`workflows/loop-<name>-workflow-design.md`) |
| PR body contract                  | [loop-pr-body-skill-contract.md](loop-pr-body-skill-contract.md)                                                                 |

## Trigger: when to update loop docs

Update affected canonical docs in the **same change** when modifying:

| Changed path pattern                                                                                     | Update                                                                                                                      |
| -------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| `.github/workflows/on-loop-*.yaml`                                                                       | Matching `loop-<name>-workflow-design.md`; inputs reference if keys change                                                  |
| `.github/workflows/ci-loop-caller*.yaml`, `ci-loop-agent.yaml`                                           | `loop-caller-workflows-design.md`, `loop-caller-reusable-design.md`                                                         |
| `.github/actions/loop-*`                                                                                 | [specification.md](../../reference/specification.md) if I/O changes; `loop-engineering-design.md` if phase contract changes |
| `.apm/packages/<pkg>/.apm/skills/<loop-skill>/`                                                          | Skill `references/` + matching per-loop workflow design                                                                     |
| `scripts/self/apm/check_loop_pr_body_contract.sh`                                                        | `loop-pr-body-skill-contract.md`                                                                                            |
| `.apm/packages/.../skills/<loop-skill>/references/category-pr-body-links.md`                             | Matching per-loop workflow design if link behavior changes; contract doc if structural rules change                         |
| `.apm/packages/.../skills/<loop-skill>/assets/pr-body-template*.md` or `category-automation-envelope.md` | Matching per-loop workflow design if behavior changes; contract doc if structural rules change                              |

## Reject (do not leave in docs)

- Duplicate job graphs — link to [loop-engineering-design.md — Workflow Architecture Diagram](loop-engineering-design.md#workflow-architecture-diagram) instead
- Stale `env:` / `LOOP_*` caller config without mapping to `ci-loop-caller` `with:` inputs
- `pull_requests` input name — canonical is `pr_enabled`
- Semantic `findings[]` attributed to detect scripts — detect emits mechanical facts only ([CONTEXT.md](CONTEXT.md))
- Separate finalize matrix job under caller — finalize runs inside `ci-loop-agent`
- "SHA advances on REJECT" — `last_sha` uses `metadata` mode on REJECT; see Retry Policy in [loop-engineering-design.md](loop-engineering-design.md)

## Architecture diagram rule

Draw the full stack once in [loop-engineering-design.md — Workflow Architecture Diagram](loop-engineering-design.md#workflow-architecture-diagram). Other docs link to that section instead of redrawing ASCII or mermaid graphs. Shared platform checklist lives in [multi-branch-loops-design.md](multi-branch-loops-design.md#shared-platform-checklist-all-loops).
