#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154,SC2317

# Tests for .github/actions/loop-detect/lib/detect.sh (pending PR gate)

# Use cases:
# - OPEN pending on integration → block candidate; detect script not invoked
# - CLOSED/MERGED pending on integration → stale; continue into detect
# - OPEN pending on pull_request target → block that candidate
# - CLOSED pending on pull_request target → continue into detect
# - empty candidates + PENDING_PR_BLOCKED → skip_reason=pending_pr (main branch)
# - circuit_breaker takes precedence over pending_pr when both counters set

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

install_gh_pr_state_mock() {
    local state="$1"
    local mock_bin="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${mock_bin}"
    cat > "${mock_bin}/gh" << EOF
#!/usr/bin/env bash
if [[ \$1 == "pr" && \$2 == "view" ]]; then
    printf '%s\\n' "${state}"
    exit 0
fi
exit 1
EOF
    chmod +x "${mock_bin}/gh"
    export PATH="${mock_bin}:${PATH}"
}

pending_detect_repo_setup() {
    PENDING_REPO="${BATS_TEST_TMPDIR}/repo"
    rm -rf "${PENDING_REPO}"
    mkdir -p "${PENDING_REPO}/.loop"
    git init -q "${PENDING_REPO}"
    git -C "${PENDING_REPO}" config user.email "test@example.com"
    git -C "${PENDING_REPO}" config user.name "Test User"
    git -C "${PENDING_REPO}" checkout -q -b main
    printf '%s\n' "fixture" > "${PENDING_REPO}/README.md"
    git -C "${PENDING_REPO}" add README.md
    git -C "${PENDING_REPO}" commit -q -m "chore: init"

    printf '%s\n' \
        '{"targets":{"integration:main":{"last_sha":"deadbeef","pending":{"sha":"cafebabe","pr":42},"consecutive_failures":0,"open_rejections":[]}}}' \
        > "${PENDING_REPO}/.loop/state-ci-sweeper.json"

    DETECT_SCRIPT="${BATS_TEST_TMPDIR}/detect.sh"
    cat > "${DETECT_SCRIPT}" << 'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"status":"ok","skip":true,"failures":[],"ignored":[]}'
EOF
    chmod +x "${DETECT_SCRIPT}"
}

setup() {
    bats_source_rel ".github/actions/loop-detect/lib/detect.sh"
    pending_detect_repo_setup
    STATE_FILE="${PENDING_REPO}/.loop/state-ci-sweeper.json"
    BASE_BRANCH="main"
    SKILL_NAME="loop-ci-sweeper"
    LEVEL="L2"
    ALLOWLIST="*"
    PROMPT_INSTRUCTIONS=""
    LOOP_FINALIZE_INTEGRATION="open_pr"
    PENDING_PR_BLOCKED=0
    CIRCUIT_BREAKER_BLOCKED=0
    CANDIDATES_JSON=()
    export GH_TOKEN='test-token'
    export DETECT_SCRIPT STATE_FILE BASE_BRANCH
}

@test "append_integration_candidate blocks and skips detect when pending PR is OPEN" {
    local detect_calls="${BATS_TEST_TMPDIR}/detect_calls"
    : > "${detect_calls}"

    install_gh_pr_state_mock "OPEN"
    cat > "${DETECT_SCRIPT}" << EOF
#!/usr/bin/env bash
echo called >> '${detect_calls}'
printf '%s\\n' '{"status":"ok","skip":true,"failures":[],"ignored":[]}'
EOF
    chmod +x "${DETECT_SCRIPT}"

    checkout_context() {
        cd "${PENDING_REPO}" || return 1
        return 0
    }

    append_integration_candidate "main"

    [ "${PENDING_PR_BLOCKED}" -eq 1 ]
    [ "${#CANDIDATES_JSON[@]}" -eq 0 ]
    [ ! -s "${detect_calls}" ]
}

@test "append_integration_candidate continues into detect when pending PR is CLOSED" {
    local detect_calls="${BATS_TEST_TMPDIR}/detect_calls"
    : > "${detect_calls}"

    install_gh_pr_state_mock "CLOSED"
    cat > "${DETECT_SCRIPT}" << EOF
#!/usr/bin/env bash
echo called >> '${detect_calls}'
printf '%s\\n' '{"status":"ok","skip":true,"failures":[],"ignored":[]}'
EOF
    chmod +x "${DETECT_SCRIPT}"

    checkout_context() {
        cd "${PENDING_REPO}" || return 1
        return 0
    }

    append_integration_candidate "main"

    [ "${PENDING_PR_BLOCKED}" -eq 0 ]
    [ "${#CANDIDATES_JSON[@]}" -eq 0 ]
    [ -s "${detect_calls}" ]
}

