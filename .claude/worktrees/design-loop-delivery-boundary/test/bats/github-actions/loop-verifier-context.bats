#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2154

# Tests for .github/actions/lib/loop/verifier_context.sh
#
# Use cases:
# - explicit verifier_context field is returned as-is
# - failures shape renders CI Failures markdown
# - unknown shape returns empty string

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

VERIFIER_CONTEXT_LIB="$(bats_workspace_root)/.github/actions/lib/loop/verifier_context.sh"

setup() {
    # shellcheck disable=SC1090,SC1091
    source "${VERIFIER_CONTEXT_LIB}"
}

@test "build_verifier_context_from_result returns explicit verifier_context" {
    run build_verifier_context_from_result '{"verifier_context":"custom context"}'
    [ "$status" -eq 0 ]
    [ "$output" = "custom context" ]
}

@test "build_verifier_context_from_result renders failures markdown" {
    run build_verifier_context_from_result '{"failures":[{"workflow_name":"ci","workflow_run_id":"1","job_name":"test","head_branch":"main","failure_type":"test","log_excerpt":"boom"}]}'
    [ "$status" -eq 0 ]
    [[ $output == *"## CI Failures"* ]]
    [[ $output == *"**ci** run 1 job test"* ]]
    [[ $output == *"boom"* ]]
}

@test "build_verifier_context_from_result returns empty for unknown shape" {
    run build_verifier_context_from_result '{"foo":"bar"}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
