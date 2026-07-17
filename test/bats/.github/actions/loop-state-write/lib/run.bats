#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-state-write/lib/run.sh

# Use cases:
# - validation: missing target_key / invalid state push branch
# - advance mode: last_sha + outcome; reset consecutive_failures on pr-created
# - rejected outcome increments consecutive_failures / stores open_rejections
# - acting_on set/clear without target write; no-op when unchanged
# - metadata mode: outcome without advancing last_sha
# - pending mode: record pending without advancing last_sha (finalize open_pr path)
# - promote mode: pending.sha → last_sha; clear pending
# - clear_pending mode: clear pending only; last_sha unchanged

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

RUN_SCRIPT="$(bats_workspace_root)/.github/actions/loop-state-write/lib/run.sh"

state_write_git_setup() {
    STATE_WRITE_BARE="${BATS_TEST_TMPDIR}/origin.git"
    STATE_WRITE_WORK="${BATS_TEST_TMPDIR}/work"
    rm -rf "${STATE_WRITE_BARE}" "${STATE_WRITE_WORK}"
    git init -q "${STATE_WRITE_WORK}"
    git -C "${STATE_WRITE_WORK}" config user.email "test@example.com"
    git -C "${STATE_WRITE_WORK}" config user.name "Test User"
    git -C "${STATE_WRITE_WORK}" checkout -q -b main
    mkdir -p "${STATE_WRITE_WORK}/.loop"
    printf '%s\n' '{"targets":{}}' > "${STATE_WRITE_WORK}/.loop/state.json"
    git -C "${STATE_WRITE_WORK}" add .loop/state.json
    git -C "${STATE_WRITE_WORK}" commit -q -m "chore: init state"
    git init -q --bare "${STATE_WRITE_BARE}"
    git -C "${STATE_WRITE_WORK}" remote add origin "${STATE_WRITE_BARE}"
    git -C "${STATE_WRITE_WORK}" push -q -u origin main
}

state_write_run() {
    run bash -c "cd '${STATE_WRITE_WORK}' && $(printf '%q ' "${@}") bash '${RUN_SCRIPT}'"
}

state_write_seed() {
    git -C "${STATE_WRITE_WORK}" add .loop/state.json
    git -C "${STATE_WRITE_WORK}" commit -q -m "test: seed state"
    git -C "${STATE_WRITE_WORK}" push -q origin main
}

setup() {
    state_write_git_setup
}

@test "run.sh rejects missing target_key" {
    state_write_run \
        GH_TOKEN='test-token' \
        STATE_FILE='.loop/state.json' \
        BASE_BRANCH='main' \
        TARGET_KEY='' \
        WRITE_TARGET_STATE='false' \
        ACTING_ON_ACTION='' \
        GITHUB_REPOSITORY='test/repo' \
        GITHUB_RUN_ID='1' \
        GITHUB_RUN_ATTEMPT='1'
    [ "$status" -eq 1 ]
    [[ $output == *"target_key is required"* ]]
}

@test "run.sh rejects invalid state push branch" {
    state_write_run \
        GH_TOKEN='test-token' \
        STATE_FILE='.loop/state.json' \
        BASE_BRANCH='main' \
        STATE_PUSH_BRANCH='bad branch' \
        TARGET_KEY='integration:main' \
        WRITE_TARGET_STATE='false' \
        ACTING_ON_ACTION='' \
        GITHUB_REPOSITORY='test/repo' \
        GITHUB_RUN_ID='1' \
        GITHUB_RUN_ATTEMPT='1'
    [ "$status" -eq 1 ]
    [[ $output == *"Invalid state read branch"* ]]
}

@test "run.sh writes target state and resets consecutive_failures on pr-created" {
    state_write_run \
        GH_TOKEN='test-token' \
        STATE_FILE='.loop/state.json' \
        BASE_BRANCH='main' \
        TARGET_KEY='integration:main' \
        WRITE_TARGET_STATE='true' \
        OUTCOME='pr-created' \
        SHA='abcdefghi' \
        OPEN_REJECTIONS='[]' \
        ACTING_ON_ACTION='' \
        GITHUB_REPOSITORY='test/repo' \
        GITHUB_RUN_ID='1' \
        GITHUB_RUN_ATTEMPT='1'
    [ "$status" -eq 0 ]
    [[ $output == *"State pushed to main"* ]]
    run jq -e \
        --arg sha 'abcdefghi' \
        '.targets["integration:main"].last_sha == $sha
         and .targets["integration:main"].outcome == "pr-created"
         and .targets["integration:main"].consecutive_failures == 0
         and .targets["integration:main"].open_rejections == []' \
        "${STATE_WRITE_WORK}/.loop/state.json"
    [ "$status" -eq 0 ]
}

