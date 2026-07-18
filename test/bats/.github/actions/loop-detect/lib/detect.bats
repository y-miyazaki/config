#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-detect/lib/detect.sh (guard helpers and config gates)

# Use cases:
# - validate_branch_match rejects invalid LOOP_BRANCH_MATCH
# - resolve_detect_script_path fails on empty or missing DETECT_SCRIPT
# - require_scoped_head_for_workflow_run fails when workflow_run lacks scoped head
# - apply_target_cap truncates candidates to fan-out cap
# - target_circuit_breaker_open blocks append_integration_candidate before detect

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

make_detect_candidate() {
    local key="$1"
    jq -nc --arg key "${key}" \
        '{target_json:{key:$key,mode:"integration"},prompt:"p",verifier_context:"",result:{skip:false}}'
}

setup() {
    bats_source_rel ".github/actions/loop-detect/lib/detect.sh"
    DETECT_TMP="$(mktemp -d)"
    export DETECT_TMP
    CANDIDATES_JSON=()
    FILTERED_CANDIDATES_JSON=()
    PENDING_PR_BLOCKED=0
    CIRCUIT_BREAKER_BLOCKED=0
    STATE_SCAN_GLOB="${DETECT_TMP}/state-*.json"
    ACTING_ON_TTL_SECONDS=5400
}

teardown() {
    rm -rf "${DETECT_TMP}"
}

@test "validate_branch_match rejects invalid LOOP_BRANCH_MATCH" {
    LOOP_BRANCH_MATCH="invalid"
    run validate_branch_match
    [ "$status" -eq 1 ]
    [[ $output == *"Invalid LOOP_BRANCH_MATCH"* ]]
}

@test "validate_branch_match accepts list glob and regex" {
    for mode in list glob regex; do
        LOOP_BRANCH_MATCH="${mode}"
        run validate_branch_match
        [ "$status" -eq 0 ]
    done
}

@test "resolve_detect_script_path fails when DETECT_SCRIPT is empty" {
    DETECT_SCRIPT=""
    run resolve_detect_script_path
    [ "$status" -eq 1 ]
    [[ $output == *"DETECT_SCRIPT is empty"* ]]
}

@test "resolve_detect_script_path fails when script file is missing" {
    DETECT_SCRIPT="${DETECT_TMP}/missing-detect.sh"
    run resolve_detect_script_path
    [ "$status" -eq 1 ]
    [[ $output == *"DETECT_SCRIPT not found"* ]]
}

@test "require_scoped_head_for_workflow_run fails when workflow_run lacks scoped head" {
    CI_SWEEPER_WORKFLOW_RUN_ID="12345"
    unset CI_SWEEPER_EVENT_HEAD_BRANCH LOOP_SCOPED_HEAD_BRANCH
    run require_scoped_head_for_workflow_run ""
    [ "$status" -eq 1 ]
    [[ $output == *"workflow_run scope incomplete"* ]]
}

@test "require_scoped_head_for_workflow_run passes when scoped head is set" {
    CI_SWEEPER_WORKFLOW_RUN_ID="12345"
    run require_scoped_head_for_workflow_run "feature/auth"
    [ "$status" -eq 0 ]
}

@test "apply_target_cap truncates candidates to fan-out cap" {
    local i

    for i in 1 2 3 4 5; do
        CANDIDATES_JSON+=("$(make_detect_candidate "integration:branch${i}")")
    done

    apply_target_cap 3

    [ "${#CANDIDATES_JSON[@]}" -eq 3 ]
    run jq -r '.target_json.key' <<< "${CANDIDATES_JSON[0]}"
    [ "$output" = "integration:branch1" ]
    run jq -r '.target_json.key' <<< "${CANDIDATES_JSON[2]}"
    [ "$output" = "integration:branch3" ]
}

@test "append_integration_candidate blocks detect when circuit breaker is open" {
    local detect_calls repo_root state_file

    detect_calls="${DETECT_TMP}/detect_calls"
    : > "${detect_calls}"
    repo_root="${DETECT_TMP}/repo"
    mkdir -p "${repo_root}/.loop"
    state_file="${repo_root}/.loop/state-ci-sweeper.json"
    printf '%s\n' \
        '{"targets":{"integration:main":{"last_sha":"deadbeef","consecutive_failures":3,"open_rejections":[]}}}' \
        > "${state_file}"

    DETECT_SCRIPT="${DETECT_TMP}/detect.sh"
    cat > "${DETECT_SCRIPT}" << EOF
#!/usr/bin/env bash
echo called >> '${detect_calls}'
printf '%s\\n' '{"status":"ok","skip":false,"failures":[{"job_name":"ci","workflow_name":"wf","failure_type":"test","reason":"x"}]}'
EOF
    chmod +x "${DETECT_SCRIPT}"

    STATE_FILE="${state_file}"
    BASE_BRANCH="main"
    SKILL_NAME="loop-ci-sweeper"
    LEVEL="L2"
    ALLOWLIST="*"
    PROMPT_INSTRUCTIONS=""
    LOOP_FINALIZE_INTEGRATION="open_pr"
    PENDING_PR_BLOCKED=0
    CIRCUIT_BREAKER_BLOCKED=0
    CANDIDATES_JSON=()

    checkout_context() {
        cd "${repo_root}" || return 1
        return 0
    }

    append_integration_candidate "main"

    [ "${CIRCUIT_BREAKER_BLOCKED}" -eq 1 ]
    [ "${#CANDIDATES_JSON[@]}" -eq 0 ]
    [ ! -s "${detect_calls}" ]
}

@test "target_budget skip_reason applies while should_run stays true" {
    local github_output pre_cap_count

    for i in 1 2 3 4; do
        CANDIDATES_JSON+=("$(make_detect_candidate "integration:branch${i}")")
    done
    LOOP_MAX_TARGETS_PER_SCHEDULE=2
    pre_cap_count=${#CANDIDATES_JSON[@]}
    skip_reason="none"

    apply_target_cap "${LOOP_MAX_TARGETS_PER_SCHEDULE}"
    if [[ ${pre_cap_count} -gt ${LOOP_MAX_TARGETS_PER_SCHEDULE} ]]; then
        skip_reason="target_budget"
    fi

    [ "${#CANDIDATES_JSON[@]}" -eq 2 ]
    [ "${skip_reason}" = "target_budget" ]

    github_output="$(mktemp)"
    GITHUB_OUTPUT="${github_output}"
    target_matrix_json="$(printf '%s\n' "${CANDIDATES_JSON[@]}" | jq -sc '.')"
    write_detect_outputs "true" "${skip_reason}" "${target_matrix_json}"

    run grep -Fx 'should_run=true' "${github_output}"
    [ "$status" -eq 0 ]
    run grep -Fx 'skip_reason=target_budget' "${github_output}"
    [ "$status" -eq 0 ]
}
