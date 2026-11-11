#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154,SC2317

bats_require_minimum_version 1.5.0

# Tests for .github/actions/loop-detect/lib/detect.sh (guard helpers and config gates)

# Use cases:
# - validate_branch_match rejects invalid DETECT_BRANCH_MATCH_MODE
# - resolve_detect_script_path leaves an empty DETECT_SCRIPT and fails on a missing one
# - require_scoped_head_for_workflow_run fails when workflow_run lacks scoped head
# - apply_scoped_pr_number_filter drops integration and keeps matching PR only
# - apply_target_cap truncates candidates to fan-out cap
# - target_circuit_breaker_open blocks append_integration_candidate before detect
# - build_integration_target_json emits integration mode payload
# - append_detect_candidate blocks detect when pending PR is open
# - append_detect_candidate appends candidate when detect reports failures
# - checkout_context fails closed when fetch is exhausted
# - empty candidates emit checkout_failed when CHECKOUT_FAILED > 0
# - checkout_context increments CHECKOUT_FAILED when checkout fails
# - append_detect_candidate exits the detect phase when the detect script fails
# - multi-target scan fails fast without appending later candidates after detect failure
# - append_detect_candidate accepts unset AGENT_EDIT_ALLOWLIST and AGENT_MAKER_INSTRUCTIONS
# - append_detect_candidate exports STATE_BRANCH (not DEFAULT_BASE_BRANCH) to the detect script
# - target_json carries no finalize or report_file key; agent_report_file reaches the prompt
# - main exits 1 without skip outputs when input validation fails
# - main skips pr_push without a PR number (empty or 0) with pr_number_missing and exit 0
# - main yields no integration targets when detect_branch_match is empty (no state_branch fallback)
# - an empty DETECT_SCRIPT uses the built-in range detect instead of a config_error
# - the built-in range detect replaces an unreachable last_sha in the prompt Last SHA line
# - a custom detect_script keeps the stored last_sha without a reachability check
# - integration target_json carries from.since with the last_sha
# - detect_items false or unset keeps the branch path and ignores result.items
# - detect_items true requires one literal branch and detect_pr_enabled false
# - items mode builds one integration:<branch>#<key> candidate per item with only that item's context
# - items mode gates each item by its own breaker / pending state, never the branch key
# - items mode orders by last_run (no state first) before the detect_max_targets cap
# - items mode falls back to HEAD~10 for from.since without item state
# - items mode treats an empty items array as skip and a missing, invalid, or duplicate key as an error

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

# stub_checkout_context replaces checkout_context with a stub that only enters the given repo.
# The stub is sourced from BATS_TEST_TMPDIR so detect.sh calls it in place of the real checkout.
stub_checkout_context() {
    local stub="${BATS_TEST_TMPDIR}/checkout_context_stub.bash"

    printf 'checkout_context() { cd %q || return 1; }\n' "$1" > "${stub}"
    # shellcheck source=/dev/null
    source "${stub}"
}

# export_main_env exports a valid L2 pr_push environment for running detect.sh main.
export_main_env() {
    local mock_bin="${DETECT_TMP}/bin"

    mkdir -p "${mock_bin}" "${DETECT_TMP}/work"
    : > "${DETECT_TMP}/detect_calls"
    : > "${DETECT_TMP}/gh_calls"
    cat > "${mock_bin}/gh" << EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> '${DETECT_TMP}/gh_calls'
printf '[]\n'
EOF
    chmod +x "${mock_bin}/gh"
    cat > "${DETECT_TMP}/detect-main.sh" << EOF
#!/usr/bin/env bash
echo called >> '${DETECT_TMP}/detect_calls'
printf '%s\n' '{"status":"ok","skip":true}'
EOF
    chmod +x "${DETECT_TMP}/detect-main.sh"

    export PATH="${mock_bin}:${PATH}"
    export GITHUB_OUTPUT="${DETECT_TMP}/github_output"
    : > "${GITHUB_OUTPUT}"
    export DETECT_SCRIPT="${DETECT_TMP}/detect-main.sh"
    export STATE_FILE="${DETECT_TMP}/work/.loop/state-github-pr-revise.json"
    export BUDGET_FILE="${DETECT_TMP}/work/.loop/loop-budget.json"
    export RUN_LOG_FILE="${DETECT_TMP}/work/.loop/loop-run-log.md"
    export LOOP_NAME="github-pr-revise"
    export AGENT_MAKER_SKILL_NAME="github-pr-revise"
    export STATE_BRANCH="main"
    export LEVEL="L2"
    export DELIVERY="pr_push"
    export AGENT_EDIT_TARGET="fix"
    export AGENT_EDIT_ALLOWLIST="**"
    export AGENT_EDIT_DENYLIST=""
    export AGENT_UNCHANGED_VERDICT="REJECT"
    export DETECT_PR_ENABLED="true"
    export DETECT_BRANCH_MATCH=""
    export DETECT_PR_NUMBER=""
    export GITHUB_TOKEN="test-token"
    unset CI_SWEEPER_WORKFLOW_RUN_ID LOOP_SCOPED_HEAD_BRANCH
}

