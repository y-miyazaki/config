#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .apm/packages/loop-ci-sweeper/.apm/skills/loop-ci-sweeper/scripts/detect_ci_failures.sh

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

DETECT_SCRIPT="$(apm_skill_script_path loop-ci-sweeper detect_ci_failures.sh)"

setup() {
    LEDGER_FILE="$(mktemp)"
    export CI_SWEEPER_LEDGER_FILE="${LEDGER_FILE}"
    export CI_SWEEPER_REJECT_RETRY_POLICY="limited"
    export CI_SWEEPER_REJECT_MAX_RETRIES="3"
    # Notices are enabled under GITHUB_ACTIONS; keep unit tests stdout-clean.
    unset GITHUB_ACTIONS CI_SWEEPER_DEBUG_LOG
    bats_source_apm_skill loop-ci-sweeper detect_ci_failures.sh
}

teardown() {
    rm -f "${LEDGER_FILE:-}"
}

@test "append_ignored records ledger skip reason" {
    REJECT_RETRY_POLICY="block"
    printf '%s' '{"runs":{"12345":{"outcome":"no-action","reject_count":0}}}' > "${LEDGER_FILE}"
    FAILURES_JSON=()
    IGNORED_JSON=()
    collect_failures_for_run "ci-markdown" "12345" "abc123" "main" "https://example.com/run/1" "failure"
    [ "${#FAILURES_JSON[@]}" -eq 0 ]
    [ "${#IGNORED_JSON[@]}" -eq 1 ]
    [[ ${IGNORED_JSON[0]} == *"ledger: no-action"* ]]
}

@test "classify_failure_type treats normal runner label as regression" {
    run classify_failure_type "Job is about to start running on the runner: ubuntu-latest"
    [ "$status" -eq 0 ]
    [ "$output" = "regression" ]
}

@test "classify_failure_type treats waiting for runner as infra" {
    run classify_failure_type "Waiting for a runner to pick up this job"
    [ "$status" -eq 0 ]
    [ "$output" = "infra" ]
}

@test "classify_failure_type treats shellcheck failure as regression" {
    run classify_failure_type "SC2086: Double quote to prevent globbing"
    [ "$status" -eq 0 ]
    [ "$output" = "regression" ]
}

@test "normalize_reject_retry_policy accepts aliases a b c" {
    [ "$(normalize_reject_retry_policy "a")" = "block" ]
    [ "$(normalize_reject_retry_policy "b")" = "retry" ]
    [ "$(normalize_reject_retry_policy "c")" = "limited" ]
}

@test "should_skip_processed_run block policy skips any ledgered run" {
    REJECT_RETRY_POLICY="block"
    printf '%s' '{"runs":{"123":{"outcome":"no-action","reject_count":0}}}' > "${LEDGER_FILE}"
    run should_skip_processed_run "123"
    [ "$status" -eq 0 ]
}

@test "should_skip_processed_run retry policy skips only pr-created" {
    REJECT_RETRY_POLICY="retry"
    printf '%s' '{"runs":{"123":{"outcome":"no-action","reject_count":0}}}' > "${LEDGER_FILE}"
    run should_skip_processed_run "123"
    [ "$status" -eq 1 ]

    printf '%s' '{"runs":{"456":{"outcome":"pr-created","reject_count":0}}}' > "${LEDGER_FILE}"
    run should_skip_processed_run "456"
    [ "$status" -eq 0 ]
}

@test "should_skip_processed_run limited policy allows retry for no-action outcome" {
    CI_SWEEPER_REJECT_RETRY_POLICY="limited"
    printf '%s' '{"runs":{"123":{"outcome":"no-action","reject_count":0}}}' > "${LEDGER_FILE}"
    run should_skip_processed_run "123"
    [ "$status" -eq 1 ]
}