@test "append_integration_candidate continues into detect when pending PR is MERGED" {
    local detect_calls="${BATS_TEST_TMPDIR}/detect_calls"
    : > "${detect_calls}"

    install_gh_pr_state_mock "MERGED"
    cat > "${DETECT_SCRIPT}" << EOF
#!/usr/bin/env bash
echo called >> '${detect_calls}'
printf '%s\\n' '{"status":"ok","skip":true,"failures":[],"ignored":[]}'
EOF
    chmod +x "${DETECT_SCRIPT}"

    checkout_context() {
        cd "${PENDING_REPO}" || return 1
        return 0
    }

    # Assert we pass the pending gate and invoke detect (skip=true → no candidate).
    append_integration_candidate "main"

    [ "${PENDING_PR_BLOCKED}" -eq 0 ]
    [ "${#CANDIDATES_JSON[@]}" -eq 0 ]
    [ -s "${detect_calls}" ]
}

@test "append_pull_request_candidate blocks when that target has OPEN pending" {
    install_gh_pr_state_mock "OPEN"
    printf '%s\n' \
        '{"targets":{"pull_request:7":{"pending":{"sha":"abc","pr":99},"consecutive_failures":0,"open_rejections":[]}}}' \
        > "${STATE_FILE}"

    checkout_context() {
        cd "${PENDING_REPO}" || return 1
        return 0
    }

    PENDING_PR_BLOCKED=0
    append_pull_request_candidate '{"number":7,"headRefName":"feat/x","headRefOid":"abc","baseRefName":"main"}'

    [ "${PENDING_PR_BLOCKED}" -eq 1 ]
    [ "${#CANDIDATES_JSON[@]}" -eq 0 ]
}

@test "append_pull_request_candidate continues into detect when pending PR is CLOSED" {
    local detect_calls="${BATS_TEST_TMPDIR}/detect_calls"
    : > "${detect_calls}"

    install_gh_pr_state_mock "CLOSED"
    printf '%s\n' \
        '{"targets":{"pull_request:7":{"pending":{"sha":"abc","pr":99},"consecutive_failures":0,"open_rejections":[]}}}' \
        > "${STATE_FILE}"

    cat > "${DETECT_SCRIPT}" << EOF
#!/usr/bin/env bash
echo called >> '${detect_calls}'
printf '%s\\n' '{"status":"ok","skip":true,"failures":[],"ignored":[]}'
EOF
    chmod +x "${DETECT_SCRIPT}"

    checkout_context() {
        cd "${PENDING_REPO}" || return 1
        return 0
    }

    PENDING_PR_BLOCKED=0
    append_pull_request_candidate '{"number":7,"headRefName":"feat/x","headRefOid":"abc","baseRefName":"main"}'

    [ "${PENDING_PR_BLOCKED}" -eq 0 ]
    [ -s "${detect_calls}" ]
}

@test "empty candidates with PENDING_PR_BLOCKED emit skip_reason pending_pr" {
    # Mirrors detect.sh main() empty-candidate branch after append_* gates.
    local github_output

    install_gh_pr_state_mock "OPEN"
    checkout_context() {
        cd "${PENDING_REPO}" || return 1
        return 0
    }
    append_integration_candidate "main"
    [ "${PENDING_PR_BLOCKED}" -eq 1 ]
    [ "${#CANDIDATES_JSON[@]}" -eq 0 ]

    github_output="$(mktemp)"
    GITHUB_OUTPUT="${github_output}"
    if [[ ${CIRCUIT_BREAKER_BLOCKED} -gt 0 ]]; then
        write_detect_outputs "false" "circuit_breaker" "[]"
    elif [[ ${PENDING_PR_BLOCKED} -gt 0 ]]; then
        write_detect_outputs "false" "pending_pr" "[]"
    else
        write_detect_outputs "false" "no_changes" "[]"
    fi

    run grep -Fx 'should_run=false' "${github_output}"
    [ "$status" -eq 0 ]
    run grep -Fx 'skip_reason=pending_pr' "${github_output}"
    [ "$status" -eq 0 ]
}

@test "empty candidates prefer circuit_breaker over pending_pr when both set" {
    local github_output

    PENDING_PR_BLOCKED=1
    CIRCUIT_BREAKER_BLOCKED=1
    CANDIDATES_JSON=()

    github_output="$(mktemp)"
    GITHUB_OUTPUT="${github_output}"
    if [[ ${CIRCUIT_BREAKER_BLOCKED} -gt 0 ]]; then
        write_detect_outputs "false" "circuit_breaker" "[]"
    elif [[ ${PENDING_PR_BLOCKED} -gt 0 ]]; then
        write_detect_outputs "false" "pending_pr" "[]"
    else
        write_detect_outputs "false" "no_changes" "[]"
    fi

    run grep -Fx 'skip_reason=circuit_breaker' "${github_output}"
    [ "$status" -eq 0 ]
}