# run_detect_main runs detect.sh as the action does, from a non-repository work directory.
run_detect_main() {
    run --separate-stderr env -C "${DETECT_TMP}/work" \
        bash "$(bats_workspace_root)/.github/actions/loop-detect/lib/detect.sh"
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
    STATE_BRANCH="main"
    export AGENT_MAKER_SKILL_NAME="loop-ci-sweeper"
    LEVEL="L2"
    AGENT_EDIT_ALLOWLIST="*"
    AGENT_MAKER_INSTRUCTIONS=""
    AGENT_EDIT_TARGET="fix"
    PENDING_PR_BLOCKED=0
    CIRCUIT_BREAKER_BLOCKED=0
    CANDIDATES_JSON=()

    stub_checkout_context "${repo_root}"

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
    STATE_BRANCH="main"
    export AGENT_MAKER_SKILL_NAME="loop-ci-sweeper"
    LEVEL="L2"
    AGENT_EDIT_ALLOWLIST="*"
    AGENT_MAKER_INSTRUCTIONS=""
    PENDING_PR_BLOCKED=0
    CIRCUIT_BREAKER_BLOCKED=0
    CANDIDATES_JSON=()

    stub_checkout_context "${repo_root}"

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
    STATE_BRANCH="main"
    export AGENT_MAKER_SKILL_NAME="loop-ci-sweeper"
    LEVEL="L2"
    AGENT_EDIT_ALLOWLIST="*"
    AGENT_MAKER_INSTRUCTIONS=""
    PENDING_PR_BLOCKED=0
    CIRCUIT_BREAKER_BLOCKED=0
    CANDIDATES_JSON=()

    stub_checkout_context "${repo_root}"

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

    run build_integration_target_json "integration:main" "main" "abcdefghijklmn"
    [ "$status" -eq 0 ]
    json="${output}"
    run jq -e \
        --arg key "integration:main" \
        --arg ref "abcdefghijklmn" \
        '.mode == "integration"
         and .key == $key
         and .from.branch == "main"
         and .from.ref == $ref
         and .to.branch == "main"
         and (has("finalize") | not)' \
        <<< "${json}"
    [ "$status" -eq 0 ]
}
@test "build_pull_request_target_json emits pull_request mode payload with pr metadata" {
    local json

    run build_pull_request_target_json "pull_request:42" "feature/auth" "abcdefghijklmn" 42 "main"
    [ "$status" -eq 0 ]
    json="${output}"
    run jq -e \
        --arg key "pull_request:42" \
        '.mode == "pull_request"
         and .key == $key
         and .from.branch == "feature/auth"
         and .to.pr_number == 42
         and .base.branch == "main"
         and (has("finalize") | not)' \
        <<< "${json}"
    [ "$status" -eq 0 ]
}
@test "apply_scoped_pr_number_filter drops integration and keeps matching PR only" {
    INTEGRATION_BRANCHES=("main" "develop")
    OPEN_PRS_JSON=(
        '{"number":11,"headRefName":"a"}'
        '{"number":42,"headRefName":"feature/x"}'
    )
    apply_scoped_pr_number_filter "42"
    [ "${#INTEGRATION_BRANCHES[@]}" -eq 0 ]
    [ "${#OPEN_PRS_JSON[@]}" -eq 1 ]
    run jq -e '.number == 42' <<< "${OPEN_PRS_JSON[0]}"
    [ "$status" -eq 0 ]
}