@test "run.sh increments consecutive_failures on rejected outcome" {
    printf '%s\n' '{"targets":{"integration:main":{"consecutive_failures":2}}}' \
        > "${STATE_WRITE_WORK}/.loop/state.json"
    state_write_seed

    state_write_run \
        GH_TOKEN='test-token' \
        STATE_FILE='.loop/state.json' \
        BASE_BRANCH='main' \
        TARGET_KEY='integration:main' \
        WRITE_TARGET_STATE='true' \
        OUTCOME='rejected' \
        SHA='def456' \
        OPEN_REJECTIONS='[{"id":"r1"}]' \
        REJECT_REASON='verifier rejected' \
        ACTING_ON_ACTION='' \
        GITHUB_REPOSITORY='test/repo' \
        GITHUB_RUN_ID='2' \
        GITHUB_RUN_ATTEMPT='1'
    [ "$status" -eq 0 ]
    run jq -e \
        '.targets["integration:main"].consecutive_failures == 3
         and .targets["integration:main"].last_reject_reason == "verifier rejected"
         and (.targets["integration:main"].open_rejections | length) == 1' \
        "${STATE_WRITE_WORK}/.loop/state.json"
    [ "$status" -eq 0 ]
}

@test "run.sh applies acting_on set and clear without target write" {
    state_write_run \
        GH_TOKEN='test-token' \
        STATE_FILE='.loop/state.json' \
        BASE_BRANCH='main' \
        TARGET_KEY='integration:main' \
        WRITE_TARGET_STATE='false' \
        ACTING_ON_ACTION='set' \
        ACTING_ON_TARGET_KEY='integration:main' \
        ACTING_ON_LOOP_NAME='docs-triage' \
        GITHUB_REPOSITORY='test/repo' \
        GITHUB_RUN_ID='3' \
        GITHUB_RUN_ATTEMPT='1'
    [ "$status" -eq 0 ]
    run jq -e \
        '.acting_on.target_key == "integration:main"
         and .acting_on.loop_name == "docs-triage"
         and (.acting_on.started_at | type) == "string"' \
        "${STATE_WRITE_WORK}/.loop/state.json"
    [ "$status" -eq 0 ]

    state_write_run \
        GH_TOKEN='test-token' \
        STATE_FILE='.loop/state.json' \
        BASE_BRANCH='main' \
        TARGET_KEY='integration:main' \
        WRITE_TARGET_STATE='false' \
        ACTING_ON_ACTION='clear' \
        GITHUB_REPOSITORY='test/repo' \
        GITHUB_RUN_ID='4' \
        GITHUB_RUN_ATTEMPT='1'
    [ "$status" -eq 0 ]
    run jq -e 'has("acting_on") | not' "${STATE_WRITE_WORK}/.loop/state.json"
    [ "$status" -eq 0 ]
}

@test "run.sh exits cleanly when state file has no changes" {
    state_write_run \
        GH_TOKEN='test-token' \
        STATE_FILE='.loop/state.json' \
        BASE_BRANCH='main' \
        TARGET_KEY='integration:main' \
        WRITE_TARGET_STATE='false' \
        ACTING_ON_ACTION='' \
        GITHUB_REPOSITORY='test/repo' \
        GITHUB_RUN_ID='6' \
        GITHUB_RUN_ATTEMPT='1'
    [ "$status" -eq 0 ]
    [[ $output == *"No state changes to commit."* ]]
}

@test "run.sh metadata mode updates outcome without advancing last_sha" {
    printf '%s\n' '{"targets":{"integration:main":{"last_sha":"oldsha000000","consecutive_failures":0}}}' \
        > "${STATE_WRITE_WORK}/.loop/state.json"
    state_write_seed

    state_write_run \
        GH_TOKEN='test-token' \
        STATE_FILE='.loop/state.json' \
        BASE_BRANCH='main' \
        TARGET_KEY='integration:main' \
        WRITE_TARGET_STATE='true' \
        STATE_WRITE_MODE='metadata' \
        OUTCOME='rejected' \
        SHA='ignored000000' \
        OPEN_REJECTIONS='[]' \
        ACTING_ON_ACTION='' \
        GITHUB_REPOSITORY='test/repo' \
        GITHUB_RUN_ID='7' \
        GITHUB_RUN_ATTEMPT='1'
    [ "$status" -eq 0 ]
    run jq -e \
        '.targets["integration:main"].last_sha == "oldsha000000"
         and .targets["integration:main"].outcome == "rejected"
         and .targets["integration:main"].consecutive_failures == 1' \
        "${STATE_WRITE_WORK}/.loop/state.json"
    [ "$status" -eq 0 ]
}

