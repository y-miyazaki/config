#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-execute/lib/loop.sh helpers

# Use cases:
# - parse_outcome_override_from_agent_output detects bold Outcome watch
# - parse_outcome_override_from_agent_output detects plain Outcome deferred
# - parse_outcome_override_from_agent_output detects no actionable failures
# - parse_outcome_override_from_agent_output ignores fix outcomes

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    # loop.sh pulls in the full execute lib stack via _init.
    bats_source_rel ".github/actions/loop-execute/lib/loop.sh"
}

@test "parse_outcome_override_from_agent_output detects bold Outcome watch" {
    run parse_outcome_override_from_agent_output $'## Summary\n- **Outcome:** watch\n'
    [ "$status" -eq 0 ]
}

@test "parse_outcome_override_from_agent_output detects plain Outcome deferred" {
    run parse_outcome_override_from_agent_output $'Outcome: deferred — infra flake\n'
    [ "$status" -eq 0 ]
}

@test "parse_outcome_override_from_agent_output detects no actionable failures" {
    run parse_outcome_override_from_agent_output $'- **Outcome:** no actionable failures\n'
    [ "$status" -eq 0 ]
}

@test "parse_outcome_override_from_agent_output ignores fix outcomes" {
    run parse_outcome_override_from_agent_output $'- **Outcome:** Fixed MD001 in docs/ci-sweeper-test.md\n'
    [ "$status" -ne 0 ]
}
