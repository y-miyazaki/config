#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

bats_require_minimum_version 1.5.0

# Tests for .github/actions/loop-finalize/lib/create_pr.sh
#
# Use cases:
# - create_pr exits cleanly after PR creation (EXIT trap must not reference local scope)
# - create_pr records redacted failure when gh pr create fails

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    local candidate

    MOCK_BIN="${BATS_TEST_TMPDIR}/bin"
    HANDOFF_DIR="${BATS_TEST_TMPDIR}/loop-handoff"
    mkdir -p "${MOCK_BIN}"

    cat > "${MOCK_BIN}/gh" << 'EOF'
#!/bin/bash
if [[ "$1" == "pr" && "$2" == "create" ]]; then
    if [[ -n ${GH_ARGV_FILE:-} ]]; then
        printf '%s\n' "$*" > "${GH_ARGV_FILE}"
    fi
    if [[ "${GH_PR_CREATE_FAIL:-}" == "1" ]]; then
        echo "error: x-access-token:ghp_[REDACTED:GitHub token] denied" >&2
        exit 1
    fi
    echo "https://github.com/example/repo/pull/42"
    exit 0
fi
if [[ "$1" == "pr" && "$2" == "view" ]]; then
    echo '{"number":42}'
    exit 0
fi
printf 'unexpected gh: %s\n' "$*" >&2
exit 1
EOF
    chmod +x "${MOCK_BIN}/gh"
    export PATH="${MOCK_BIN}:${PATH}"

    bats_source_rel ".github/actions/lib/loop/handoff.sh"
    candidate='{"target_json":{"key":"integration:main"},"prompt":"p","verifier_context":"","result":{"failures":[]}}'
    loop_handoff_write_bundle "${HANDOFF_DIR}" "${candidate}"
}

@test "create_pr exits cleanly after successful PR creation" {
    local script

    script="$(bats_workspace_root)/.github/actions/loop-finalize/lib/create_pr.sh"
    export BRANCH="loop/test-branch"
    export DETECT_RESULT_JSON="{}"
    export GH_TOKEN="test-token"
    export GITHUB_REPOSITORY="example/repo"
    export HANDOFF_KEY="integration:main"
    export LOOP_HANDOFF_DIR="${HANDOFF_DIR}"
    export NOTIFY_CONTEXT_JSON='{"changed_files":[],"agent_report_summary":"done"}'
    export PR_BASE_BRANCH="main"
    export PR_BODY="Automated update"
    export PR_TITLE="chore: test"
    export SKIP_REASON="none"
    export TARGET_JSON='{"key":"integration:main"}'

    run bash "${script}"
    [ "$status" -eq 0 ]
    [[ $output == *"https://github.com/example/repo/pull/42"* ]]
}

@test "create_pr records redacted failure when gh pr create fails" {
    local script failure_file

    script="$(bats_workspace_root)/.github/actions/loop-finalize/lib/create_pr.sh"
    failure_file="${BATS_TEST_TMPDIR}/failure.json"
    export BRANCH="loop/test-branch"
    export DETECT_RESULT_JSON="{}"
    export GH_PR_CREATE_FAIL="1"
    export GH_TOKEN="test-token"
    export GITHUB_REPOSITORY="example/repo"
    export HANDOFF_KEY="integration:main"
    export LOOP_FAILURE_FILE="${failure_file}"
    export LOOP_HANDOFF_DIR="${HANDOFF_DIR}"
    export NOTIFY_CONTEXT_JSON='{"changed_files":[],"agent_report_summary":"done"}'
    export PR_BASE_BRANCH="main"
    export PR_BODY="Automated update"
    export PR_TITLE="chore: test"
    export SKIP_REASON="none"
    export TARGET_JSON='{"key":"integration:main"}'

    run bash "${script}"
    [ "$status" -eq 1 ]
    [ -f "${failure_file}" ]
    [ "$(jq -r '.failure_stage' "${failure_file}")" = "finalize_pr" ]
    [[ "$(jq -r '.failure_message' "${failure_file}")" == *"[REDACTED]"* ]]
    [[ "$(jq -r '.failure_message' "${failure_file}")" != *"ghp_"* ]]
}

@test "create_pr passes --draft when PR_DRAFT=true" {
    local script

    script="$(bats_workspace_root)/.github/actions/loop-finalize/lib/create_pr.sh"
    export GH_ARGV_FILE="${BATS_TEST_TMPDIR}/gh-argv"
    export BRANCH="loop/test-branch"
    export DETECT_RESULT_JSON="{}"
    export GH_TOKEN="test-token"
    export GITHUB_REPOSITORY="example/repo"
    export HANDOFF_KEY="integration:main"
    export LOOP_HANDOFF_DIR="${HANDOFF_DIR}"
    export NOTIFY_CONTEXT_JSON='{"changed_files":[],"agent_report_summary":"done"}'
    export PR_BASE_BRANCH="main"
    export PR_BODY="Automated update"
    export PR_DRAFT="true"
    export PR_TITLE="chore: test"
    export SKIP_REASON="none"
    export TARGET_JSON='{"key":"integration:main"}'

    run bash "${script}"
    [ "$status" -eq 0 ]
    grep -q -- '--draft' "${GH_ARGV_FILE}"
}

@test "create_pr omits --draft when PR_DRAFT unset or false" {
    local script

    script="$(bats_workspace_root)/.github/actions/loop-finalize/lib/create_pr.sh"
    export GH_ARGV_FILE="${BATS_TEST_TMPDIR}/gh-argv"
    export BRANCH="loop/test-branch"
    export DETECT_RESULT_JSON="{}"
    export GH_TOKEN="test-token"
    export GITHUB_REPOSITORY="example/repo"
    export HANDOFF_KEY="integration:main"
    export LOOP_HANDOFF_DIR="${HANDOFF_DIR}"
    export NOTIFY_CONTEXT_JSON='{"changed_files":[],"agent_report_summary":"done"}'
    export PR_BASE_BRANCH="main"
    export PR_BODY="Automated update"
    export PR_DRAFT="false"
    export PR_TITLE="chore: test"
    export SKIP_REASON="none"
    export TARGET_JSON='{"key":"integration:main"}'

    run bash "${script}"
    [ "$status" -eq 0 ]
    run ! grep -q -- '--draft' "${GH_ARGV_FILE}"
}
