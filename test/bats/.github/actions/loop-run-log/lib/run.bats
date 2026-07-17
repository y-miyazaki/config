#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-run-log/lib/run.sh

# Use cases:
# - run.sh rejects missing loop_name
# - run.sh appends entry, commits, and writes entry_json output
# - run.sh computes duration when duration input is empty

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

RUN_SCRIPT="$(bats_workspace_root)/.github/actions/loop-run-log/lib/run.sh"

run_log_git_setup() {
    RUN_LOG_BARE="${BATS_TEST_TMPDIR}/origin.git"
    RUN_LOG_WORK="${BATS_TEST_TMPDIR}/work"
    rm -rf "${RUN_LOG_BARE}" "${RUN_LOG_WORK}"
    git init -q "${RUN_LOG_WORK}"
    git -C "${RUN_LOG_WORK}" config user.email "test@example.com"
    git -C "${RUN_LOG_WORK}" config user.name "Test User"
    git -C "${RUN_LOG_WORK}" checkout -q -b main
    mkdir -p "${RUN_LOG_WORK}/.loop"
    printf '# Loop Run Log\n' > "${RUN_LOG_WORK}/.loop/loop-run-log.md"
    git -C "${RUN_LOG_WORK}" add .loop/loop-run-log.md
    git -C "${RUN_LOG_WORK}" commit -q -m "chore: init run log"
    git init -q --bare "${RUN_LOG_BARE}"
    git -C "${RUN_LOG_WORK}" remote add origin "${RUN_LOG_BARE}"
    git -C "${RUN_LOG_WORK}" push -q -u origin main
}

run_log_run() {
    run bash -c "cd '${RUN_LOG_WORK}' && $(printf '%q ' "${@}") bash '${RUN_SCRIPT}'"
}

setup() {
    run_log_git_setup
    GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/github_output"
    : > "${GITHUB_OUTPUT}"
}

@test "run.sh rejects missing loop_name" {
    run_log_run \
        TOKEN='test-token' \
        OUTCOME='skipped' \
        WORKFLOW_RUN='42' \
        GITHUB_OUTPUT="${GITHUB_OUTPUT}"
    [ "$status" -eq 1 ]
}

@test "run.sh appends entry, commits, and writes entry_json output" {
    run_log_run \
        TOKEN='test-token' \
        LOOP_NAME='docs-triage' \
        OUTCOME='skipped' \
        SKIP_REASON='budget' \
        RUN_LOG_FILE='.loop/loop-run-log.md' \
        BASE_BRANCH='main' \
        WORKFLOW_RUN='42' \
        TOKENS_ESTIMATE='52000' \
        DURATION_S_INPUT='7' \
        GITHUB_OUTPUT="${GITHUB_OUTPUT}"
    [ "$status" -eq 0 ]
    [[ $output == *"Run log pushed directly."* ]]

    run tail -n 1 "${RUN_LOG_WORK}/.loop/loop-run-log.md"
    [ "$status" -eq 0 ]
    assert_loop_run_log_entry_json "${output}"
    [ "$(jq -r '.pattern' <<< "${output}")" = "docs-triage" ]
    [ "$(jq -r '.outcome' <<< "${output}")" = "skipped" ]
    [ "$(jq -r '.skip_reason' <<< "${output}")" = "budget" ]
    [ "$(jq -r '.workflow_run' <<< "${output}")" = "42" ]
    [ "$(jq -r '.duration_s' <<< "${output}")" = "7" ]

    run grep -E '^entry_json<<' "${GITHUB_OUTPUT}"
    [ "$status" -eq 0 ]
    run awk '/^entry_json<</{found=1;next} found{print; exit}' "${GITHUB_OUTPUT}"
    [ "$status" -eq 0 ]
    assert_loop_run_log_entry_json "${output}"
}

@test "run.sh computes duration when duration input is empty" {
    local started
    started="$(date -u -d '5 seconds ago' +%Y-%m-%dT%H:%M:%SZ)"

    run_log_run \
        TOKEN='test-token' \
        LOOP_NAME='docs-triage' \
        OUTCOME='no-changes' \
        SKIP_REASON='none' \
        RUN_LOG_FILE='.loop/loop-run-log.md' \
        BASE_BRANCH='main' \
        WORKFLOW_RUN='99' \
        RUN_STARTED_AT="${started}" \
        GITHUB_OUTPUT="${GITHUB_OUTPUT}"
    [ "$status" -eq 0 ]

    run tail -n 1 "${RUN_LOG_WORK}/.loop/loop-run-log.md"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.duration_s' <<< "${output}")" -ge 3 ]
}
