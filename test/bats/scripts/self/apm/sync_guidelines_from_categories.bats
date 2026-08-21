#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

bats_require_minimum_version 1.5.0

# Tests for scripts/self/apm/sync_guidelines_from_categories.pl
#
# Use cases:
# - sync emits ItemID title lines under ## Guidelines
# - sync omits Check: children from always-on Guidelines (thin instructions)
# - sync regenerates common-checklist.md from category rule titles
# - sync appends Code Modification Guidelines when configured for the skill

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

SYNC_SCRIPT="$(bats_workspace_root)/scripts/self/apm/sync_guidelines_from_categories.pl"

setup() {
    FIXTURE_ROOT="${BATS_TEST_TMPDIR}/sync-guidelines-root"
    rm -rf "${FIXTURE_ROOT}"
    REF_DIR="${FIXTURE_ROOT}/.apm/packages/common/.apm/skills/agent-skills-review/references"
    INSTR="${FIXTURE_ROOT}/.apm/packages/common/.apm/instructions/agent-skills.instructions.md"
    mkdir -p "${REF_DIR}" "$(dirname "${INSTR}")"

    cat > "${REF_DIR}/category-anti-patterns.md" << 'EOF'
# Anti-Patterns (AP)

**AP-01 (SHOULD): Fixture anti-pattern rule**

Check: Is the anti-pattern rule deferred until after domain sections?
Why: STRUCT-05 requires domain rules before Anti-Patterns.
Fix: Order category files with AP sections last in sync output.
EOF

    cat > "${REF_DIR}/category-structure.md" << 'EOF'
# Structural Checks (S)

**S-01 (MUST): SKILL.md has the five required ## sections**

Check: Does SKILL.md have all 5 required sections at ## heading level?
Why: Complete structure ensures reviewability.
Fix: Add missing ## sections.

**S-99 (SHOULD): Fixture-only secondary rule**

Check: Is the secondary rule present for checklist coverage?
Why: Ensures multiple rules sync.
Fix: Keep the rule.
EOF

    cat > "${REF_DIR}/common-checklist.md" << 'EOF'
# Agent Skills Review Checklist

## Structural Checks (S)
- S-OLD (MUST): stale entry replaced by sync
EOF

    cat > "${INSTR}" << 'EOF'
# Agent Skills Instructions

## Scope

- Scope covers skill authoring.

## Standards

Document non-obvious rules only.

## Guidelines

### Structural Checks (S)
- S-OLD (MUST): stale guideline replaced by sync

### Code Modification Guidelines

- stale code mod bullet

## Testing and Validation

On-demand validation: see agent-skills-review skill SKILL.md.

## Security Guidelines

- Do not embed secrets.
EOF
}

@test "sync_guidelines parses H1 category section headers" {
    run bash -c "cd '${FIXTURE_ROOT}' && perl '${SYNC_SCRIPT}'"
    [ "$status" -eq 0 ]
    grep -q 'S-01 (MUST): SKILL.md has the five required ## sections' "${REF_DIR}/common-checklist.md"
    grep -q '## Structural Checks (S)' "${REF_DIR}/common-checklist.md"
}

@test "sync_guidelines emits ItemID titles without Check children" {
    run bash -c "cd '${FIXTURE_ROOT}' && perl '${SYNC_SCRIPT}'"
    [ "$status" -eq 0 ]
    [[ ${output} == *"sync completed"* ]]

    # Thin Guidelines: ItemID titles present, Check: absent between Guidelines and Testing
    grep -q 'S-01 (MUST): SKILL.md has the five required ## sections' "${INSTR}"
    grep -q 'S-99 (SHOULD): Fixture-only secondary rule' "${INSTR}"
    guidelines_block="$(awk '/^## Guidelines$/{p=1;next} /^## /{p=0} p' "${INSTR}")"
    [[ ${guidelines_block} != *"Check:"* ]]

    # Checklist regenerated from category titles
    grep -q 'S-01 (MUST): SKILL.md has the five required ## sections' "${REF_DIR}/common-checklist.md"
    run ! grep -q 'S-OLD' "${REF_DIR}/common-checklist.md"

    # Code Modification Guidelines retained from script defaults for agent-skills-review
    grep -q 'Automate deterministic checks' "${INSTR}"
}
@test "sync_guidelines places anti-patterns after domain sections" {
    run bash -c "cd '${FIXTURE_ROOT}' && perl '${SYNC_SCRIPT}'"
    [ "$status" -eq 0 ]

    guidelines_block="$(awk '/^## Guidelines$/{p=1;next} /^## /{p=0} p' "${INSTR}")"
    s_line="$(printf '%s\n' "${guidelines_block}" | grep -n '### Structural Checks (S)' | cut -d: -f1)"
    ap_line="$(printf '%s\n' "${guidelines_block}" | grep -n '### Anti-Patterns (AP)' | cut -d: -f1)"
    cmg_line="$(printf '%s\n' "${guidelines_block}" | grep -n '### Code Modification Guidelines' | cut -d: -f1)"

    [ -n "${s_line}" ]
    [ -n "${ap_line}" ]
    [ -n "${cmg_line}" ]
    [ "${s_line}" -lt "${ap_line}" ]
    [ "${ap_line}" -lt "${cmg_line}" ]
}
@test "go-review excludes test categories from go.instructions Guidelines" {
    local root="${BATS_TEST_TMPDIR}/go-split-root"
    local ref="${root}/.apm/packages/go/.apm/skills/go-review/references"
    local instr="${root}/.apm/packages/go/.apm/instructions/go.instructions.md"
    rm -rf "${root}"
    mkdir -p "${ref}" "$(dirname "${instr}")"

    cat > "${ref}/category-architecture.md" << 'EOF'
# Architecture (ARCH)

**ARCH-01 (SHOULD): Fixture architecture rule**

Check: Is the architecture rule present?
Why: Domain rules belong in go.instructions Guidelines.
Fix: Keep ARCH in instructions output.
EOF

    cat > "${ref}/category-testing.md" << 'EOF'
# Testing (TEST)

**TEST-01 (SHOULD): Fixture test rule**

Check: Is the test rule excluded from go.instructions?
Why: Test rules belong in go-test.instructions only.
Fix: Exclude category-testing.md from go.instructions sync.
EOF

    cat > "${ref}/category-test-anti-patterns.md" << 'EOF'
# Test Anti-Patterns (TAP)

**TAP-01 (SHOULD): Fixture tap rule**

Check: Is TAP excluded from go.instructions?
Why: TAP belongs in go-test.instructions only.
Fix: Exclude category-test-anti-patterns.md from go.instructions sync.
EOF

    cat > "${ref}/common-checklist.md" << 'EOF'
# Go Review Checklist
EOF

    cat > "${instr}" << 'EOF'
# Go Development Instructions

## Scope

- Scope covers Go source.

## Standards

## Guidelines

### Stale

- STALE (MUST): replaced by sync

## Testing and Validation

On-demand validation: see go-validation skill SKILL.md.

## Security Guidelines

- No secrets.
EOF

    run bash -c "cd '${root}' && perl '${SYNC_SCRIPT}'"
    [ "$status" -eq 0 ]

    guidelines_block="$(awk '/^## Guidelines$/{p=1;next} /^## /{p=0} p' "${instr}")"
    [[ ${guidelines_block} == *"ARCH-01 (SHOULD): Fixture architecture rule"* ]]
    [[ ${guidelines_block} != *"TEST-01"* ]]
    [[ ${guidelines_block} != *"TAP-01"* ]]

    grep -q 'TEST-01 (SHOULD): Fixture test rule' "${ref}/common-checklist.md"
    grep -q 'TAP-01 (SHOULD): Fixture tap rule' "${ref}/common-checklist.md"
}

