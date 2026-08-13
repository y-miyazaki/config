#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-entity-detect/lib/{detect,outputs}.sh
#
# Use cases:
# - resolve_detect_script_path pins relative and absolute detect scripts
# - shrink_entity_matrix_for_output trims verifier_context from matrix output
# - write_entity_detect_outputs writes should_run and target_matrix to GITHUB_OUTPUT
# - main skips when daily budget is exceeded
# - main builds target matrix from a successful entity detect script

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

ENTITY_DETECT_LIB="$(bats_workspace_root)/.github/actions/loop-entity-detect/lib/detect.sh"
ENTITY_DETECT_INIT="$(bats_workspace_root)/.github/actions/loop-entity-detect/lib/_init.sh"

entity_detect_write_mock_script() {
    local path="$1"
    local payload="$2"
    cat > "${path}" << EOF
#!/bin/bash
printf '%s\n' '${payload}'
EOF
    chmod +x "${path}"
}

setup() {
    # shellcheck disable=SC1090,SC1091
    source "${ENTITY_DETECT_INIT}"
    # shellcheck disable=SC1090,SC1091
    source "${ENTITY_DETECT_LIB}"
    GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/github_output"
    : > "${GITHUB_OUTPUT}"
    export GITHUB_OUTPUT
    export RUNNER_TEMP="${BATS_TEST_TMPDIR}/runner"
    mkdir -p "${RUNNER_TEMP}"
}

@test "resolve_detect_script_path resolves relative detect script" {
    entity_detect_write_mock_script "${BATS_TEST_TMPDIR}/detect.sh" '{"status":"ok","skip":true,"result":{}}'
    (
        cd "${BATS_TEST_TMPDIR}"
        DETECT_SCRIPT="detect.sh"
        resolve_detect_script_path
        [[ ${DETECT_SCRIPT} == "${BATS_TEST_TMPDIR}/detect.sh" ]]
    )
}

@test "resolve_detect_script_path fails when script is missing" {
    DETECT_SCRIPT="${BATS_TEST_TMPDIR}/missing-detect.sh"
    run resolve_detect_script_path
    [ "$status" -eq 1 ]
    [[ $output == *"not found"* ]]
}

@test "shrink_entity_matrix_for_output clears verifier_context" {
    local full='[{"handoff_key":"entity:issue:1","prompt":"p","target_json":{"to":{"branch":"main"}},"verifier_context":"secret"}]'
    run shrink_entity_matrix_for_output "${full}"
    [ "$status" -eq 0 ]
    run jq -e 'length == 1 and .[0].verifier_context == "" and .[0].handoff_key == "entity:issue:1"' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "write_entity_detect_outputs writes should_run and target_matrix" {
    export DELIVERY="none"
    write_entity_detect_outputs "true" "" '[{"handoff_key":"entity:issue:2"}]'
    grep -q '^should_run=true$' "${GITHUB_OUTPUT}"
    grep -q '^skip_reason=$' "${GITHUB_OUTPUT}"
    grep -q '^delivery=none$' "${GITHUB_OUTPUT}"
    grep -q 'entity:issue:2' "${GITHUB_OUTPUT}"
}

@test "main skips when daily run budget is exceeded" {
    entity_detect_write_mock_script "${BATS_TEST_TMPDIR}/detect.sh" '{"status":"ok","skip":false,"result":{"handoff_key":"entity:issue:1"}}'
    printf '%s\n' '{}' > "${BATS_TEST_TMPDIR}/budget.json"
    printf '%s\n' "{\"loop_name\":\"issue-triage\",\"run_id\":\"$(date -u +%Y-%m-%d)T12:00:00Z\"}" > "${BATS_TEST_TMPDIR}/run-log.md"
    run env \
        DETECT_SCRIPT="${BATS_TEST_TMPDIR}/detect.sh" \
        LOOP_NAME="issue-triage" \
        SKILL_NAME="issue-triage" \
        BUDGET_FILE="${BATS_TEST_TMPDIR}/budget.json" \
        BUDGET_MAX_RUNS_PER_DAY="1" \
        RUN_LOG_FILE="${BATS_TEST_TMPDIR}/run-log.md" \
        bash "${ENTITY_DETECT_LIB}"
    [ "$status" -eq 0 ]
    grep -q '^should_run=false$' "${GITHUB_OUTPUT}"
    grep -q '^skip_reason=budget$' "${GITHUB_OUTPUT}"
}

@test "main publishes target matrix for successful entity detect" {
    entity_detect_write_mock_script "${BATS_TEST_TMPDIR}/detect.sh" \
        '{"status":"ok","skip":false,"result":{"handoff_key":"entity:issue:9","issue_number":9,"event_name":"issues","event_action":"opened"},"verifier_context":"Issue #9"}'
    run env \
        DETECT_SCRIPT="${BATS_TEST_TMPDIR}/detect.sh" \
        LOOP_NAME="issue-triage" \
        SKILL_NAME="issue-triage" \
        PROMPT_INSTRUCTIONS="triage pls" \
        LEVEL="L1" \
        DELIVERY="none" \
        bash "${ENTITY_DETECT_LIB}"
    [ "$status" -eq 0 ]
    grep -q '^should_run=true$' "${GITHUB_OUTPUT}"
    grep -q 'entity:issue:9' "${GITHUB_OUTPUT}"
    run find "${RUNNER_TEMP}/loop-handoff" -type f
    [ "$status" -eq 0 ]
    [ "$(wc -l <<< "${output}")" -ge 1 ]
}
