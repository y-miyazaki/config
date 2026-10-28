#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .apm/packages/repo-maintenance/.apm/skills/test-gap/scripts/update_test_gap_ledger.sh
#
# Use cases:
# - update_test_gap_ledger creates the ledger file when it does not exist
# - update_test_gap_ledger exits 0 and leaves the ledger unchanged when no files changed
# - update_test_gap_ledger exits 0 when the execute branch is not resolvable
# - update_test_gap_ledger falls back to main when TARGET_JSON is invalid
# - update_test_gap_ledger increments attempts for an already recorded file
# - update_test_gap_ledger maps VERDICT to outcome when OUTCOME is unset
# - update_test_gap_ledger prefers TEST_GAP_BASE_BRANCH over the TARGET_JSON base branch
# - update_test_gap_ledger preserves unrelated entries
# - update_test_gap_ledger prunes entries older than the retention window
# - update_test_gap_ledger records changed test files from the execute branch diff
# - update_test_gap_ledger recovers from a corrupt ledger file
# - update_test_gap_ledger rejects absolute and parent-relative ledger paths
# - update_test_gap_ledger skips when outcome is error
# - update_test_gap_ledger skips when outcome is no-action
# - update_test_gap_ledger takes the base branch from TARGET_JSON to.branch when TEST_GAP_BASE_BRANCH is unset

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

LEDGER_SCRIPT="$(apm_skill_script_path test-gap update_test_gap_ledger.sh)"

# make_repo_with_test_change [base]: base commit on <base> (default main), one test file added on branch feature
make_repo_with_test_change() {
    local base="${1:-main}"
    git_test_repo_setup
    mkdir -p "${GIT_TEST_REPO}/test/bats" "${GIT_TEST_REPO}/.loop"
    printf 'base\n' > "${GIT_TEST_REPO}/README.md"
    git_test_repo_git add .
    git_test_repo_git commit -q -m "chore: init"
    git_test_repo_git branch -M "${base}"
    git_test_repo_git checkout -q -b feature
    printf '#!/usr/bin/env bats\n@test "x" { true; }\n' > "${GIT_TEST_REPO}/test/bats/foo.bats"
    git_test_repo_git add .
    git_test_repo_git commit -q -m "test: add foo"
    git_test_repo_git checkout -q "${base}"
}

@test "update_test_gap_ledger creates the ledger file when it does not exist" {
    make_repo_with_test_change
    rm -f "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json"
    git_test_repo_run "env OUTCOME=pr-created EXECUTE_BRANCH=feature TEST_GAP_BASE_BRANCH=main bash '${LEDGER_SCRIPT}'"
    [ "$status" -eq 0 ]
    [ -f "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json" ]
}

@test "update_test_gap_ledger exits 0 and leaves the ledger unchanged when no files changed" {
    git_test_repo_setup
    mkdir -p "${GIT_TEST_REPO}/.loop"
    printf 'base\n' > "${GIT_TEST_REPO}/README.md"
    git_test_repo_git add .
    git_test_repo_git commit -q -m "chore: init"
    git_test_repo_git branch -M main
    git_test_repo_git branch feature
    git_test_repo_run "env OUTCOME=pr-created EXECUTE_BRANCH=feature TEST_GAP_BASE_BRANCH=main bash '${LEDGER_SCRIPT}'"
    [ "$status" -eq 0 ]
    [ ! -f "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json" ]
}

@test "update_test_gap_ledger exits 0 when the execute branch is not resolvable" {
    make_repo_with_test_change
    git_test_repo_run "env OUTCOME=pr-created EXECUTE_BRANCH=does-not-exist TEST_GAP_BASE_BRANCH=main bash '${LEDGER_SCRIPT}'"
    [ "$status" -eq 0 ]
    [ ! -f "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json" ]
}

@test "update_test_gap_ledger falls back to main when TARGET_JSON is invalid" {
    make_repo_with_test_change
    git_test_repo_run "env OUTCOME=pr-created EXECUTE_BRANCH=feature TARGET_JSON='not json' bash '${LEDGER_SCRIPT}'"
    [ "$status" -eq 0 ]
    run jq -e '.entries["test/bats/foo.bats"].attempts == 1' "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json"
    [ "$status" -eq 0 ]
}

@test "update_test_gap_ledger increments attempts for an already recorded file" {
    make_repo_with_test_change
    printf '%s' '{"entries":{"test/bats/foo.bats":{"attempts":1,"last_loop_run_id":"100","outcome":"rejected","processed_at":"2999-01-01T00:00:00Z"}}}' > "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json"
    git_test_repo_run "env OUTCOME=rejected EXECUTE_BRANCH=feature TEST_GAP_BASE_BRANCH=main GITHUB_RUN_ID=222 bash '${LEDGER_SCRIPT}'"
    [ "$status" -eq 0 ]
    run jq -e '.entries["test/bats/foo.bats"].attempts == 2 and .entries["test/bats/foo.bats"].last_loop_run_id == "222"' "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json"
    [ "$status" -eq 0 ]
}

@test "update_test_gap_ledger maps VERDICT to outcome when OUTCOME is unset" {
    make_repo_with_test_change
    git_test_repo_run "env VERDICT=REJECT EXECUTE_BRANCH=feature TEST_GAP_BASE_BRANCH=main bash '${LEDGER_SCRIPT}'"
    [ "$status" -eq 0 ]
    run jq -e '.entries["test/bats/foo.bats"].outcome == "rejected"' "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json"
    [ "$status" -eq 0 ]
}