@test "shell-script excludes TEST-00 from Guidelines while keeping review checklist" {
    local root="${BATS_TEST_TMPDIR}/shell-test00-root"
    local ref="${root}/.apm/packages/shell-script/.apm/skills/shell-script-review/references"
    local instr="${root}/.apm/packages/shell-script/.apm/instructions/shell-script.instructions.md"
    rm -rf "${root}"
    mkdir -p "${ref}" "$(dirname "${instr}")"

    cat > "${ref}/category-testing.md" << 'EOF'
# Testing (TEST)

**TEST-00 (MUST): Fixture pairing rule**

Check: Is the pairing rule excluded from shell-script Guidelines?
Why: Pairing belongs in Scope prose only.
Fix: Exclude TEST-00 from synced Guidelines.

**TEST-01 (SHOULD): Fixture ordering rule**

Check: Is TEST-01 still synced into Guidelines?
Why: Non-pairing test rules remain in Guidelines.
Fix: Keep TEST-01 in sync output.
EOF

    cat > "${ref}/common-checklist.md" << 'EOF'
# Shell Script Review Checklist
EOF

    cat > "${instr}" << 'EOF'
# Shell Script Instructions

## Scope

- When adding or materially changing a shell script or sourced library, add or update the matching Bats suite in the same change (MUST).

## Standards

## Guidelines

### Stale

- STALE (MUST): replaced by sync

## Testing and Validation

On-demand validation: see shell-script-validation skill SKILL.md.

## Security Guidelines

- No secrets.
EOF

    run bash -c "cd '${root}' && perl '${SYNC_SCRIPT}'"
    [ "$status" -eq 0 ]

    guidelines_block="$(awk '/^## Guidelines$/{p=1;next} /^## /{p=0} p' "${instr}")"
    [[ ${guidelines_block} != *"TEST-00"* ]]
    [[ ${guidelines_block} == *"TEST-01 (SHOULD): Fixture ordering rule"* ]]
    grep -q 'TEST-00 (MUST): Fixture pairing rule' "${ref}/common-checklist.md"
}

@test "sync_guidelines preserves MUST levels from thin Guidelines bullets" {
    local root="${BATS_TEST_TMPDIR}/thin-level-root"
    local ref="${root}/.apm/packages/common/.apm/skills/agent-skills-review/references"
    local instr="${root}/.apm/packages/common/.apm/instructions/agent-skills.instructions.md"
    rm -rf "${root}"
    mkdir -p "${ref}" "$(dirname "${instr}")"

    cat > "${ref}/category-structure.md" << 'EOF'
# Structural Checks (S)

**S-01: Fixture rule title missing inline level**
EOF

    cat > "${ref}/common-checklist.md" << 'EOF'
# Agent Skills Review Checklist
EOF

    cat > "${instr}" << 'EOF'
# Agent Skills Instructions

## Scope

- Scope covers skill authoring.

## Standards

Document non-obvious rules only.

## Guidelines

### Structural Checks (S)
- S-01 (MUST): Fixture rule with thin bullet level

## Testing and Validation

On-demand validation: see agent-skills-review skill SKILL.md.

## Security Guidelines

- Do not embed secrets.
EOF

    run bash -c "cd '${root}' && perl '${SYNC_SCRIPT}'"
    [ "$status" -eq 0 ]
    grep -q 'S-01 (MUST): Fixture rule title missing inline level' "${ref}/category-structure.md"
}
