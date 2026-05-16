# Waza Capabilities In This Repository

This document summarizes what Waza can do, what it cannot do by itself, and how to use it effectively in this repository.
The summary is based on the official Waza documentation and command behavior verified in this workspace.

## Overview

Waza is an evaluation framework for AI agent skills.
It helps validate whether a skill is invoked as intended and whether its outputs satisfy objective quality checks.

Primary value:
- Turn skill quality checks into repeatable YAML-based evaluations.
- Separate deterministic checks from subjective checks.
- Run evaluation loops quickly with `mock` and then validate with a real executor.

## Prerequisites

- Waza CLI installed and available on PATH.
- A skill directory containing `SKILL.md`.
- Evaluation files:
  - `eval.yaml`
  - `evals/tasks/*.yaml`
  - Optional fixtures under `evals/fixtures/`

Recommended version hygiene:
- Check versions before running evaluations:

```bash
waza --version
```

## Architecture And Design

Waza evaluates a skill using three layers:

1. Inputs:
- `eval.yaml`: suite-level config, metrics, graders, task globs.
- task files: scenario-level inputs/expectations.
- fixtures: optional test inputs.

2. Executor:
- `mock`: fast feedback loop for grader and task design.
- `copilot-sdk`: real model execution.

3. Outputs:
- Grader results per task.
- Aggregated scores and pass/fail summary.

Design guidance from the article and docs:
- Keep objective graders (text/file/diff/behavior) as the core.
- Use subjective prompt-based grading only where objective checks are insufficient.

## What Waza Can Do

- Validate readiness of a skill package with `waza check`.
- Enforce token budgets and spec compliance in readiness output.
- Detect whether `eval.yaml` exists and whether schema is valid.
- Execute evaluation suites with `waza run eval.yaml`.
- Score tasks using configured graders and metrics.
- Support iterative improvement loops for skill quality.
- Provide token analysis and optimization hints (`waza tokens ...`).

Useful commands:

```bash
# Readiness and static quality checks
waza check <skill-path>

# Execute evaluation suite
waza run eval.yaml

# Token analysis helpers
waza tokens count <path>
waza tokens suggest <path>
```

For this repository workflow, use these checks as default:
- Required: `waza check <skill-path>`, `waza run eval.yaml`, `waza tokens count <SKILL.md>`
- Optional: `waza quality <skill-path>` for advisory content feedback
- Optional: `waza grade eval.yaml --results <results.json>` only when grading saved run artifacts

## What Waza Does Not Do Alone

- It does not automatically create good task files from poor requirements.
- It does not replace domain-specific lint/test/build pipelines.
- It does not guarantee business correctness without well-designed graders.
- It does not auto-select an executor via CLI flag in all versions; executor is typically controlled in `eval.yaml`.
- It does not infer missing task files when your glob pattern matches nothing.

Example failure pattern seen in this repo:
- `no test files matched patterns: [evals/tasks/*.yaml]`
- Fix: create at least one valid task YAML under `evals/tasks/`.

## Implementation Details In This Repository

Current usage around `agent-skills-review`:

- Skill readiness:

```bash
cd .github/skills
waza check agent-skills-review
```

- Eval run:

```bash
cd .github/skills/agent-skills-review
waza run eval.yaml
```

- Required structure to avoid empty suite errors:
- `eval.yaml` must include a valid task glob.
- The glob must match at least one task file.

Recommended working loop:
1. Run `waza check` for packaging/readiness issues.
2. Fix hard errors first (schema, missing files, token limit).
3. Run `waza run eval.yaml` and inspect task-level results.
4. Tighten graders and task data iteratively.

## Testing And Validation

Documentation and workflow validation commands:

```bash
# Validate markdown docs in this repository
bash .github/skills/markdown-validation/scripts/validate.sh

# Validate target skill readiness
cd .github/skills
waza check agent-skills-review

# Run target evaluation suite
cd .github/skills/agent-skills-review
waza run eval.yaml
```

## Troubleshooting

Common issues and fixes:

1. Evaluation suite found but run fails immediately.
- Cause: task glob in `eval.yaml` matches zero files.
- Action: add task files under the configured path.

2. `waza check` passes spec but remains low readiness.
- Cause: advisory/content quality findings in `SKILL.md`.
- Action: improve description triggers, routing clarity, examples, and token budget fit.

3. Schema errors in `eval.yaml`.
- Cause: missing required sections (for example metrics in current toolchain expectations).
- Action: align with official eval spec examples and rerun.

## References

- Waza repository: https://github.com/microsoft/waza
- Waza docs site: https://microsoft.github.io/waza/

## Related Docs In This Repository

- [waza-quickstart.md](./waza-quickstart.md)
- [waza-eval-templates.md](./waza-eval-templates.md)
