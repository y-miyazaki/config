#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-execute/lib/validate_agent_report.sh

# Use cases:
# - agent_report_skill_requires_format_check matches fix skills only
# - validate_agent_report accepts canonical output with matching git diff
# - validate_agent_report rejects Deferred path still in branch diff
# - validate_agent_report rejects branch diff path missing from Changes table
# - validate_agent_report rejects legacy Fixes Applied and Outcome sections

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/loop-execute/lib/validate_agent_report.sh"
    TEST_TMP="${BATS_TEST_TMPDIR}/validate_agent_report"
    mkdir -p "${TEST_TMP}"
}

@test "agent_report_skill_requires_format_check matches fix skills only" {
    run agent_report_skill_requires_format_check "docs-updater"
    [ "$status" -eq 0 ]
    run agent_report_skill_requires_format_check "unknown-skill"
    [ "$status" -eq 1 ]
}

@test "validate_agent_report accepts canonical output with matching git diff" {
    local out="${TEST_TMP}/good.txt"
    cat > "${out}" << 'EOF'
# Refactor Result

## Overview

Refactor scan found duplicated diff logic; this run deduplicated one call.

## Summary

### Changes

| Target | What was wrong | What changed |
| ------ | -------------- | ------------ |
| `scripts/ai/sync_skill_lib.sh` | diff ran twice | capture once |

## Verification

| Check | Result |
| ----- | ------ |
| shellcheck | pass |
EOF
    run validate_agent_report "${out}" $'scripts/ai/sync_skill_lib.sh\n' "refactor"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "validate_agent_report rejects Deferred path still in branch diff" {
    local out="${TEST_TMP}/deferred-mismatch.txt"
    cat > "${out}" << 'EOF'
## Overview

Docs drift found stale inventory; updated specification only.

## Summary

### Changes

| File | What was wrong | What changed |
| ---- | -------------- | ------------ |
| docs/reference/specification.md | missing rows | added rows |

### Deferred

| File | Why deferred |
| ---- | ------------ |
| docs/index.md | no inventory table |

## Verification

| Check | Result |
| ----- | ------ |
| markdownlint | pass |
EOF
    run validate_agent_report "${out}" $'docs/reference/specification.md\ndocs/index.md\n' "docs-updater"
    [ "$status" -eq 1 ]
    [[ $output == *"docs/index.md"* ]]
}

@test "validate_agent_report rejects branch diff path missing from Changes table" {
    local out="${TEST_TMP}/missing-change.txt"
    cat > "${out}" << 'EOF'
## Overview

Updated one doc file.

## Summary

### Changes

| File | What was wrong | What changed |
| ---- | -------------- | ------------ |
| docs/a.md | stale | fixed |

## Verification

| Check | Result |
| ----- | ------ |
| markdownlint | pass |
EOF
    run validate_agent_report "${out}" $'docs/a.md\ndocs/b.md\n' "docs-updater"
    [ "$status" -eq 1 ]
    [[ $output == *"docs/b.md"* ]]
}

@test "validate_agent_report rejects legacy Fixes Applied and Outcome sections" {
    local out="${TEST_TMP}/legacy.txt"
    cat > "${out}" << 'EOF'
## Overview

Loop done.

## Summary

### Fixes Applied

| File | Reason | Change |
| ---- | ------ | ------ |
| docs/a.md | stale | fix |

**Outcome:** fixed 1

## Verification

| Check | Result |
| ----- | ------ |
| lint | pass |
EOF
    run validate_agent_report "${out}" $'docs/a.md\n' "docs-updater"
    [ "$status" -eq 1 ]
    [[ $output == *"Fixes Applied"* ]]
    [[ $output == *"Outcome"* ]]
}