@test "apply_scoped_pr_number_filter is a no-op when number is empty" {
    INTEGRATION_BRANCHES=("main")
    OPEN_PRS_JSON=('{"number":11}')
    apply_scoped_pr_number_filter ""
    [ "${#INTEGRATION_BRANCHES[@]}" -eq 1 ]
    [ "${#OPEN_PRS_JSON[@]}" -eq 1 ]
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
@test "resolve_detect_script_path leaves an empty DETECT_SCRIPT for the built-in range detect" {
    DETECT_SCRIPT=""
    resolve_detect_script_path > /dev/null
    [ -z "${DETECT_SCRIPT}" ]
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
    DETECT_MAX_TARGETS=2
    pre_cap_count=${#CANDIDATES_JSON[@]}
    skip_reason="none"

    apply_target_cap "${DETECT_MAX_TARGETS}"
    if [[ ${pre_cap_count} -gt ${DETECT_MAX_TARGETS} ]]; then
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
        DETECT_BRANCH_MATCH_MODE="${mode}"
        run validate_branch_match
        [ "$status" -eq 0 ]
    done
}
@test "validate_branch_match rejects invalid DETECT_BRANCH_MATCH_MODE" {
    DETECT_BRANCH_MATCH_MODE="invalid"
    run validate_branch_match
    [ "$status" -eq 1 ]
    [[ $output == *"Invalid DETECT_BRANCH_MATCH_MODE"* ]]
}

@test "detect_result_skip returns non-skip on invalid json" {
    run detect_result_skip "not-json"
    [ "$status" -eq 1 ]
    [[ $output == *"detect_result_skip"* ]]
}

@test "invoke_detect_script exits with detect output when script fails" {
    DETECT_SCRIPT="${DETECT_TMP}/detect-error.sh"
    cat > "${DETECT_SCRIPT}" << 'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"status":"error","message":"missing jq"}'
exit 1
EOF
    chmod +x "${DETECT_SCRIPT}"

    run --separate-stderr invoke_detect_script "deadbeef" "integration:main"
    [ "$status" -eq 1 ]
    [[ ${stderr} == *"missing jq"* ]]
    [[ ${stderr} == *"loop-detect:"* ]]
    [[ ${stderr} == *"integration:main"* ]]
}

@test "append_detect_candidate exits the detect phase when the detect script fails" {
    local detect_lib repo_root state_file

    detect_lib="$(bats_workspace_root)/.github/actions/loop-detect/lib"
    repo_root="${DETECT_TMP}/repo-fail"
    mkdir -p "${repo_root}/.loop"
    git init -q "${repo_root}"
    git -C "${repo_root}" config user.email "test@example.com"
    git -C "${repo_root}" config user.name "Test User"
    git -C "${repo_root}" commit -q --allow-empty -m "init"
    state_file="${repo_root}/.loop/state-ci-sweeper.json"
    printf '%s\n' \
        '{"targets":{"integration:main":{"last_sha":"deadbeef","consecutive_failures":0,"open_rejections":[]}}}' \
        > "${state_file}"

    DETECT_SCRIPT="${DETECT_TMP}/detect-fail.sh"
    cat > "${DETECT_SCRIPT}" << 'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"status":"error","message":"detect failed"}'
exit 1
EOF
    chmod +x "${DETECT_SCRIPT}"

    run --separate-stderr bash -c "
        set -euo pipefail
        # shellcheck disable=SC1091
        source '${detect_lib}/detect.sh'
        DETECT_SCRIPT='${DETECT_SCRIPT}'
        STATE_FILE='${state_file}'
        STATE_BRANCH='main'
        export AGENT_MAKER_SKILL_NAME='loop-ci-sweeper'
        LEVEL='L2'
        AGENT_EDIT_ALLOWLIST='*'
        AGENT_EDIT_TARGET='fix'
        AGENT_MAKER_INSTRUCTIONS=''
        CANDIDATES_JSON=()
        checkout_context() { cd '${repo_root}' || return 1; }
        append_integration_candidate 'main'
    "
    [ "$status" -eq 1 ]
    [[ ${stderr} == *"detect failed"* ]]
    [[ ${stderr} == *"loop-detect:"* ]]
}

@test "multi-target detect scan fails fast without appending later candidates" {
    local detect_lib repo_root state_file call_file

    detect_lib="$(bats_workspace_root)/.github/actions/loop-detect/lib"
    repo_root="${DETECT_TMP}/repo-multi"
    call_file="${DETECT_TMP}/detect_calls"
    mkdir -p "${repo_root}/.loop"
    git init -q "${repo_root}"
    git -C "${repo_root}" config user.email "test@example.com"
    git -C "${repo_root}" config user.name "Test User"
    git -C "${repo_root}" commit -q --allow-empty -m "init"
    state_file="${repo_root}/.loop/state-ci-sweeper.json"
    printf '%s\n' \
        '{"targets":{"integration:main":{"last_sha":"deadbeef","consecutive_failures":0,"open_rejections":[]},"integration:develop":{"last_sha":"deadbeef","consecutive_failures":0,"open_rejections":[]}}}' \
        > "${state_file}"

    DETECT_SCRIPT="${DETECT_TMP}/detect-multi.sh"
    cat > "${DETECT_SCRIPT}" << EOF
#!/usr/bin/env bash
calls='${call_file}'
if [[ ! -f "\${calls}" ]]; then
  : > "\${calls}"
fi
count=\$(wc -l < "\${calls}" 2>/dev/null || echo 0)
echo called >> "\${calls}"
if [[ \${count} -eq 0 ]]; then
  printf '%s\\n' '{"status":"ok","skip":false,"failures":[{"job_name":"ci","workflow_name":"wf","failure_type":"test","reason":"x"}]}'
  exit 0
fi
printf '%s\\n' '{"status":"error","message":"second target failed"}'
exit 1
EOF
    chmod +x "${DETECT_SCRIPT}"
    : > "${call_file}"

    run --separate-stderr bash -c "
        set -euo pipefail
        # shellcheck disable=SC1091
        source '${detect_lib}/detect.sh'
        DETECT_SCRIPT='${DETECT_SCRIPT}'
        STATE_FILE='${state_file}'
        STATE_BRANCH='main'
        export AGENT_MAKER_SKILL_NAME='loop-ci-sweeper'
        LEVEL='L2'
        AGENT_EDIT_ALLOWLIST='*'
        AGENT_EDIT_TARGET='fix'
        AGENT_MAKER_INSTRUCTIONS=''
        CANDIDATES_JSON=()
        checkout_context() { cd '${repo_root}' || return 1; }
        append_integration_candidate 'main' || exit 1
        echo \"after_first=\${#CANDIDATES_JSON[@]}\"
        set +e
        append_integration_candidate 'develop'
        set -e
        echo \"after_second=\${#CANDIDATES_JSON[@]}\"
        exit 1
    "
    [ "$status" -eq 1 ]
    [[ ${stderr} == *"second target failed"* || ${stderr} == *"integration:develop"* ]]
    [ "$(wc -l < "${call_file}")" -eq 2 ]
    [[ $output == *"after_first=1"* ]]
    [[ $output == *"after_second=1"* ]]
}

@test "append_detect_candidate accepts unset AGENT_EDIT_ALLOWLIST and AGENT_MAKER_INSTRUCTIONS" {
    local repo_root state_file

    repo_root="${DETECT_TMP}/repo-empty-allowlist"
    mkdir -p "${repo_root}/.loop"
    git init -q "${repo_root}"
    git -C "${repo_root}" config user.email "test@example.com"
    git -C "${repo_root}" config user.name "Test User"
    git -C "${repo_root}" commit -q --allow-empty -m "init"
    state_file="${repo_root}/.loop/state-github-issue-autofix.json"
    printf '%s\n' \
        '{"targets":{"integration:main":{"last_sha":"deadbeef","consecutive_failures":0,"open_rejections":[]}}}' \
        > "${state_file}"

    DETECT_SCRIPT="${DETECT_TMP}/detect-empty-allowlist.sh"
    cat > "${DETECT_SCRIPT}" << 'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"status":"ok","skip":false,"failures":[{"job_name":"ci","workflow_name":"wf","failure_type":"test","reason":"x"}]}'
EOF
    chmod +x "${DETECT_SCRIPT}"

    STATE_FILE="${state_file}"
    STATE_BRANCH="main"
    export AGENT_MAKER_SKILL_NAME="issue-autofix"
    LEVEL="L2"
    unset AGENT_EDIT_ALLOWLIST
    unset AGENT_MAKER_INSTRUCTIONS
    AGENT_EDIT_TARGET="fix"
    PENDING_PR_BLOCKED=0
    CIRCUIT_BREAKER_BLOCKED=0
    CANDIDATES_JSON=()

    stub_checkout_context "${repo_root}"

    append_integration_candidate "main"

    [ "${#CANDIDATES_JSON[@]}" -eq 1 ]
}

@test "append_detect_candidate exports STATE_BRANCH to the detect script instead of DEFAULT_BASE_BRANCH" {
    local repo_root state_file env_file

    repo_root="${DETECT_TMP}/repo-state-branch"
    env_file="${DETECT_TMP}/detect_env"
    mkdir -p "${repo_root}/.loop"
    git init -q "${repo_root}"
    git -C "${repo_root}" config user.email "test@example.com"
    git -C "${repo_root}" config user.name "Test User"
    git -C "${repo_root}" commit -q --allow-empty -m "init"
    state_file="${repo_root}/.loop/state-ci-sweeper.json"
    printf '%s\n' '{"targets":{}}' > "${state_file}"

    DETECT_SCRIPT="${DETECT_TMP}/detect-env.sh"
    cat > "${DETECT_SCRIPT}" << EOF
#!/usr/bin/env bash
printf '%s|%s\n' "\${STATE_BRANCH:-unset}" "\${DEFAULT_BASE_BRANCH:-unset}" > '${env_file}'
printf '%s\n' '{"status":"ok","skip":true}'
EOF
    chmod +x "${DETECT_SCRIPT}"

    unset DEFAULT_BASE_BRANCH
    STATE_FILE="${state_file}"
    STATE_BRANCH="release"
    LEVEL="L2"
    CANDIDATES_JSON=()

    stub_checkout_context "${repo_root}"

    append_integration_candidate "main"

    [ "$(cat "${env_file}")" = "release|unset" ]
}

@test "append_detect_candidate target_json carries no finalize or report_file key" {
    local repo_root state_file

    repo_root="${DETECT_TMP}/repo-target-keys"
    mkdir -p "${repo_root}/.loop"
    git init -q "${repo_root}"
    git -C "${repo_root}" config user.email "test@example.com"
    git -C "${repo_root}" config user.name "Test User"
    git -C "${repo_root}" commit -q --allow-empty -m "init"
    state_file="${repo_root}/.loop/state-tech-debt.json"
    printf '%s\n' '{"targets":{}}' > "${state_file}"

    DETECT_SCRIPT="${DETECT_TMP}/detect-report.sh"
    cat > "${DETECT_SCRIPT}" << 'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"status":"ok","skip":false,"agent_report_file":"docs/report/tech-debt/2026-10-17.md","report_file":"legacy.md","signals":[]}'
EOF
    chmod +x "${DETECT_SCRIPT}"

    STATE_FILE="${state_file}"
    STATE_BRANCH="main"
    export AGENT_MAKER_SKILL_NAME="tech-debt"
    LEVEL="L2"
    AGENT_EDIT_ALLOWLIST="docs/report/**"
    AGENT_EDIT_TARGET="report"
    CANDIDATES_JSON=()

    stub_checkout_context "${repo_root}"

    append_integration_candidate "main"

    [ "${#CANDIDATES_JSON[@]}" -eq 1 ]
    run jq -c '.target_json | keys' <<< "${CANDIDATES_JSON[0]}"
    [ "$output" = '["from","key","mode","to"]' ]
    run jq -r '.prompt' <<< "${CANDIDATES_JSON[0]}"
    [[ $output == *$'\nagent_report_file: docs/report/tech-debt/2026-10-17.md\n'* ]]
    [[ $output != *"legacy.md"* ]]
}

@test "main exits 1 without skip outputs when input validation fails" {
    local -a cases=(
        'AGENT_EDIT_ALLOWLIST=|::error::agent_edit_allowlist is required at L2 (use ** for unrestricted)'
        'DELIVERY=|::error::delivery must be issue_comment|issue_create|none|pr_create|pr_push|pr_review (got: empty)'
        'LEVEL=|::error::level is required (L1, L2, or L3)'
        'DETECT_BRANCH_MATCH=main|::error::delivery pr_push does not allow detect_branch_match (got: main)'
    )
    local entry assignment expected checked=0
    for entry in "${cases[@]}"; do
        assignment="${entry%%|*}"
        expected="${entry#*|}"
        export_main_env
        export "${assignment?}"
        run_detect_main
        [ "$status" -eq 1 ]
        [ "$stderr" = "${expected}" ]
        [ ! -s "${GITHUB_OUTPUT}" ]
        [ ! -s "${DETECT_TMP}/detect_calls" ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 4 ]
}

@test "main skips pr_push without a PR number with pr_number_missing and exit 0" {
    local pr_number normalized expected entry checked=0
    expected="should_run=false
skip_reason=pr_number_missing
delivery=pr_push
pr_auto_merge=false
target_matrix<<TARGET_MATRIX_X
[]
TARGET_MATRIX_X
last_sha=
current_sha=
consecutive_failures=0
prompt="
    for pr_number in "" "0"; do
        export_main_env
        export DETECT_PR_NUMBER="${pr_number}"
        run_detect_main
        [ "$status" -eq 0 ]
        normalized="$(sed -E 's/TARGET_MATRIX_[0-9a-f]{16}/TARGET_MATRIX_X/' "${GITHUB_OUTPUT}")"
        [ "${normalized}" = "${expected}" ]
        [ ! -s "${DETECT_TMP}/detect_calls" ]
        [ ! -s "${DETECT_TMP}/gh_calls" ]

        # The record-skip job passes skip_reason to loop-run-log unchanged.
        entry="$(bash -c "
            source '$(bats_workspace_root)/.github/actions/loop-run-log/lib/append.sh'
            loop_run_log_build_entry '' 1 '' github-pr-revise skipped pr_number_missing '' 123
        ")"
        run jq -c '{outcome, skip_reason}' <<< "${entry}"
        [ "$output" = '{"outcome":"skipped","skip_reason":"pr_number_missing"}' ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 2 ]
}

@test "main yields no integration targets when detect_branch_match is empty" {
    export_main_env
    export DELIVERY="pr_create"
    export DETECT_PR_NUMBER=""
    export DETECT_PR_ENABLED="true"
    export DETECT_BRANCH_MATCH=""
    run_detect_main
    [ "$status" -eq 0 ]
    run grep -Fx 'skip_reason=no_changes' "${GITHUB_OUTPUT}"
    [ "$status" -eq 0 ]
    run grep -Fx 'should_run=false' "${GITHUB_OUTPUT}"
    [ "$status" -eq 0 ]
    [ -s "${DETECT_TMP}/gh_calls" ]
    [ ! -s "${DETECT_TMP}/detect_calls" ]
}

# make_range_repo: repository whose state points at SINCE and whose HEAD changes src/a.sh
make_range_repo() {
    local state_sha="${1:-}"

    RANGE_REPO="${DETECT_TMP}/repo"
    mkdir -p "${RANGE_REPO}/.loop" "${RANGE_REPO}/src"
    git init -q "${RANGE_REPO}"
    git -C "${RANGE_REPO}" config user.email "test@example.com"
    git -C "${RANGE_REPO}" config user.name "Test User"
    printf 'one\n' > "${RANGE_REPO}/src/a.sh"
    git -C "${RANGE_REPO}" add -A
    git -C "${RANGE_REPO}" commit -q -m base
    RANGE_SINCE="$(git -C "${RANGE_REPO}" rev-parse HEAD)"
    printf 'two\n' >> "${RANGE_REPO}/src/a.sh"
    git -C "${RANGE_REPO}" add -A
    git -C "${RANGE_REPO}" commit -q -m change
    printf '{"targets":{"integration:main":{"last_sha":"%s","consecutive_failures":0,"open_rejections":[]}}}\n' \
        "${state_sha:-${RANGE_SINCE}}" > "${RANGE_REPO}/.loop/state-x.json"
    STATE_FILE="${RANGE_REPO}/.loop/state-x.json"
    RUN_LOG_FILE="${RANGE_REPO}/.loop/run-log.md"
    STATE_BRANCH="main"
    LEVEL="L2"
    AGENT_EDIT_ALLOWLIST="*"
    AGENT_MAKER_INSTRUCTIONS=""
    AGENT_EDIT_TARGET="report"
    AGENT_MAKER_SKILL_NAME="code-review"
    stub_checkout_context "${RANGE_REPO}"
}

@test "append_detect_candidate builds the integration target with from.since" {
    make_range_repo
    DETECT_SCRIPT=""
    append_integration_candidate "main"
    [ "${#CANDIDATES_JSON[@]}" -eq 1 ]
    [ "$(jq -r '.target_json.from.since' <<< "${CANDIDATES_JSON[0]}")" = "${RANGE_SINCE}" ]
}

@test "append_detect_candidate keeps the stored last_sha for a custom detect_script" {
    make_range_repo "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
    DETECT_SCRIPT="${DETECT_TMP}/detect-custom.sh"
    printf '#!/usr/bin/env bash\nprintf %%s %s\n' "'{\"skip\":false,\"failures\":[]}'" > "${DETECT_SCRIPT}"
    chmod +x "${DETECT_SCRIPT}"
    append_integration_candidate "main"
    [ "${#CANDIDATES_JSON[@]}" -eq 1 ]
    [[ "$(jq -r '.prompt' <<< "${CANDIDATES_JSON[0]}")" == *"Last SHA: deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"* ]]
}

@test "append_detect_candidate range detect replaces an unreachable last_sha in the prompt" {
    local fallback
    make_range_repo "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
    fallback="$(git -C "${RANGE_REPO}" rev-list --max-parents=0 HEAD | head -1)"
    DETECT_SCRIPT=""
    append_integration_candidate "main"
    [ "${#CANDIDATES_JSON[@]}" -eq 1 ]
    [[ "$(jq -r '.prompt' <<< "${CANDIDATES_JSON[0]}")" == *"Last SHA: ${fallback}"* ]]
    [ "$(jq -r '.target_json.from.since' <<< "${CANDIDATES_JSON[0]}")" = "${fallback}" ]
}

@test "main does not report config_error for an empty DETECT_SCRIPT" {
    export_main_env
    export DETECT_SCRIPT=""
    export DETECT_PR_NUMBER=""
    run_detect_main
    [ "$status" -eq 0 ]
    grep -qx 'skip_reason=pr_number_missing' "${GITHUB_OUTPUT}"
}

# items_detect_json N...: detect JSON whose result.items holds one issue item per number
items_detect_json() {
    printf '%s\n' "$@" | jq -sc '{status: "ok", skip: false, result: {items: map({
        key: ("issue:" + tostring),
        entity: {kind: "issue", number: ., handoff_key: ("entity:issue:" + tostring)},
        context: {issue_number: .},
        verifier_context: ""
    })}}'
}

