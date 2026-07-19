#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-state-promote/lib/run.sh

# Use cases:
# - merged PR promotes pending.sha to last_sha on branch_state
# - closed-without-merge clears pending only
# - skip_state_pr warns and exits cleanly when direct push is blocked
# - opens auto-merge state PR when direct push is blocked

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

RUN_SCRIPT="$(bats_workspace_root)/.github/actions/loop-state-promote/lib/run.sh"

state_promote_git_setup() {
    STATE_PROMOTE_BARE="${BATS_TEST_TMPDIR}/origin.git"
    STATE_PROMOTE_WORK="${BATS_TEST_TMPDIR}/work"
    rm -rf "${STATE_PROMOTE_BARE}" "${STATE_PROMOTE_WORK}"
    git init -q "${STATE_PROMOTE_WORK}"
    git -C "${STATE_PROMOTE_WORK}" config user.email "test@example.com"
    git -C "${STATE_PROMOTE_WORK}" config user.name "Test User"
    git -C "${STATE_PROMOTE_WORK}" checkout -q -b main
    mkdir -p "${STATE_PROMOTE_WORK}/.loop"
    printf '%s\n' \
        '{"targets":{"integration:main":{"last_sha":"oldsha000000","pending":{"sha":"newsha111111","pr":42}}}}' \
        > "${STATE_PROMOTE_WORK}/.loop/state-test.json"
    git -C "${STATE_PROMOTE_WORK}" add .loop/state-test.json
    git -C "${STATE_PROMOTE_WORK}" commit -q -m "chore: init state"
    git init -q --bare "${STATE_PROMOTE_BARE}"
    git -C "${STATE_PROMOTE_WORK}" remote add origin "${STATE_PROMOTE_BARE}"
    git -C "${STATE_PROMOTE_WORK}" push -q -u origin main
}

state_promote_run() {
    run bash -c "cd '${STATE_PROMOTE_WORK}' && $(printf '%q ' "${@}") bash '${RUN_SCRIPT}'"
}

state_promote_block_push() {
    cat > "${STATE_PROMOTE_BARE}/hooks/pre-receive" << 'EOF'
#!/bin/sh
while read -r _ _ refname; do
    case "${refname}" in
        refs/heads/main) exit 1 ;;
    esac
done
exit 0
EOF
    chmod +x "${STATE_PROMOTE_BARE}/hooks/pre-receive"
}

state_promote_mock_gh() {
    MOCK_BIN="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${MOCK_BIN}"
    cat > "${MOCK_BIN}/gh" << 'EOF'
#!/bin/bash
if [[ "$1" == "pr" && "$2" == "create" ]]; then
    echo "https://github.com/test/repo/pull/99"
    exit 0
fi
if [[ "$1" == "pr" && "$2" == "merge" ]]; then
    exit 0
fi
printf 'unexpected gh: %s\n' "$*" >&2
exit 1
EOF
    chmod +x "${MOCK_BIN}/gh"
    export PATH="${MOCK_BIN}:${PATH}"
}

setup() {
    state_promote_git_setup
}

@test "run.sh clears pending when PR closed without merge" {
    state_promote_run \
        GH_TOKEN='test-token' \
        MERGED='false' \
        PR_NUMBER='42' \
        STATE_PUSH_BRANCH='main' \
        GITHUB_REPOSITORY='test/repo' \
        GITHUB_RUN_ID='1' \
        GITHUB_RUN_ATTEMPT='1'
    [ "$status" -eq 0 ]
    [[ $output == *"State clear_pending pushed to main"* ]]
    run jq -e \
        '.targets["integration:main"].last_sha == "oldsha000000"
         and (.targets["integration:main"] | has("pending") | not)
         and .targets["integration:main"].outcome == "pr-closed"' \
        "${STATE_PROMOTE_WORK}/.loop/state-test.json"
    [ "$status" -eq 0 ]
}

@test "run.sh opens state promote PR when direct push is blocked" {
    state_promote_mock_gh
    state_promote_block_push

    state_promote_run \
        GH_TOKEN='test-token' \
        MERGED='true' \
        PR_NUMBER='42' \
        SKIP_STATE_PR='false' \
        STATE_PUSH_BRANCH='main' \
        GITHUB_REPOSITORY='test/repo' \
        GITHUB_RUN_ID='2' \
        GITHUB_RUN_ATTEMPT='1'
    [ "$status" -eq 0 ]
    [[ $output == *"Direct push blocked; opening state promote PR."* ]]
    [[ $output == *"State promote PR queued for auto-merge"* ]]
}

@test "run.sh promotes pending.sha to last_sha when merged" {
    state_promote_run \
        GH_TOKEN='test-token' \
        MERGED='true' \
        PR_NUMBER='42' \
        STATE_PUSH_BRANCH='main' \
        GITHUB_REPOSITORY='test/repo' \
        GITHUB_RUN_ID='3' \
        GITHUB_RUN_ATTEMPT='1'
    [ "$status" -eq 0 ]
    [[ $output == *"State promote pushed to main"* ]]
    run jq -e \
        '.targets["integration:main"].last_sha == "newsha111111"
         and (.targets["integration:main"] | has("pending") | not)
         and .targets["integration:main"].outcome == "merged"
         and .targets["integration:main"].consecutive_failures == 0' \
        "${STATE_PROMOTE_WORK}/.loop/state-test.json"
    [ "$status" -eq 0 ]
}

@test "run.sh skips state PR fallback when skip_state_pr is true" {
    state_promote_block_push

    state_promote_run \
        GH_TOKEN='test-token' \
        MERGED='true' \
        PR_NUMBER='42' \
        SKIP_STATE_PR='true' \
        STATE_PUSH_BRANCH='main' \
        GITHUB_REPOSITORY='test/repo' \
        GITHUB_RUN_ID='4' \
        GITHUB_RUN_ATTEMPT='1'
    [ "$status" -eq 0 ]
    [[ $output == *"skip_state_pr=true"* ]]
}