@test "run.sh pending mode records pending without advancing last_sha" {
    printf '%s\n' '{"targets":{"integration:main":{"last_sha":"oldsha000000"}}}' \
        > "${STATE_WRITE_WORK}/.loop/state.json"
    state_write_seed

    state_write_run \
        GH_TOKEN='test-token' \
        STATE_FILE='.loop/state.json' \
        BASE_BRANCH='main' \
        TARGET_KEY='integration:main' \
        WRITE_TARGET_STATE='true' \
        STATE_WRITE_MODE='pending' \
        OUTCOME='pr-created' \
        SHA='abcdefghi' \
        PENDING_PR_NUMBER='42' \
        PENDING_PR_URL='https://github.com/owner/repo/pull/42' \
        LOOP_NAME='changelog' \
        OPEN_REJECTIONS='[]' \
        ACTING_ON_ACTION='' \
        GITHUB_REPOSITORY='test/repo' \
        GITHUB_RUN_ID='8' \
        GITHUB_RUN_ATTEMPT='1'
    [ "$status" -eq 0 ]
    run jq -e \
        '.targets["integration:main"].last_sha == "oldsha000000"
         and .targets["integration:main"].pending.pr == 42
         and .targets["integration:main"].pending.sha == "abcdefghi"' \
        "${STATE_WRITE_WORK}/.loop/state.json"
    [ "$status" -eq 0 ]
}

@test "run.sh promote mode advances last_sha from pending" {
    printf '%s\n' '{"targets":{"integration:main":{"last_sha":"oldsha000000","pending":{"sha":"newsha111111","pr":99}}}}' \
        > "${STATE_WRITE_WORK}/.loop/state.json"
    state_write_seed

    state_write_run \
        GH_TOKEN='test-token' \
        STATE_FILE='.loop/state.json' \
        BASE_BRANCH='main' \
        TARGET_KEY='integration:main' \
        WRITE_TARGET_STATE='true' \
        STATE_WRITE_MODE='promote' \
        OUTCOME='merged' \
        PENDING_PR_NUMBER='99' \
        OPEN_REJECTIONS='[]' \
        ACTING_ON_ACTION='' \
        GITHUB_REPOSITORY='test/repo' \
        GITHUB_RUN_ID='9' \
        GITHUB_RUN_ATTEMPT='1'
    [ "$status" -eq 0 ]
    run jq -e \
        '.targets["integration:main"].last_sha == "newsha111111"
         and (.targets["integration:main"] | has("pending") | not)
         and .targets["integration:main"].outcome == "merged"' \
        "${STATE_WRITE_WORK}/.loop/state.json"
    [ "$status" -eq 0 ]
}

@test "run.sh clear_pending mode clears pending without advancing last_sha" {
    printf '%s\n' '{"targets":{"integration:main":{"last_sha":"oldsha000000","pending":{"sha":"newsha111111","pr":99}}}}' \
        > "${STATE_WRITE_WORK}/.loop/state.json"
    state_write_seed

    state_write_run \
        GH_TOKEN='test-token' \
        STATE_FILE='.loop/state.json' \
        BASE_BRANCH='main' \
        TARGET_KEY='integration:main' \
        WRITE_TARGET_STATE='true' \
        STATE_WRITE_MODE='clear_pending' \
        OUTCOME='pr-closed' \
        PENDING_PR_NUMBER='99' \
        OPEN_REJECTIONS='[]' \
        ACTING_ON_ACTION='' \
        GITHUB_REPOSITORY='test/repo' \
        GITHUB_RUN_ID='10' \
        GITHUB_RUN_ATTEMPT='1'
    [ "$status" -eq 0 ]
    run jq -e \
        '.targets["integration:main"].last_sha == "oldsha000000"
         and (.targets["integration:main"] | has("pending") | not)
         and .targets["integration:main"].outcome == "pr-closed"' \
        "${STATE_WRITE_WORK}/.loop/state.json"
    [ "$status" -eq 0 ]
}

@test "run.sh clear_pending mode no-ops when pending pr does not match" {
    printf '%s\n' '{"targets":{"integration:main":{"last_sha":"oldsha000000","pending":{"sha":"newsha111111","pr":42}}}}' \
        > "${STATE_WRITE_WORK}/.loop/state.json"
    state_write_seed

    state_write_run \
        GH_TOKEN='test-token' \
        STATE_FILE='.loop/state.json' \
        BASE_BRANCH='main' \
        TARGET_KEY='integration:main' \
        WRITE_TARGET_STATE='true' \
        STATE_WRITE_MODE='clear_pending' \
        OUTCOME='pr-closed' \
        PENDING_PR_NUMBER='99' \
        OPEN_REJECTIONS='[]' \
        ACTING_ON_ACTION='' \
        GITHUB_REPOSITORY='test/repo' \
        GITHUB_RUN_ID='11' \
        GITHUB_RUN_ATTEMPT='1'
    [ "$status" -eq 0 ]
    [[ ${output} == *"No matching pending entry"* ]]
    run jq -e \
        '.targets["integration:main"].pending.pr == 42
         and .targets["integration:main"].last_sha == "oldsha000000"' \
        "${STATE_WRITE_WORK}/.loop/state.json"
    [ "$status" -eq 0 ]
}
