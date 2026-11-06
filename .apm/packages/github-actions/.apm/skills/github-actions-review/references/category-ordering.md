# Ordering (ORD)

**ORD-01 (MUST): Alphabetize keys in env/inputs/outputs/permissions/secrets/with maps**

Note: Enforced deterministically by the companion `github-actions-validation` ORD-01 step (map key order check). When that validation output is supplied, do not re-evaluate ORD-01 — mark it Passed or Failed from the validation result and cite it. Evaluate ORD-01 from source only when no validation output is available.

Check: Are map keys sorted alphabetically (A-Z, ASCII order) within each ORD-01 in-scope map listed below?
Why: Inconsistent key ordering adds diff noise and makes change detection harder across workflow files
Fix: Sort keys alphabetically within each listed map.

In-scope maps (any `env`, `inputs`, `outputs`, `permissions`, `secrets`, or `with` map in workflow or composite action YAML), for example:

- Workflow and job: `env`, `outputs`, `permissions`, `secrets`, `with`
- Reusable workflow declaration: `on.workflow_call.inputs`, `on.workflow_call.outputs`, `on.workflow_call.secrets`
- Composite `action.yml`: `inputs`, `outputs`; per-step `env`, `with`

Out of scope:

- `jobs` map keys and `on` trigger keys — keep semantic order (pipeline stage, event priority)
- `steps` — ordered lists, not key maps