# make_items_repo DETECT_JSON [STATE_TARGETS_JSON]: repo with 11 commits, a detect script
# that prints DETECT_JSON, the state targets, and the environment for an items mode run.
make_items_repo() {
    local detect_json="$1"
    local targets_json="${2:-}"
    local i

    [[ -n ${targets_json} ]] || targets_json='{}'
    ITEMS_REPO="${DETECT_TMP}/items-repo"
    mkdir -p "${ITEMS_REPO}/.loop"
    git init -q "${ITEMS_REPO}"
    git -C "${ITEMS_REPO}" config user.email "test@example.com"
    git -C "${ITEMS_REPO}" config user.name "Test User"
    for i in 0 1 2 3 4 5 6 7 8 9 10; do
        git -C "${ITEMS_REPO}" commit -q --allow-empty -m "c${i}"
    done
    jq -nc --argjson t "${targets_json}" '{targets: $t}' > "${ITEMS_REPO}/.loop/state-items.json"
    printf '%s\n' "${detect_json}" > "${DETECT_TMP}/items-detect.json"
    : > "${DETECT_TMP}/detect_calls"
    printf '#!/usr/bin/env bash\necho called >> %q\ncat %q\n' \
        "${DETECT_TMP}/detect_calls" "${DETECT_TMP}/items-detect.json" > "${DETECT_TMP}/detect-items.sh"
    chmod +x "${DETECT_TMP}/detect-items.sh"

    export AGENT_EDIT_ALLOWLIST="**"
    export AGENT_EDIT_DENYLIST=""
    export AGENT_EDIT_TARGET="fix"
    export AGENT_MAKER_INSTRUCTIONS=""
    export AGENT_MAKER_SKILL_NAME="github-issue-autofix"
    export AGENT_UNCHANGED_VERDICT="REJECT"
    export BUDGET_FILE="${ITEMS_REPO}/.loop/loop-budget.json"
    export DELIVERY="pr_create"
    export DETECT_BRANCH_MATCH="main"
    export DETECT_BRANCH_MATCH_MODE="list"
    export DETECT_ITEMS="true"
    export DETECT_MAX_TARGETS="3"
    export DETECT_PR_ENABLED="false"
    export DETECT_PR_NUMBER=""
    export DETECT_SCRIPT="${DETECT_TMP}/detect-items.sh"
    export GITHUB_OUTPUT="${DETECT_TMP}/github_output"
    export GITHUB_TOKEN=""
    export LEVEL="L2"
    export LOOP_NAME="items"
    export RUNNER_TEMP="${DETECT_TMP}"
    export RUN_LOG_FILE="${ITEMS_REPO}/.loop/loop-run-log.md"
    export STATE_BRANCH="main"
    export STATE_FILE="${ITEMS_REPO}/.loop/state-items.json"
    : > "${GITHUB_OUTPUT}"
    unset CI_SWEEPER_WORKFLOW_RUN_ID LOOP_SCOPED_HEAD_BRANCH
    stub_checkout_context "${ITEMS_REPO}"
}

