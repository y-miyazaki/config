# Harness Engineering: Go

Go-specific enforcement toolchain across the [harness engineering](harness-engineering.md) layers.

## Layer-by-Layer Configuration

### Layer 1: Agent Instructions

| Package | Instruction | Scope     |
| ------- | ----------- | --------- |
| go      | go          | `**/*.go` |

### Layer 2: Agent Hooks

| PostToolUse (auto-fix) | Stop (validation) |
| ---------------------- | ----------------- |
| —                      | golangci-lint     |

**Design principle**: golangci-lint covers Go formatting via its integrated formatters, so a separate `gofumpt` PostToolUse hook is unnecessary.

### Layer 3: pre-commit

| Hook          | Behavior                                |
| ------------- | --------------------------------------- |
| golangci-lint | Runs with `--fix` on staged `.go` files |

### Layer 4: CI (`ci-go.yaml`)

| Check                     | Purpose                                       |
| ------------------------- | --------------------------------------------- |
| go mod tidy               | Detect uncommitted dependency changes         |
| go test -race             | Run tests with race detector                  |
| golangci-lint (reviewdog) | Inline PR comments for lint violations        |
| govulncheck               | Known vulnerability detection in dependencies |
| trivy (vuln + license)    | Vulnerability and license compliance scanning |
| SBOM (CycloneDX)          | Software bill of materials artifact           |

**Key behaviors**:

- Go lint uses `reviewdog` for inline PR comments on pull requests
- Security scanning (trivy, govulncheck) generates artifacts but does not block merge for informational findings
- SBOM is generated and uploaded as artifact
- License compliance is covered by trivy's `license` scanner

### Layer 6: Setup Automation

No Go-specific init steps beyond `mise install` (which provisions Go and golangci-lint).

## Coverage Matrix

Layers 1–2 apply only when development is AI-assisted. For manual development, Layer 3 (pre-commit) is the first enforcement point.

| Rule Category          | Agent Instructions |    Agent Hooks    | pre-commit |           CI           |
| ---------------------- | :----------------: | :---------------: | :--------: | :--------------------: |
| Code formatting        |         ✓          | ✓ (golangci-lint) |     ✓      |           ✓            |
| Linting                |         ✓          |         ✓         |     ✓      |           ✓            |
| Vulnerability scanning |         —          |         —         |     —      | ✓ (govulncheck, trivy) |
| License compliance     |         —          |         —         |     —      |       ✓ (trivy)        |
| Dependency updates     |         —          |         —         |     —      |      ✓ (Renovate)      |

## Design Decisions

| Decision                           | Rationale                                                                                                                |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| No coverage threshold gate         | Coverage percentage becomes the goal rather than test quality. Instructions guide toward 80% but CI does not enforce it. |
| No `depguard` in shared config     | Project package structures vary too much. Layer violation rules are project-specific.                                    |
| No `go-arch-lint` in shared config | Overkill for Lambda/CLI; only useful for large layered services. Projects add it individually.                           |

## Pending Items

| Item                     | Status      | Rationale for deferral                                       |
| ------------------------ | ----------- | ------------------------------------------------------------ |
| Dependency review action | Pending     | Not yet prioritized; supply chain coverage gap               |
| `go-arch-lint`           | Per-project | Not suitable as shared harness; projects opt in individually |