@test "should_skip_processed_run limited policy skips rejected at max retries" {
    REJECT_RETRY_POLICY="limited"
    REJECT_MAX_RETRIES="3"
    printf '%s' '{"runs":{"456":{"outcome":"rejected","reject_count":3}}}' > "${LEDGER_FILE}"
    run should_skip_processed_run "456"
    [ "$status" -eq 0 ]

    printf '%s' '{"runs":{"456":{"outcome":"rejected","reject_count":2}}}' > "${LEDGER_FILE}"
    run should_skip_processed_run "456"
    [ "$status" -eq 1 ]
}

@test "collect_failures_for_run includes startup_failure as workflow-level failure" {
    MOCK_BIN="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${MOCK_BIN}"
    cat > "${MOCK_BIN}/gh" << 'EOF'
#!/usr/bin/env bash
if [[ "$1" == "run" && "$2" == "view" ]]; then
    if [[ "$*" == *"--json jobs"* ]]; then
        exit 0
    fi
    if [[ "$*" == *"--json event,workflowName,displayTitle,conclusion"* ]]; then
        printf '%s\n' '{"event":"workflow_dispatch","workflowName":"on-loop-changelog","displayTitle":"on-loop-changelog","conclusion":"startup_failure"}'
        exit 0
    fi
fi
exit 1
EOF
    chmod +x "${MOCK_BIN}/gh"
    PATH="${MOCK_BIN}:${PATH}"

    FAILURES_JSON=()
    IGNORED_JSON=()
    collect_failures_for_run "on-loop-changelog" "12345" "abc123" "main" "https://example.com/run/1" "startup_failure"
    [ "${#FAILURES_JSON[@]}" -eq 1 ]
    [ "${#IGNORED_JSON[@]}" -eq 0 ]
    [[ ${FAILURES_JSON[0]} == *'"job_name": "workflow"'* ]]
    [[ ${FAILURES_JSON[0]} == *"startup_failure"* ]]
}

@test "collect_failures_for_run includes infra failures in failures array" {
    MOCK_BIN="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${MOCK_BIN}"
    cat > "${MOCK_BIN}/gh" << 'EOF'
#!/usr/bin/env bash
if [[ "$1" == "run" && "$2" == "view" ]]; then
    if [[ "$*" == *"--json jobs"* ]]; then
        printf '%s\n' '{"name":"lint","conclusion":"failure","url":"https://example.com/run/1"}'
        exit 0
    fi
    if [[ "$*" == *"--log-failed"* ]]; then
        printf '%s\n' "Waiting for a runner to pick up this job"
        exit 0
    fi
fi
exit 1
EOF
    chmod +x "${MOCK_BIN}/gh"
    PATH="${MOCK_BIN}:${PATH}"

    FAILURES_JSON=()
    IGNORED_JSON=()
    collect_failures_for_run "ci-markdown" "12345" "abc123" "main" "https://example.com/run/1"
    [ "${#FAILURES_JSON[@]}" -eq 1 ]
    [ "${#IGNORED_JSON[@]}" -eq 0 ]
    [[ ${FAILURES_JSON[0]} == *'"failure_type": "infra"'* ]]
}

@test "classify_failure_type treats http status in test output as regression" {
    run classify_failure_type "expected status 401 Unauthorized in response test"
    [ "$status" -eq 0 ]
    [ "$output" = "regression" ]
}

@test "classify_failure_type does not treat timestamp digits as infra http status" {
    # Regression: bare 502|503|504 matched substrings inside timestamps like 1850472.
    run classify_failure_type "markdown-ci / lint	UNKNOWN STEP	2026-07-17T04:12:53.1850472Z ##[endgroup]"
    [ "$status" -eq 0 ]
    [ "$output" = "regression" ]
}

@test "classify_failure_type treats explicit HTTP 503 as infra" {
    run classify_failure_type "upstream returned HTTP 503 Service Unavailable"
    [ "$status" -eq 0 ]
    [ "$output" = "infra" ]
}