# run_items_main runs detect.sh main with checkout_context entering ITEMS_REPO.
run_items_main() {
    run --separate-stderr bash -c "
        source '$(bats_workspace_root)/.github/actions/loop-detect/lib/detect.sh'
        checkout_context() { cd '${ITEMS_REPO}' || return 1; }
        main
    "
}

# output_matrix_keys prints the comma-joined target keys of the target_matrix output.
output_matrix_keys() {
    awk '/^target_matrix<</ {f = 1; next} f && /^TARGET_MATRIX_/ {exit} f' "${GITHUB_OUTPUT}" \
        | jq -r '[.[].target_json.key] | join(",")'
}

@test "items empty array behaves like skip" {
    local detect_json

    for detect_json in \
        '{"status":"ok","skip":false,"result":{"items":[]}}' \
        '{"status":"ok","skip":true}'; do
        make_items_repo "${detect_json}"
        run_items_main
        [ "$status" -eq 0 ]
        grep -qx 'should_run=false' "${GITHUB_OUTPUT}"
        grep -qx 'skip_reason=no_changes' "${GITHUB_OUTPUT}"
        rm -rf "${ITEMS_REPO}"
    done
}

@test "items ignored when detect_items false" {
    local detect_json value

    detect_json="$(items_detect_json 1 2)"
    for value in false ""; do
        make_items_repo "${detect_json}"
        export DETECT_ITEMS="${value}"
        run_items_main
        [ "$status" -eq 0 ]
        [ "$(output_matrix_keys)" = "integration:main" ]
        rm -rf "${ITEMS_REPO}"
    done

    make_items_repo "${detect_json}"
    DETECT_ITEMS="false"
    append_integration_candidate "main"
    [ "${#CANDIDATES_JSON[@]}" -eq 1 ]
    [ "$(jq -c '.result' <<< "${CANDIDATES_JSON[0]}")" = "${detect_json}" ]
    [ "$(jq -r '.target_json.entity // "none"' <<< "${CANDIDATES_JSON[0]}")" = "none" ]
}

