## Verification (V4)

Stack-specific gates. Prefer existing `*-validation` skills named in `## Instructions` (A').

### Stack table (v1)

| Stack          | Prefer                                                     | If missing foundation                                                 |
| -------------- | ---------------------------------------------------------- | --------------------------------------------------------------------- |
| Go             | `go test` for touched packages                             | Add characterization `*_test.go` for existing behavior, then refactor |
| Shell          | `shellcheck` + bats when suite exists                      | Add/extend bats when domain rules require TEST-00                     |
| Terraform      | `terraform fmt/validate`, tflint; no unintended plan drift | Do not invent terratest in Phase 1                                    |
| GitHub Actions | actionlint / workflow validation skills                    | Reuse validation skills via A'; do not invent new product behavior    |
| Unsupported    | —                                                          | Watch / skip — do not invent tests                                    |

### Characterization tests

- Capture **existing** behavior only — do not expand into feature specs
- Add tests/checks before or in the same change as the refactor when the stack is supported and no net exists
- After tests are green on current behavior, apply O1/O2 depth (local or same-package), then re-run gates

### Downgrade (V4)

- If the gate is insufficient for a same-package move (O2) → apply **local-only (O1)** or Watch
- Record the choice under Characterization / Gates **Downgrade** using plain labels (`O2 same-package move → O1 local structure` or Watch reason)
- Lint/SAST may appear inside a stack gate; their findings must **not** become the primary reason to select or expand a target

### Instructions (A')

- Read `## Instructions` for named validation skills and commands
- Do not hardcode consumer skill package paths into this reference
