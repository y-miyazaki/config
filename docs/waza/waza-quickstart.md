# Waza Quickstart

This quickstart shows the minimum workflow to evaluate a skill with Waza.
Use this page when you want a fast setup without reading all details.

## Overview

Goal:
- Run readiness checks for a skill.
- Run an evaluation suite from `eval.yaml`.

## Prerequisites

- Waza CLI is installed.
- Target skill has `SKILL.md`.
- Evaluation files exist:
  - `eval.yaml`
  - at least one file in `evals/tasks/`

## Quick Steps

1. Move to the skills root.

```bash
cd .github/skills
```

2. Check readiness.

```bash
waza check <skill-name>
```

3. Move to the target skill.

```bash
cd <skill-name>
```

4. Run evaluation.

```bash
waza run eval.yaml
```

## Minimal Success Criteria

- `waza check` reports valid spec and no schema errors.
- `waza run eval.yaml` finds at least one task and completes.

## Common Failures

1. No task files matched.

Symptom:
- `no test files matched patterns: [evals/tasks/*.yaml]`

Fix:
- Add at least one task file under `evals/tasks/`.
- Confirm the glob in `eval.yaml` matches the file path.

2. Eval schema error.

Fix:
- Ensure required sections exist in `eval.yaml`.
- Compare with examples in [waza-eval-templates.md](./waza-eval-templates.md).

## Next Reading

- [waza-capabilities.md](./waza-capabilities.md)
- [waza-eval-templates.md](./waza-eval-templates.md)
