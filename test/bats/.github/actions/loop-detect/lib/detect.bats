#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154,SC2317

# Tests for .github/actions/loop-detect/lib/detect.sh (guard helpers and config gates)

# Use cases:
# - validate_branch_match rejects invalid LOOP_BRANCH_MATCH
# - resolve_detect_script_path fails on empty or missing DETECT_SCRIPT
# - require_scoped_head_for_workflow_run fails when workflow_run lacks scoped head
# - apply_target_cap truncates candidates to fan-out cap
# - target_circuit_breaker_open blocks append_integration_candidate before detect
# - build_integration_target_json emits integration mode payload
# - append_detect_candidate blocks detect when pending PR is open
# - append_detect_candidate appends candidate when detect reports failures
# - checkout_context fails closed when fetch is exhausted
# - empty candidates emit checkout_failed when CHECKOUT_FAILED > 0
# - checkout_context increments CHECKOUT_FAILED when checkout fails

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
}

teardown() {
    rm -rf "${DETECT_TMP}"
}

@test "append_detect_candidate appends candidate when detect reports failures" {
    local detect_calls repo_root state_file

    detect_calls="${DETECT_TMP}/detect_calls"
    : > "${detect_calls}"
    repo_root="${DETECT_TMP}/repo"
    mkdir -p "${repo_root}/.loop"
    git init -q "${repo_root}"
    git -C "${repo_root}" config user.email "test@example.com"
    git -C "${repo_root}" config user.name "Test User"
    git -C "${repo_root}" commit -q --allow-empty -m "init"
    state_file="${repo_root}/.loop/state-ci-sweeper.json"
    printf '%s\n' \
        '{"targets":{"integration:main":{"last_sha":"deadbeef","consecutive_failures":0,"open_rejections":[]}}}' \
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

    [ "${#CANDIDATES_JSON[@]}" -eq 1 ]
    [ -s "${detect_calls}" ]
    run jq -e '.target_json.key == "integration:main"' <<< "${CANDIDATES_JSON[0]}"
    [ "$status" -eq 0 ]
}
@test "append_detect_candidate blocks detect when pending PR is open" {
    local detect_calls repo_root state_file

    detect_calls="${DETECT_TMP}/detect_calls"
    : > "${detect_calls}"
    repo_root="${DETECT_TMP}/repo-pending"
    mkdir -p "${repo_root}/.loop"
    state_file="${repo_root}/.loop/state-ci-sweeper.json"
    printf '%s\n' \
        '{"targets":{"integration:main":{"last_sha":"deadbeef","consecutive_failures":0,"pending":{"pr":42}}}}' \
        > "${state_file}"

    DETECT_SCRIPT="${DETECT_TMP}/detect-pending.sh"
    cat > "${DETECT_SCRIPT}" << EOF
#!/usr/bin/env bash
echo called >> '${detect_calls}'
printf '%s\\n' '{"status":"ok","skip":false,"failures":[]}'
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

    [ "${PENDING_PR_BLOCKED}" -eq 1 ]
    [ "${#CANDIDATES_JSON[@]}" -eq 0 ]
    [ ! -s "${detect_calls}" ]
}

@test "checkout_context fails closed when fetch is exhausted" {
    local mock_bin calls

    mock_bin="${DETECT_TMP}/bin"
    calls="${DETECT_TMP}/git_calls"
    mkdir -p "${mock_bin}"
    : > "${calls}"
    cat > "${mock_bin}/git" << EOF
#!/usr/bin/env bash
printf '%s\\n' "\$*" >> "${calls}"
case "\$1" in
    fetch) exit 1 ;;
    checkout) exit 0 ;;
    *) exit 0 ;;
esac
EOF
    chmod +x "${mock_bin}/git"

    CHECKOUT_FAILED=0
    PATH="${mock_bin}:${PATH}"
    run checkout_context "main"
    [ "$status" -eq 1 ]
    [[ $output == *"fetch failed"* ]]

    CHECKOUT_FAILED=0
    checkout_context "main" > /dev/null 2>&1 || true
    [ "${CHECKOUT_FAILED}" -eq 1 ]
    grep -q '^fetch ' "${calls}"
    run grep -q '^checkout ' "${calls}"
    [ "$status" -ne 0 ]
}

@test "checkout_context increments CHECKOUT_FAILED when checkout fails" {
    local mock_bin

    mock_bin="${DETECT_TMP}/bin"
    mkdir -p "${mock_bin}"
    cat > "${mock_bin}/git" << 'EOF'
#!/usr/bin/env bash
case "$1" in
    fetch) exit 0 ;;
    checkout) exit 1 ;;
    *) command git "$@" ;;
esac
EOF
    chmod +x "${mock_bin}/git"

    CHECKOUT_FAILED=0
    PATH="${mock_bin}:${PATH}"
    run checkout_context "main"
    [ "$status" -eq 1 ]

    CHECKOUT_FAILED=0
    checkout_context "main" > /dev/null 2>&1 || true
    [ "${CHECKOUT_FAILED}" -eq 1 ]
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
@test "build_integration_target_json emits integration mode payload" {
    local json

    run build_integration_target_json "integration:main" "main" "abc123def456" "open_pr"
    [ "$status" -eq 0 ]
    json="${output}"
    run jq -e \
        --arg key "integration:main" \
        --arg ref "abc123def456" \
        '.mode == "integration"
         and .key == $key
         and .from.branch == "main"
         and .from.ref == $ref
         and .to.branch == "main"
         and .finalize == "open_pr"' \
        <<< "${json}"
    [ "$status" -eq 0 ]
}
@test "build_pull_request_target_json emits pull_request mode payload with pr metadata" {
    local json

    run build_pull_request_target_json "pull_request:42" "feature/auth" "abc123def456" "open_pr" 42 "main"
    [ "$status" -eq 0 ]
    json="${output}"
    run jq -e \
        --arg key "pull_request:42" \
        '.mode == "pull_request"
         and .key == $key
         and .from.branch == "feature/auth"
         and .to.pr_number == 42
         and .base.branch == "main"
         and .finalize == "open_pr"' \
        <<< "${json}"
    [ "$status" -eq 0 ]
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
@test "empty candidates emit checkout_failed when CHECKOUT_FAILED is set" {
    local github_output

    CANDIDATES_JSON=()
    CHECKOUT_FAILED=1
    CIRCUIT_BREAKER_BLOCKED=0
    PENDING_PR_BLOCKED=0
    github_output="$(mktemp)"
    GITHUB_OUTPUT="${github_output}"

    write_empty_candidates_outputs

    run grep -Fx 'should_run=false' "${github_output}"
    [ "$status" -eq 0 ]
    run grep -Fx 'skip_reason=checkout_failed' "${github_output}"
    [ "$status" -eq 0 ]
}
@test "validate_branch_match accepts list glob and regex" {
    for mode in list glob regex; do
        LOOP_BRANCH_MATCH="${mode}"
        run validate_branch_match
        [ "$status" -eq 0 ]
    done
}
@test "validate_branch_match rejects invalid LOOP_BRANCH_MATCH" {
    LOOP_BRANCH_MATCH="invalid"
    run validate_branch_match
    [ "$status" -eq 1 ]
    [[ $output == *"Invalid LOOP_BRANCH_MATCH"* ]]
}