@test "run_head_branch_for_run uses gh --jq expression without -r flag" {
    MOCK_BIN="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${MOCK_BIN}"
    cat > "${MOCK_BIN}/gh" << 'EOF'
#!/usr/bin/env bash
# Mirror real gh: --jq accepts exactly one argument (the expression).
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
    if [[ ${args[$i]} == "--jq" ]]; then
        if [[ $((i + 1)) -ge ${#args[@]} ]]; then
            echo "flag needs an argument: --jq" >&2
            exit 1
        fi
        expr="${args[$((i + 1))]}"
        if [[ ${expr} == -* ]]; then
            echo "accepts at most 1 arg(s), received 2" >&2
            exit 1
        fi
        if [[ $* == *"--json headBranch"* ]]; then
            printf '%s\n' "main"
            exit 0
        fi
    fi
done
echo "missing --jq" >&2
exit 1
EOF
    chmod +x "${MOCK_BIN}/gh"
    PATH="${MOCK_BIN}:${PATH}"

    run run_head_branch_for_run "29554290605"
    [ "$status" -eq 0 ]
    [ "$output" = "main" ]
}

@test "collect_from_workflow_run_event ignores branch mismatch for PR scan context" {
    MOCK_BIN="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${MOCK_BIN}"
    cat > "${MOCK_BIN}/gh" << 'EOF'
#!/usr/bin/env bash
if [[ "$1" == "run" && "$2" == "view" && $* == *"--json headBranch"* ]]; then
    if [[ $* == *"--jq"* ]]; then
        args=("$@")
        for ((i = 0; i < ${#args[@]}; i++)); do
            if [[ ${args[$i]} == "--jq" ]]; then
                expr="${args[$((i + 1))]:-}"
                if [[ ${expr} == -* ]]; then
                    echo "accepts at most 1 arg(s), received 2" >&2
                    exit 1
                fi
                printf '%s\n' "main"
                exit 0
            fi
        done
    fi
fi
exit 1
EOF
    chmod +x "${MOCK_BIN}/gh"
    PATH="${MOCK_BIN}:${PATH}"

    export CI_SWEEPER_WORKFLOW_RUN_ID="29554290605"
    export CI_SWEEPER_WORKFLOW_NAME="on-ci-push-markdown"
    export CI_SWEEPER_HEAD_SHA="56b6732"
    export CI_SWEEPER_HEAD_BRANCH="renovate/example"
    export CI_SWEEPER_EVENT_HEAD_BRANCH="main"
    export CI_SWEEPER_RUN_URL="https://example.com/run/1"

    FAILURES_JSON=()
    IGNORED_JSON=()
    collect_from_workflow_run_event
    [ "${#FAILURES_JSON[@]}" -eq 0 ]
    [ "${#IGNORED_JSON[@]}" -eq 1 ]
    [[ ${IGNORED_JSON[0]} == *"branch mismatch"* ]]
}

@test "collect_from_workflow_run_event ignores when head branch unknown" {
    MOCK_BIN="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${MOCK_BIN}"
    cat > "${MOCK_BIN}/gh" << 'EOF'
#!/usr/bin/env bash
if [[ "$1" == "run" && "$2" == "view" && $* == *"--json headBranch"* ]]; then
    printf '\n'
    exit 0
fi
exit 1
EOF
    chmod +x "${MOCK_BIN}/gh"
    PATH="${MOCK_BIN}:${PATH}"

    export CI_SWEEPER_WORKFLOW_RUN_ID="29554290605"
    export CI_SWEEPER_WORKFLOW_NAME="on-ci-push-markdown"
    export CI_SWEEPER_HEAD_SHA="56b6732"
    export CI_SWEEPER_HEAD_BRANCH="main"
    unset CI_SWEEPER_EVENT_HEAD_BRANCH
    export CI_SWEEPER_RUN_URL="https://example.com/run/1"

    FAILURES_JSON=()
    IGNORED_JSON=()
    collect_from_workflow_run_event
    [ "${#FAILURES_JSON[@]}" -eq 0 ]
    [ "${#IGNORED_JSON[@]}" -eq 1 ]
    [[ ${IGNORED_JSON[0]} == *"head branch unknown"* ]]
}

@test "collect_from_workflow_run_event accepts matching main scan context" {
    MOCK_BIN="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${MOCK_BIN}"
    cat > "${MOCK_BIN}/gh" << 'EOF'
#!/usr/bin/env bash
if [[ "$1" == "run" && "$2" == "view" ]]; then
    if [[ $* == *"--json headBranch"* ]]; then
        printf '%s\n' "main"
        exit 0
    fi
    if [[ $* == *"--json jobs"* ]]; then
        printf '%s\n' '{"name":"markdown-ci / lint","conclusion":"failure","url":"https://example.com/run/1"}'
        exit 0
    fi
    if [[ $* == *"--log-failed"* ]]; then
        printf '%s\n' "markdown-ci / lint	UNKNOWN STEP	##[error].apm/packages/common/x.md:1:1 MD038/no-space-in-code Spaces inside code"
        exit 0
    fi
fi
exit 1
EOF
    chmod +x "${MOCK_BIN}/gh"
    PATH="${MOCK_BIN}:${PATH}"

    export CI_SWEEPER_WORKFLOW_RUN_ID="29554290605"
    export CI_SWEEPER_WORKFLOW_NAME="on-ci-push-markdown"
    export CI_SWEEPER_HEAD_SHA="56b6732"
    export CI_SWEEPER_HEAD_BRANCH="main"
    export CI_SWEEPER_EVENT_HEAD_BRANCH="main"
    export CI_SWEEPER_RUN_URL="https://example.com/run/1"

    FAILURES_JSON=()
    IGNORED_JSON=()
    collect_from_workflow_run_event
    [ "${#FAILURES_JSON[@]}" -eq 1 ]
    [ "${#IGNORED_JSON[@]}" -eq 0 ]
    [[ ${FAILURES_JSON[0]} == *'"failure_type": "regression"'* ]]
    [[ ${FAILURES_JSON[0]} == *"MD038"* ]]
}

@test "collect_from_workflow_run_event falls back to EVENT_HEAD_BRANCH when api head empty" {
    MOCK_BIN="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${MOCK_BIN}"
    cat > "${MOCK_BIN}/gh" << 'EOF'
#!/usr/bin/env bash
if [[ "$1" == "run" && "$2" == "view" && $* == *"--json headBranch"* ]]; then
    # Simulate empty headBranch (API glitch / permissions)
    printf '\n'
    exit 0
fi
exit 1
EOF
    chmod +x "${MOCK_BIN}/gh"
    PATH="${MOCK_BIN}:${PATH}"

    export CI_SWEEPER_WORKFLOW_RUN_ID="29554290605"
    export CI_SWEEPER_WORKFLOW_NAME="on-ci-push-markdown"
    export CI_SWEEPER_HEAD_SHA="56b6732"
    export CI_SWEEPER_HEAD_BRANCH="renovate/example"
    export CI_SWEEPER_EVENT_HEAD_BRANCH="main"
    export CI_SWEEPER_RUN_URL="https://example.com/run/1"

    FAILURES_JSON=()
    IGNORED_JSON=()
    collect_from_workflow_run_event
    [ "${#FAILURES_JSON[@]}" -eq 0 ]
    [ "${#IGNORED_JSON[@]}" -eq 1 ]
    [[ ${IGNORED_JSON[0]} == *"branch mismatch"* ]]
}

@test "ci-sweeper debug log emits workflow-run notices on stderr" {
    MOCK_BIN="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${MOCK_BIN}"
    cat > "${MOCK_BIN}/gh" << 'EOF'
#!/usr/bin/env bash
if [[ "$1" == "run" && "$2" == "view" && $* == *"--json headBranch"* ]]; then
    printf '%s\n' "main"
    exit 0
fi
exit 1
EOF
    chmod +x "${MOCK_BIN}/gh"
    PATH="${MOCK_BIN}:${PATH}"

    export CI_SWEEPER_WORKFLOW_RUN_ID="29554290605"
    export CI_SWEEPER_WORKFLOW_NAME="on-ci-push-markdown"
    export CI_SWEEPER_HEAD_SHA="56b6732"
    export CI_SWEEPER_HEAD_BRANCH="renovate/example"
    export CI_SWEEPER_EVENT_HEAD_BRANCH="main"
    export CI_SWEEPER_RUN_URL="https://example.com/run/1"
    export CI_SWEEPER_DEBUG_LOG="true"

    local err_file
    err_file="${BATS_TEST_TMPDIR}/ci-sweeper-debug.err"
    FAILURES_JSON=()
    IGNORED_JSON=()
    collect_from_workflow_run_event 2> "${err_file}"
    grep -q 'ci-sweeper/workflow-run' "${err_file}"
    grep -q 'IGNORE branch mismatch' "${err_file}"
}

@test "fetch_log_excerpt prefers diagnostic error lines over summary tail" {
    MOCK_BIN="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${MOCK_BIN}"
    cat > "${MOCK_BIN}/gh" << 'EOF'
#!/usr/bin/env bash
if [[ "$1" == "run" && "$2" == "view" && $* == *"--log-failed"* ]]; then
    # Simulate many MD038 errors then a long summary tail (the production bug).
    i=0
    while [[ $i -lt 20 ]]; do
        printf '%s\n' "markdown-ci / lint	UNKNOWN STEP	##[error].apm/packages/common/.apm/instructions/instructions.instructions.md:12:115 MD038/no-space-in-code Spaces inside code span"
        i=$((i + 1))
    done
    j=0
    while [[ $j -lt 100 ]]; do
        printf '%s\n' "markdown-ci / lint	UNKNOWN STEP	##[group]Run echo \"## Results\" >> \$GITHUB_STEP_SUMMARY"
        printf '%s\n' "markdown-ci / lint	UNKNOWN STEP	STATUS: failure"
        j=$((j + 1))
    done
    exit 0
fi
exit 1
EOF
    chmod +x "${MOCK_BIN}/gh"
    PATH="${MOCK_BIN}:${PATH}"

    run fetch_log_excerpt "29554290605" "markdown-ci / lint"
    [ "$status" -eq 0 ]
    [[ $output == *"MD038"* ]]
    [[ $output == *"##[error]"* ]]
    [[ $output != *"STATUS: failure"* ]]
}

@test "collect_failures_for_run includes env-pattern failures in failures array" {
    run classify_failure_type "Please retry the deployment after fixing config"
    [ "$status" -eq 0 ]
    [ "$output" = "regression" ]
}

@test "classify_failure_type treats explicit retrying as flake" {
    run classify_failure_type "Job is retrying due to intermittent network"
    [ "$status" -eq 0 ]
    [ "$output" = "flake" ]
}

@test "sanitize_log_excerpt redacts github tokens" {
    run sanitize_log_excerpt "token=[REDACTED:API key param]" # pragma: allowlist secret
    [ "$status" -eq 0 ]
    [[ $output == *"[REDACTED]"* ]]
    [[ $output != *"ghp_"* ]]
}

@test "collect_failures_for_run includes secret-missing failures in failures array" {
    MOCK_BIN="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${MOCK_BIN}"
    cat > "${MOCK_BIN}/gh" << 'EOF'
#!/usr/bin/env bash
if [[ "$1" == "run" && "$2" == "view" ]]; then
    if [[ "$*" == *"--json jobs"* ]]; then
        printf '%s\n' '{"name":"deploy","conclusion":"failure","url":"https://example.com/run/2"}'
        exit 0
    fi
    if [[ "$*" == *"--log-failed"* ]]; then
        printf '%s\n' "Error: secret not found in credentials store"
        exit 0
    fi
fi
exit 1
EOF
    chmod +x "${MOCK_BIN}/gh"
    PATH="${MOCK_BIN}:${PATH}"

    FAILURES_JSON=()
    IGNORED_JSON=()
    collect_failures_for_run "ci-markdown" "99999" "abc123" "main" "https://example.com/run/2"
    [ "${#FAILURES_JSON[@]}" -eq 1 ]
    [ "${#IGNORED_JSON[@]}" -eq 0 ]
    [[ ${FAILURES_JSON[0]} == *'"failure_type": "env"'* ]]
}

@test "sanitize_log_excerpt redacts bearer tokens" {
    run sanitize_log_excerpt "Authorization: Bearer [REDACTED:Authorization header] token]"
    [ "$status" -eq 0 ]
    [[ $output == *"[REDACTED]"* ]]
    [[ $output != *"eyJhbGci"* ]]
}

@test "collect_failures_for_run emits valid JSON when log excerpt contains control characters" {
    MOCK_BIN="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${MOCK_BIN}"
    cat > "${MOCK_BIN}/gh" << 'EOF'
#!/usr/bin/env bash
if [[ "$1" == "run" && "$2" == "view" ]]; then
    if [[ "$*" == *"--json jobs"* ]]; then
        printf '%s\n' '{"name":"lint","conclusion":"failure","url":"https://example.com/run/3"}'
        exit 0
    fi
    if [[ "$*" == *"--log-failed"* ]]; then
        printf '%s\n' $'error\r\nwith\x01control'
        exit 0
    fi
fi
exit 1
EOF
    chmod +x "${MOCK_BIN}/gh"
    PATH="${MOCK_BIN}:${PATH}"

    FAILURES_JSON=()
    IGNORED_JSON=()
    collect_failures_for_run "ci-markdown" "54321" "abc123" "main" "https://example.com/run/3"
    [ "${#FAILURES_JSON[@]}" -eq 1 ]
    run jq -e . <<< "${FAILURES_JSON[0]}"
    [ "$status" -eq 0 ]
}

@test "detect_ci_failures rejects ledger path traversal outside dot loop" {
    run env CI_SWEEPER_LEDGER_FILE=".loop/../outside.json" bash "${DETECT_SCRIPT}" --scope all
    [ "$status" -eq 0 ]
    assert_detect_ci_failures_error_json "${output}" "stay under .loop/"
}

@test "detect_ci_failures script validates ok response format with mocked gh" {
    local workspace since_ref json mock_bin ledger_file

    workspace="$(bats_workspace_root)"
    if ! since_ref="$(bats_resolve_since_ref "${workspace}")"; then
        skip "not enough git history for relative since ref"
    fi

    mock_bin="${BATS_TEST_TMPDIR}/bin"
    ledger_file=".loop/bats-detect-ci-failures-${BATS_TEST_NUMBER}.json"
    mkdir -p "${mock_bin}" "${workspace}/.loop"
    cat > "${mock_bin}/gh" << 'EOF'
#!/usr/bin/env bash
if [[ "$1" == "run" && "$2" == "list" ]]; then
    printf '[]'
    exit 0
fi
exit 1
EOF
    chmod +x "${mock_bin}/gh"

    run bash -c "cd '${workspace}' && PATH='${mock_bin}:'\$PATH CI_SWEEPER_LEDGER_FILE='${ledger_file}' GITHUB_TOKEN='test-token' env -u GITHUB_ACTIONS -u CI_SWEEPER_DEBUG_LOG bash '${DETECT_SCRIPT}' --scope range --since '${since_ref}'"
    [ "$status" -eq 0 ]
    json="${output}"
    assert_detect_ci_failures_ok_json "${json}" "range" "${since_ref}"
    run jq -e '.skip == true and (.failures | length) == 0' <<< "${json}"
    [ "$status" -eq 0 ]
    rm -f "${workspace}/${ledger_file}"
}

@test "detect_ci_failures script validates error response format without token" {
    local workspace ledger_file

    workspace="$(bats_workspace_root)"
    ledger_file=".loop/bats-detect-ci-failures-no-token-${BATS_TEST_NUMBER}.json"
    mkdir -p "${workspace}/.loop"

    run bash -c "cd '${workspace}' && env -u GH_TOKEN -u GITHUB_TOKEN -u GITHUB_ACTIONS -u CI_SWEEPER_DEBUG_LOG CI_SWEEPER_LEDGER_FILE='${ledger_file}' bash '${DETECT_SCRIPT}' --scope all"
    [ "$status" -eq 0 ]
    assert_detect_ci_failures_error_json "${output}" "GH_TOKEN or GITHUB_TOKEN is required"
}
