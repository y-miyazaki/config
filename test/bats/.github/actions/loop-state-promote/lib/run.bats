#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-state-promote/lib/run.sh

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

PROMOTE_SCRIPT="$(bats_workspace_root)/.github/actions/loop-state-promote/lib/run.sh"

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
        '{"targets":{"integration:main":{"pending":{"sha":"newsha111111","pr":42}}}}' \
        > "${STATE_PROMOTE_WORK}/.loop/state-changelog.json"
    git -C "${STATE_PROMOTE_WORK}" add .loop/state-changelog.json
    git -C "${STATE_PROMOTE_WORK}" commit -q -m "chore: init state"
    git init -q --bare "${STATE_PROMOTE_BARE}"
    git -C "${STATE_PROMOTE_WORK}" remote add origin "${STATE_PROMOTE_BARE}"
    git -C "${STATE_PROMOTE_WORK}" push -q -u origin main
}

state_promote_run() {
    run bash -c "cd '${STATE_PROMOTE_WORK}' && $(printf '%q ' "${@}") bash '${PROMOTE_SCRIPT}'"
}

setup() {
    state_promote_git_setup
}

@test "run.sh clears pending when merged is false" {
    state_promote_run \
        GH_TOKEN='test-token' \
        GITHUB_REPOSITORY='test/repo' \
        MERGED='false' \
        PR_NUMBER='42' \
        STATE_PUSH_BRANCH='main'
    [ "$status" -eq 0 ]
    run jq -e \
        '.targets["integration:main"].outcome == "pr-closed"
         and (.targets["integration:main"] | has("pending") | not)
         and .targets["integration:main"].last_sha == null' \
        "${STATE_PROMOTE_WORK}/.loop/state-changelog.json"
    [ "$status" -eq 0 ]
}

@test "run.sh exits cleanly when no pending state matches PR" {
    state_promote_run \
        GH_TOKEN='test-token' \
        GITHUB_REPOSITORY='test/repo' \
        MERGED='true' \
        PR_NUMBER='99' \
        STATE_PUSH_BRANCH='main'
    [ "$status" -eq 0 ]
    [[ $output == *"No pending state matched PR #99 on main."* ]]
}

@test "run.sh promotes pending to last_sha when merged is true" {
    state_promote_run \
        GH_TOKEN='test-token' \
        GITHUB_REPOSITORY='test/repo' \
        MERGED='true' \
        PR_NUMBER='42' \
        STATE_PUSH_BRANCH='main'
    [ "$status" -eq 0 ]
    run jq -e \
        '.targets["integration:main"].last_sha == "newsha111111"
         and .targets["integration:main"].outcome == "merged"
         and (.targets["integration:main"] | has("pending") | not)' \
        "${STATE_PROMOTE_WORK}/.loop/state-changelog.json"
    [ "$status" -eq 0 ]
}
