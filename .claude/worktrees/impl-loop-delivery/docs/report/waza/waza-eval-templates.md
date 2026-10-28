# Waza Eval Templates

This document provides minimal templates for `eval.yaml` and task YAML files.
Use these as a starting point, then tighten graders for your skill domain.

## Minimal eval.yaml

```yaml
name: my-skill-eval
skill: my-skill
version: "1.0"

config:
  trials_per_task: 5
  timeout_seconds: 180
  parallel: false
  executor: mock
  model: claude-sonnet-4-20250514

metrics:
  - name: task_completion
    weight: 1.0
    threshold: 0.8
    description: Verify task execution completes successfully.

graders:
  - type: code
    name: has_output
    weight: 1.0
    config:
      assertions:
        - "len(output) > 0"
  - type: text
    name: no_error_markers
    weight: 0.5
    config:
      regex_not_match:
        - "(?i)error|failed|exception"
  - type: behavior
    name: bounded_runtime
    weight: 0.5
    config:
      max_tool_calls: 30
      max_tokens: 120000
      max_duration_ms: 180000

  # Optional LLM-as-Judge (Prompt grader)
  # - type: prompt
  #   name: quality_gate
  #   weight: 0.5
  #   config:
  #     prompt: |
  #       Review the response for correctness, clarity, and completeness.
  #       Call set_waza_grade_pass if acceptable; otherwise set_waza_grade_fail with reasons.
  #     model: claude-sonnet-4-20250514

tasks:
  - "evals/tasks/*.yaml"
```

## Minimal Task File

Path example: `evals/tasks/basic.yaml`

```yaml
id: basic-001
name: Basic trigger test
description: Verify the skill is invoked for an intended request.

tags:
  - trigger
  - positive

inputs:
  prompt: "Review this SKILL.md and report failed checks."

expected:
  output_contains:
    - "Checks"
  outcomes:
    - type: task_completed
```

## Template Notes

1. Start with `executor: mock` for fast iteration.
2. Set `trials_per_task: 5` when you plan to use `waza run --baseline` for A/B effect checks.
3. Keep one simple task first, then add coverage.
4. Use `code` + `text` + `behavior` as default graders.
5. Use `prompt` grader only for dedicated quality runs (cost and runtime increase).

## Validation Commands

```bash
# Readiness check
waza check <skill-name>

# Run evaluation
cd .github/skills/<skill-name>
waza run eval.yaml
```

## Waza Command Matrix

This matrix summarizes major Waza commands and how to use them in this repository.

| Category   | Command                                   | Purpose                                                                                     |
| ---------- | ----------------------------------------- | ------------------------------------------------------------------------------------------- |
| Generation | `waza init`                               | Initialize a project workspace (`skills/`, `evals/`, CI workflow).                          |
| Generation | `waza new skill`                          | Create `SKILL.md` and eval scaffold (project/standalone modes).                             |
| Generation | `waza new eval`                           | Scaffold an eval suite from an existing `SKILL.md` trigger definition.                      |
| Generation | `waza new task from-prompt`               | Record a real prompt run and generate a task YAML.                                          |
| Generation | `waza suggest`                            | Use an LLM to suggest test cases, graders, and fixtures (`--dry-run`/`--apply`).            |
| Execution  | `waza run`                                | Run `eval.yaml` with options such as `--parallel`, `--baseline`, `--trials`, and `--cache`. |
| Execution  | `waza grade`                              | Re-grade existing `results.json` artifacts after validator/grader updates.                  |
| Analysis   | `waza compare`                            | Compare multiple results files and show pass-rate/task-level deltas.                        |
| Analysis   | `waza coverage`                           | Generate skill-to-eval coverage grid (Markdown/HTML/JSON).                                  |
| Quality    | `waza check`                              | Readiness check before submission (trigger/metadata/spec/token/eval checks).                |
| Quality    | `waza tokens count`                       | Measure token usage for skills and related Markdown files.                                  |
| Quality    | `waza tokens compare main --threshold 10` | Compare token budget deltas against `main`.                                                 |
| Quality    | `waza tokens suggest`                     | Suggest token reduction opportunities.                                                      |
| Extension  | `waza quality`                            | Advisory LLM-as-Judge quality scoring for skill output.                                     |
| Extension  | `waza dashboard`                          | Start local dashboard server for trends and diff visualization.                             |

## Command Policy In This Repository

For `agent-skills-review`, use this command policy:

- Required checks: `waza check`, `waza run`, `waza tokens count`
- Optional checks: `waza quality`, `waza grade`, `waza compare`, `waza coverage`, `waza tokens compare`, `waza tokens suggest`
- Workflow helper: `bash .github/skills/agent-skills-review/scripts/validate_waza.sh <skill-name>` runs the required checks in one command

Use optional checks when investigation depth is needed (regression analysis, coverage planning, or advisory quality scoring).

## Related Docs

- [waza-quickstart.md](./waza-quickstart.md)
- [waza-capabilities.md](./waza-capabilities.md)