@test "items mode candidate result contains only that item's context" {
    make_items_repo '{"status":"ok","skip":false,"result":{"items":[
        {"key":"issue:1","context":{"issue_number":1,"title":"one"},"verifier_context":"## Issue 1"},
        {"key":"issue:2","context":{"issue_number":2}}]}}'

    append_items_candidates "main"

    [ "${#CANDIDATES_JSON[@]}" -eq 2 ]
    [ "$(jq -c '.result' <<< "${CANDIDATES_JSON[0]}")" = '{"status":"ok","skip":false,"result":{"issue_number":1,"title":"one","key":"issue:1"}}' ]
    [ "$(jq -c '.result' <<< "${CANDIDATES_JSON[1]}")" = '{"status":"ok","skip":false,"result":{"issue_number":2,"key":"issue:2"}}' ]
    [ "$(jq -r '.verifier_context' <<< "${CANDIDATES_JSON[0]}")" = "## Issue 1" ]
    [ "$(jq -r '.verifier_context' <<< "${CANDIDATES_JSON[1]}")" = "" ]
}

@test "items mode caps at detect_max_targets" {
    make_items_repo "$(items_detect_json 1 2 3 4)"
    export DETECT_MAX_TARGETS="3"
    run_items_main
    [ "$status" -eq 0 ]
    grep -qx 'should_run=true' "${GITHUB_OUTPUT}"
    grep -qx 'skip_reason=target_budget' "${GITHUB_OUTPUT}"
    [ "$(output_matrix_keys)" = "integration:main#issue:1,integration:main#issue:2,integration:main#issue:3" ]
    [ "$(wc -l < "${DETECT_TMP}/detect_calls")" -eq 1 ]
}

