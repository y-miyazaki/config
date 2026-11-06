# Terraform Validation Checklist

## Execution Order

`scripts/validate.sh` runs these tools in this order and continues after a failing tool (no fail-fast); the exit code is non-zero when any tool failed:

1. `tflint` — linting and provider-specific rule checks
2. `terraform validate` — HCL syntax and schema validation
3. `terraform fmt` — formatting compliance (rewrites only with `--fix`)
4. Argument order check (ORD-01) — only with `--check-order`; otherwise report `⊘ Skipped`
5. `trivy config` — security misconfiguration scan

`terraform`, `tflint`, and `trivy` are required (`python3` with `--check-order`); the script stops before any check when one is missing.

## terraform fmt (FMT)

- FMT-01 (SHOULD): All .tf files are formatted per `terraform fmt` standard
- FMT-02 (SHOULD): Consistent indentation (2-space) throughout
- FMT-03 (SHOULD): Argument alignment follows canonical style

## terraform validate (SYNTAX)

- SYNTAX-01 (SHOULD): HCL parses without errors
- SYNTAX-02 (SHOULD): All referenced variables and modules resolve
- SYNTAX-03 (SHOULD): Resource and data source schemas are valid
- SYNTAX-04 (SHOULD): No missing required arguments

## Argument order (ORD)

- ORD-01 (MUST): Argument keys inside resource/module/data/locals blocks are alphabetically ordered (checked only with `--check-order`)

## tflint (LINT)

- LINT-01 (SHOULD): All enabled rules pass with zero findings
- LINT-02 (SHOULD): Provider-specific rules enabled in `.tflint.hcl` pass
- LINT-03 (SHOULD): No deprecated resource types or argument names
- LINT-04 (SHOULD): Custom ruleset (`.tflint.hcl`) compliance verified

## trivy config (SEC)

- SEC-01 (SHOULD): No HIGH or CRITICAL severity misconfigurations
- SEC-02 (SHOULD): No hardcoded secrets detected
- SEC-03 (SHOULD): Access policies comply with least-privilege principles
- SEC-04 (SHOULD): Suppressed findings have documented justifications

## Pass Criteria

- All tools exit with code 0
- No errors or warnings above configured thresholds
- See [common-output-format.md](common-output-format.md) for output structure
