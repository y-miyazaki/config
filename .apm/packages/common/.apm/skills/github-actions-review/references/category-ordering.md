## Ordering (ORD)

**ORD-01 (MUST): Alphabetical Key Ordering**

Note: Not enforced by `github-actions-validation` (actionlint, ghalint, zizmor). Enforce during edits via companion github-actions-workflow rules (ORD-01). Omit from review output unless workflow YAML key ordering is the primary finding.

Check: Are map keys sorted alphabetically (A-Z) within each ORD-01 block: workflow and job `env`, `permissions`, `with`, and `secrets`; `on.workflow_call.inputs` and `on.workflow_call.secrets`; composite `action.yml` `inputs` and `outputs`; per-step `with` and `env`? <!-- pragma: allowlist secret -->
Why: Inconsistent key ordering adds diff noise and makes change detection harder across workflow files
Fix: Sort keys alphabetically within each listed block; see companion github-actions-workflow rules (ORD-01) for the full block list and out-of-scope maps