@test "items mode creates one candidate per item with per-item key" {
    make_items_repo "$(items_detect_json 1 2)"

    append_items_candidates "main"

    [ "${#CANDIDATES_JSON[@]}" -eq 2 ]
    [ "$(wc -l < "${DETECT_TMP}/detect_calls")" -eq 1 ]
    run jq -c '.target_json | {mode, key, from: .from.branch, to: .to.branch, entity}' <<< "${CANDIDATES_JSON[0]}"
    [ "$output" = '{"mode":"integration","key":"integration:main#issue:1","from":"main","to":"main","entity":{"kind":"issue","number":1}}' ]
    run jq -c '.target_json | {mode, key, entity}' <<< "${CANDIDATES_JSON[1]}"
    [ "$output" = '{"mode":"integration","key":"integration:main#issue:2","entity":{"kind":"issue","number":2}}' ]
    [ "$(jq -r '.target_json.from.ref' <<< "${CANDIDATES_JSON[0]}")" = "$(git -C "${ITEMS_REPO}" rev-parse HEAD)" ]
}

@test "items mode exits the detect phase when the detect script fails" {
    make_items_repo '{"status":"error","message":"items detect failed"}'
    printf '#!/usr/bin/env bash\ncat %q\nexit 3\n' "${DETECT_TMP}/items-detect.json" > "${DETECT_SCRIPT}"
    run_items_main
    [ "$status" -ne 0 ]
    [[ ${stderr} == *"items detect failed"* ]]
    [[ ${stderr} == *"loop-detect: detect script failed"* ]]
    run ! grep -q 'should_run=' "${GITHUB_OUTPUT}"
}

@test "items mode fails on invalid or duplicate item key" {
    local entry expected

    for entry in \
        '{"status":"ok","skip":false,"result":{"items":[{"key":"issue:1"},{"key":"issue:1"}]}}|duplicate item key' \
        '{"status":"ok","skip":false,"result":{"items":[{"key":"a b"}]}}|invalid item key'; do
        expected="${entry#*|}"
        make_items_repo "${entry%%|*}"
        run_items_main
        [ "$status" -eq 1 ]
        [[ ${stderr} == *"::error::"*"${expected}"* ]]
        run ! grep -q 'should_run=' "${GITHUB_OUTPUT}"
        rm -rf "${ITEMS_REPO}"
    done
}

