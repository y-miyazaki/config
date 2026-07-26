#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .apm/packages/common/.apm/skills/agent-skills-review/scripts/validate.sh
#
# Use cases:
# - check_description_quality passes without literal "Use when"
# - check_description_quality fails on "Use for" prefix
# - check_description_quality fails on implementation instructions
# - check_reference_triggers passes allowlist triggers
# - check_reference_triggers fails on non-allowlist triggers

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    WORKSPACE_ROOT="$(bats_workspace_root)"
    VALIDATE_SCRIPT="${WORKSPACE_ROOT}/.apm/packages/common/.apm/skills/agent-skills-review/scripts/validate.sh"
    FIXTURE_ROOT="${BATS_TEST_TMPDIR}/.cursor/skills/test-fixture"
    mkdir -p "${FIXTURE_ROOT}/references"
    touch "${FIXTURE_ROOT}/references/common-checklist.md"
    touch "${FIXTURE_ROOT}/references/common-output-format.md"
    # shellcheck disable=SC1090,SC1091
    source "${VALIDATE_SCRIPT}"
}

reset_checks() {
    check_names=()
    check_statuses=()
    check_details_json=()
}

write_fixture_skill() {
    local description="$1"
    local ref_guide="${2:-$(
        cat << 'EOF'
- [common-checklist.md](references/common-checklist.md) (always read)
- [common-output-format.md](references/common-output-format.md) (always read)
EOF
    )}"

    cat > "${FIXTURE_ROOT}/SKILL.md" << EOF
---
name: test-fixture
description: >-
  ${description}
license: Apache-2.0
metadata:
  author: test
  version: "1.0.0"
---

## Input

- Test input

## Output Specification

- Test output

## Execution Scope

### USE FOR:

- Testing

## Reference Files Guide

${ref_guide}

## Workflow

1. Test step.
EOF
    SKILL_FILE="$(realpath "${FIXTURE_ROOT}/SKILL.md")"
}

@test "check_description_quality passes without literal Use when" {
    reset_checks
    write_fixture_skill "Validates fixture skills when tests run."

    check_description_quality > /dev/null
    [ "${check_statuses[0]}" = "PASS" ]
}

@test "check_description_quality fails on Use for prefix" {
    reset_checks
    write_fixture_skill "Use for testing only."

    check_description_quality > /dev/null
    [ "${check_statuses[0]}" = "FAIL" ]
    [[ ${check_details_json[0]} == *"not third person"* ]]
}

@test "check_description_quality fails on implementation instructions" {
    reset_checks
    write_fixture_skill "Always use this skill for troubleshooting."

    check_description_quality > /dev/null
    [ "${check_statuses[0]}" = "FAIL" ]
    [[ ${check_details_json[0]} == *"implementation instructions"* ]]
}

@test "check_reference_triggers passes allowlist triggers" {
    reset_checks
    write_fixture_skill "Validates reference triggers." "$(
        cat << 'EOF'
- [common-checklist.md](references/common-checklist.md) (always read)
- [common-output-format.md](references/common-output-format.md) (always read)
- [category-scope.md](references/category-scope.md) (read on automation path)
- [common-troubleshooting.md](references/common-troubleshooting.md) (read on failure)
EOF
    )"

    check_reference_triggers > /dev/null
    [ "${check_statuses[0]}" = "PASS" ]
}

@test "check_reference_triggers fails on non-allowlist triggers" {
    reset_checks
    write_fixture_skill "Validates reference triggers." "$(
        cat << 'EOF'
- [common-checklist.md](references/common-checklist.md) (always read)
- [common-output-format.md](references/common-output-format.md) (always read)
- [category-scope.md](references/category-scope.md) (read on automation)
EOF
    )"

    check_reference_triggers > /dev/null
    [ "${check_statuses[0]}" = "FAIL" ]
    [[ ${check_details_json[0]} == *"non-allowlist trigger"* ]]
}
