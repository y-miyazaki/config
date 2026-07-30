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