@test "update_test_gap_ledger prefers TEST_GAP_BASE_BRANCH over the TARGET_JSON base branch" {
    make_repo_with_test_change trunk
    # explicit base is unresolvable, so the ledger must stay untouched even though TARGET_JSON names trunk
    git_test_repo_run "env OUTCOME=pr-created EXECUTE_BRANCH=feature TEST_GAP_BASE_BRANCH=no-such-base TARGET_JSON='{\"to\":{\"branch\":\"trunk\"}}' bash '${LEDGER_SCRIPT}'"
    [ "$status" -eq 0 ]
    [ ! -f "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json" ]
    # explicit base resolves, TARGET_JSON names an unresolvable branch: the ledger is written
    git_test_repo_run "env OUTCOME=pr-created EXECUTE_BRANCH=feature TEST_GAP_BASE_BRANCH=trunk TARGET_JSON='{\"to\":{\"branch\":\"no-such-base\"}}' bash '${LEDGER_SCRIPT}'"
    [ "$status" -eq 0 ]
    [ -f "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json" ]
}

@test "update_test_gap_ledger preserves unrelated entries" {
    make_repo_with_test_change
    printf '%s' '{"entries":{"test/bats/other.bats":{"attempts":3,"last_loop_run_id":"9","outcome":"pr-created","processed_at":"2999-01-01T00:00:00Z"}}}' > "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json"
    git_test_repo_run "env OUTCOME=pr-created EXECUTE_BRANCH=feature TEST_GAP_BASE_BRANCH=main bash '${LEDGER_SCRIPT}'"
    [ "$status" -eq 0 ]
    run jq -e '.entries["test/bats/other.bats"].attempts == 3 and (.entries | has("test/bats/foo.bats"))' "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json"
    [ "$status" -eq 0 ]
}

@test "update_test_gap_ledger prunes entries older than the retention window" {
    make_repo_with_test_change
    printf '%s' '{"entries":{"test/bats/old.bats":{"attempts":1,"last_loop_run_id":"1","outcome":"pr-created","processed_at":"2000-01-01T00:00:00Z"}}}' > "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json"
    git_test_repo_run "env OUTCOME=pr-created EXECUTE_BRANCH=feature TEST_GAP_BASE_BRANCH=main TEST_GAP_RETENTION_DAYS=30 bash '${LEDGER_SCRIPT}'"
    [ "$status" -eq 0 ]
    run jq -e '(.entries | has("test/bats/old.bats") | not) and (.entries | has("test/bats/foo.bats"))' "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json"
    [ "$status" -eq 0 ]
}

@test "update_test_gap_ledger records changed test files from the execute branch diff" {
    make_repo_with_test_change
    git_test_repo_run "env OUTCOME=pr-created EXECUTE_BRANCH=feature TEST_GAP_BASE_BRANCH=main GITHUB_RUN_ID=111 bash '${LEDGER_SCRIPT}'"
    [ "$status" -eq 0 ]
    run jq -e '.entries["test/bats/foo.bats"].attempts == 1 and .entries["test/bats/foo.bats"].outcome == "pr-created" and .entries["test/bats/foo.bats"].last_loop_run_id == "111"' "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json"
    [ "$status" -eq 0 ]
}

@test "update_test_gap_ledger recovers from a corrupt ledger file" {
    make_repo_with_test_change
    printf '%s' 'not json' > "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json"
    git_test_repo_run "env OUTCOME=pr-created EXECUTE_BRANCH=feature TEST_GAP_BASE_BRANCH=main bash '${LEDGER_SCRIPT}'"
    [ "$status" -eq 0 ]
    run jq -e '.entries["test/bats/foo.bats"].attempts == 1' "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json"
    [ "$status" -eq 0 ]
}

@test "update_test_gap_ledger rejects absolute and parent-relative ledger paths" {
    make_repo_with_test_change
    git_test_repo_run "env OUTCOME=pr-created EXECUTE_BRANCH=feature TEST_GAP_BASE_BRANCH=main TEST_GAP_LEDGER_FILE=/tmp/escape.json bash '${LEDGER_SCRIPT}'"
    [ "$status" -eq 0 ]
    [ ! -f /tmp/escape.json ]
    git_test_repo_run "env OUTCOME=pr-created EXECUTE_BRANCH=feature TEST_GAP_BASE_BRANCH=main TEST_GAP_LEDGER_FILE=../escape.json bash '${LEDGER_SCRIPT}'"
    [ "$status" -eq 0 ]
    [ ! -f "${GIT_TEST_REPO}/../escape.json" ]
}

@test "update_test_gap_ledger skips when outcome is error" {
    make_repo_with_test_change
    git_test_repo_run "env OUTCOME=error EXECUTE_BRANCH=feature TEST_GAP_BASE_BRANCH=main bash '${LEDGER_SCRIPT}'"
    [ "$status" -eq 0 ]
    [ ! -f "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json" ]
}

@test "update_test_gap_ledger skips when outcome is no-action" {
    make_repo_with_test_change
    git_test_repo_run "env OUTCOME=no-action EXECUTE_BRANCH=feature TEST_GAP_BASE_BRANCH=main bash '${LEDGER_SCRIPT}'"
    [ "$status" -eq 0 ]
    [ ! -f "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json" ]
}

@test "update_test_gap_ledger takes the base branch from TARGET_JSON to.branch when TEST_GAP_BASE_BRANCH is unset" {
    make_repo_with_test_change trunk
    git_test_repo_run "env OUTCOME=pr-created EXECUTE_BRANCH=feature TARGET_JSON='{\"mode\":\"integration\",\"key\":\"integration:trunk\",\"to\":{\"branch\":\"trunk\"}}' bash '${LEDGER_SCRIPT}'"
    [ "$status" -eq 0 ]
    run jq -e '.entries["test/bats/foo.bats"].attempts == 1' "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json"
    [ "$status" -eq 0 ]
}