@test "items mode ignores branch-level circuit breaker" {
    make_items_repo "$(items_detect_json 1)" \
        '{"integration:main":{"last_sha":"deadbeef","consecutive_failures":3,"pending":{"pr":7}}}'

    append_items_candidates "main"

    [ "${#CANDIDATES_JSON[@]}" -eq 1 ]
    [ "$(jq -r '.target_json.key' <<< "${CANDIDATES_JSON[0]}")" = "integration:main#issue:1" ]
    [ "${CIRCUIT_BREAKER_BLOCKED}" -eq 0 ]
    [ "${PENDING_PR_BLOCKED}" -eq 0 ]
}

@test "items mode missing items key is an error" {
    make_items_repo '{"status":"ok","skip":false,"result":{"issue_number":1}}'
    run_items_main
    [ "$status" -eq 1 ]
    [[ ${stderr} == *"::error::"*"items"* ]]
    run ! grep -q 'should_run=' "${GITHUB_OUTPUT}"
}

@test "items mode orders by last_run oldest first before cap" {
    make_items_repo "$(items_detect_json 1 2 3)" \
        '{"integration:main#issue:1":{"last_run":"2026-11-10T00:00:00Z","consecutive_failures":0},
          "integration:main#issue:2":{"last_run":"2026-11-01T00:00:00Z","consecutive_failures":0}}'
    export DETECT_MAX_TARGETS="2"
    run_items_main
    [ "$status" -eq 0 ]
    grep -qx 'skip_reason=target_budget' "${GITHUB_OUTPUT}"
    [ "$(output_matrix_keys)" = "integration:main#issue:3,integration:main#issue:2" ]
}

@test "items mode requires single branch and detect_pr_enabled false" {
    local -a cases=(
        'DETECT_BRANCH_MATCH=main,develop'
        $'DETECT_BRANCH_MATCH=main\ndevelop'
        'DETECT_BRANCH_MATCH=release/*'
        'DETECT_BRANCH_MATCH_MODE=regex'
        'DETECT_PR_ENABLED=true'
        'DETECT_ITEMS=yes'
    )
    local assignment checked=0

    make_items_repo "$(items_detect_json 1)"
    run validate_detect_inputs
    [ "$status" -eq 0 ]
    DETECT_BRANCH_MATCH_MODE="glob"
    run validate_detect_inputs
    [ "$status" -eq 0 ]
    rm -rf "${ITEMS_REPO}"

    for assignment in "${cases[@]}"; do
        make_items_repo "$(items_detect_json 1)"
        export "${assignment?}"
        run --separate-stderr validate_detect_inputs
        [ "$status" -eq 1 ]
        [[ ${stderr} == *"::error::"*"detect_items"* ]]
        rm -rf "${ITEMS_REPO}"
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 6 ]

    make_items_repo "$(items_detect_json 1)"
    export DETECT_BRANCH_MATCH="main,develop"
    run_items_main
    [ "$status" -eq 1 ]
    [ ! -s "${GITHUB_OUTPUT}" ]
    [ ! -s "${DETECT_TMP}/detect_calls" ]
}

@test "items mode since falls back to HEAD~10 without state" {
    make_items_repo "$(items_detect_json 1 2)" \
        '{"integration:main#issue:2":{"last_sha":"cafebabecafebabecafebabecafebabecafebabe","consecutive_failures":0}}'

    append_items_candidates "main"

    [ "${#CANDIDATES_JSON[@]}" -eq 2 ]
    [ "$(jq -r '.target_json.from.since' <<< "${CANDIDATES_JSON[0]}")" = "$(git -C "${ITEMS_REPO}" rev-parse HEAD~10)" ]
    [ "$(jq -r '.target_json.from.since' <<< "${CANDIDATES_JSON[1]}")" = "cafebabecafebabecafebabecafebabecafebabe" ]
    [[ "$(jq -r '.prompt' <<< "${CANDIDATES_JSON[1]}")" == *"Last SHA: cafebabecafebabecafebabecafebabecafebabe"* ]]
}

@test "items mode skips item with open breaker and reports circuit_breaker skip_reason when all blocked" {
    make_items_repo "$(items_detect_json 1 2)" \
        '{"integration:main#issue:1":{"consecutive_failures":3}}'
    append_items_candidates "main"
    [ "${#CANDIDATES_JSON[@]}" -eq 1 ]
    [ "$(jq -r '.target_json.key' <<< "${CANDIDATES_JSON[0]}")" = "integration:main#issue:2" ]
    [ "${CIRCUIT_BREAKER_BLOCKED}" -eq 1 ]
    rm -rf "${ITEMS_REPO}"

    make_items_repo "$(items_detect_json 1)" \
        '{"integration:main#issue:1":{"consecutive_failures":3}}'
    run_items_main
    [ "$status" -eq 0 ]
    [[ ${output} == *"::warning::Circuit breaker open for integration:main#issue:1"* ]]
    grep -qx 'should_run=false' "${GITHUB_OUTPUT}"
    grep -qx 'skip_reason=circuit_breaker' "${GITHUB_OUTPUT}"
}

@test "items mode skips item with pending pr" {
    make_items_repo "$(items_detect_json 1 2)" \
        '{"integration:main#issue:2":{"consecutive_failures":0,"pending":{"pr":42}}}'

    append_items_candidates "main"

    [ "${#CANDIDATES_JSON[@]}" -eq 1 ]
    [ "$(jq -r '.target_json.key' <<< "${CANDIDATES_JSON[0]}")" = "integration:main#issue:1" ]
    [ "${PENDING_PR_BLOCKED}" -eq 1 ]
}
