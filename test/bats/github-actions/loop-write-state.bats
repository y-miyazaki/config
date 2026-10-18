#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-finalize/lib/write_state.sh

# Use cases:
# - validation: missing target_key / missing or invalid state_branch
# - advance mode: last_sha + outcome; reset consecutive_failures on pr_created
# - rejected, pr_closed, and persisted old pr-closed outcomes increment consecutive_failures
# - finalize_commit_paths are committed with the state file
# - no-op when unchanged
# - metadata mode: outcome without advancing last_sha
# - pending mode: record pending without advancing last_sha (delivery pr_create path)
# - promote mode: pending.sha → last_sha; clear pending
# - clear_pending mode: clear pending only; last_sha unchanged
# - apply_state_patch updates state via write_state_advance helper
# - write_state_pending records pending without advancing last_sha
# - write_state_promote promotes pending sha to last_sha
# - write_state_clear_pending clears pending without advancing last_sha
# - refuses PR fallback for advance + pr_pushed when push is blocked
# - opens the state PR fallback for advance + pr_created (the refusal keys on pr_pushed only)
# - state_pr_skip warns when direct push is blocked

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

RUN_SCRIPT="$(bats_workspace_root)/.github/actions/loop-finalize/lib/write_state.sh"

state_write_git_setup() {
    STATE_WRITE_BARE="${BATS_TEST_TMPDIR}/origin.git"
    STATE_WRITE_WORK="${BATS_TEST_TMPDIR}/work"
    rm -rf "${STATE_WRITE_BARE}" "${STATE_WRITE_WORK}"
    mkdir -p "${STATE_WRITE_WORK}/.loop"
    bats_git_init_in_place "${STATE_WRITE_WORK}"
    git -C "${STATE_WRITE_WORK}" checkout -q -b main
    printf '%s\n' '{"targets":{}}' > "${STATE_WRITE_WORK}/.loop/state-test.json"
    bats_git_commit "${STATE_WRITE_WORK}" "chore: init state" .loop/state-test.json
    git init -q --bare "${STATE_WRITE_BARE}"
    git -C "${STATE_WRITE_WORK}" remote add origin "${STATE_WRITE_BARE}"
    git -C "${STATE_WRITE_WORK}" push -q -u origin main
}

state_write_run() {
    run bash -c "cd '${STATE_WRITE_WORK}' && $(printf '%q ' "${@}") bash '${RUN_SCRIPT}'"
}

state_write_seed() {
    git -C "${STATE_WRITE_WORK}" add .loop/state-test.json
    git -C "${STATE_WRITE_WORK}" commit -q -m "test: seed state"
    git -C "${STATE_WRITE_WORK}" push -q origin main
}

state_write_block_push() {
    cat > "${STATE_WRITE_BARE}/hooks/pre-receive" << 'EOF'
#!/bin/sh
while read -r _ _ refname; do
    case "${refname}" in
        refs/heads/main) exit 1 ;;
    esac
done
exit 0
EOF
    chmod +x "${STATE_WRITE_BARE}/hooks/pre-receive"
}

state_write_mock_gh() {
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

state_write_source_helpers() {
    # shellcheck disable=SC1090,SC1091
    source "${RUN_SCRIPT}"
}

setup() {
    state_write_git_setup
}

@test "apply_state_patch advances last_sha and clears pending via write_state_advance" {
    TARGET_KEY='integration:main'
    SHA='newsha111111'
    OUTCOME='pr_merged'
    REJECT_REASON=''
    OPEN_REJECTIONS='[]'

    state_write_source_helpers
    STATE_TMP="$(mktemp)"
    printf '%s\n' '{"targets":{"integration:main":{"last_sha":"oldsha000000","pending":{"pr":1,"sha":"pendingsha"}}}}' \
        > "${STATE_TMP}"

    write_state_advance "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" 0

    run jq -e \
        '.targets["integration:main"].last_sha == "newsha111111"
         and (.targets["integration:main"] | has("pending") | not)
         and .targets["integration:main"].outcome == "pr_merged"' \
        "${STATE_TMP}"
    [ "$status" -eq 0 ]
    rm -f "${STATE_TMP}"
}
@test "run.sh clear_pending mode clears pending without advancing last_sha" {
    printf '%s\n' '{"targets":{"integration:main":{"last_sha":"oldsha000000","pending":{"sha":"newsha111111","pr":99}}}}' \
        > "${STATE_WRITE_WORK}/.loop/state-test.json"
    state_write_seed

    state_write_run \
        GITHUB_TOKEN='test-token' \
        STATE_FILE='.loop/state-test.json' \
        STATE_BRANCH='main' \
        TARGET_KEY='integration:main' \
        WRITE_TARGET_STATE='true' \
        STATE_WRITE_MODE='clear_pending' \
        OUTCOME='pr_closed' \
        PENDING_PR_NUMBER='99' \
        OPEN_REJECTIONS='[]' \
        GITHUB_REPOSITORY='test/repo' \
        GITHUB_RUN_ID='10' \
        GITHUB_RUN_ATTEMPT='1'
    [ "$status" -eq 0 ]
    run jq -e \
        '.targets["integration:main"].last_sha == "oldsha000000"
         and (.targets["integration:main"] | has("pending") | not)
         and .targets["integration:main"].outcome == "pr_closed"' \
        "${STATE_WRITE_WORK}/.loop/state-test.json"
    [ "$status" -eq 0 ]
}
@test "run.sh clear_pending mode no-ops when pending pr does not match" {
    printf '%s\n' '{"targets":{"integration:main":{"last_sha":"oldsha000000","pending":{"sha":"newsha111111","pr":42}}}}' \
        > "${STATE_WRITE_WORK}/.loop/state-test.json"
    state_write_seed

    state_write_run \
        GITHUB_TOKEN='test-token' \
        STATE_FILE='.loop/state-test.json' \
        STATE_BRANCH='main' \
        TARGET_KEY='integration:main' \
        WRITE_TARGET_STATE='true' \
        STATE_WRITE_MODE='clear_pending' \
        OUTCOME='pr_closed' \
        PENDING_PR_NUMBER='99' \
        OPEN_REJECTIONS='[]' \
        GITHUB_REPOSITORY='test/repo' \
        GITHUB_RUN_ID='11' \
        GITHUB_RUN_ATTEMPT='1'
    [ "$status" -eq 0 ]
    [[ ${output} == *"No matching pending entry"* ]]
    run jq -e \
        '.targets["integration:main"].pending.pr == 42
         and .targets["integration:main"].last_sha == "oldsha000000"' \
        "${STATE_WRITE_WORK}/.loop/state-test.json"
    [ "$status" -eq 0 ]
}
@test "run.sh exits cleanly when state file has no changes" {
    state_write_run \
        GITHUB_TOKEN='test-token' \
        STATE_FILE='.loop/state-test.json' \
        STATE_BRANCH='main' \
        TARGET_KEY='integration:main' \
        WRITE_TARGET_STATE='false' \
        GITHUB_REPOSITORY='test/repo' \
        GITHUB_RUN_ID='6' \
        GITHUB_RUN_ATTEMPT='1'
    [ "$status" -eq 0 ]
    [[ $output == *"No state changes to commit."* ]]
}
@test "run.sh increments consecutive_failures on rejected outcome" {
    printf '%s\n' '{"targets":{"integration:main":{"consecutive_failures":2}}}' \
        > "${STATE_WRITE_WORK}/.loop/state-test.json"
    state_write_seed

    state_write_run \
        GITHUB_TOKEN='test-token' \
        STATE_FILE='.loop/state-test.json' \
        STATE_BRANCH='main' \
        TARGET_KEY='integration:main' \
        WRITE_TARGET_STATE='true' \
        OUTCOME='rejected' \
        SHA='def456' \
        OPEN_REJECTIONS='[{"id":"r1"}]' \
        REJECT_REASON='checker rejected' \
        GITHUB_REPOSITORY='test/repo' \
        GITHUB_RUN_ID='2' \
        GITHUB_RUN_ATTEMPT='1'
    [ "$status" -eq 0 ]
    run jq -e \
        '.targets["integration:main"].consecutive_failures == 3
         and .targets["integration:main"].last_reject_reason == "checker rejected"
         and (.targets["integration:main"].open_rejections | length) == 1' \
        "${STATE_WRITE_WORK}/.loop/state-test.json"
    [ "$status" -eq 0 ]
}
@test "run.sh increments consecutive_failures on pr_closed and old pr-closed outcomes" {
    local outcome checked=0
    for outcome in pr_closed pr-closed; do
        printf '%s\n' '{"targets":{"integration:main":{"consecutive_failures":2}}}' \
            > "${STATE_WRITE_WORK}/.loop/state-test.json"
        state_write_seed

        state_write_run \
            GITHUB_TOKEN='test-token' \
            STATE_FILE='.loop/state-test.json' \
            STATE_BRANCH='main' \
            TARGET_KEY='integration:main' \
            WRITE_TARGET_STATE='true' \
            STATE_WRITE_MODE='metadata' \
            OUTCOME="${outcome}" \
            SHA='def456' \
            OPEN_REJECTIONS='[]' \
            GITHUB_REPOSITORY='test/repo' \
            GITHUB_RUN_ID='15' \
            GITHUB_RUN_ATTEMPT='1'
        [ "$status" -eq 0 ]
        run jq -r '.targets["integration:main"].consecutive_failures' "${STATE_WRITE_WORK}/.loop/state-test.json"
        [ "$output" = "3" ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 2 ]
}
@test "run.sh commits finalize_commit_paths with the state file" {
    printf '%s\n' '{"entries":[1]}' > "${STATE_WRITE_WORK}/.loop/state-test-ledger.json"

    state_write_run \
        GITHUB_TOKEN='test-token' \
        STATE_FILE='.loop/state-test.json' \
        STATE_BRANCH='main' \
        TARGET_KEY='integration:main' \
        WRITE_TARGET_STATE='true' \
        STATE_WRITE_MODE='metadata' \
        OUTCOME='reported' \
        SHA='def456' \
        OPEN_REJECTIONS='[]' \
        FINALIZE_COMMIT_PATHS='.loop/state-test-ledger.json' \
        GITHUB_REPOSITORY='test/repo' \
        GITHUB_RUN_ID='16' \
        GITHUB_RUN_ATTEMPT='1'
    [ "$status" -eq 0 ]
    run git --git-dir="${STATE_WRITE_BARE}" show main:.loop/state-test-ledger.json
    [ "$status" -eq 0 ]
    [ "$output" = '{"entries":[1]}' ]
}
@test "run.sh metadata mode updates outcome without advancing last_sha" {
    printf '%s\n' '{"targets":{"integration:main":{"last_sha":"oldsha000000","consecutive_failures":0}}}' \
        > "${STATE_WRITE_WORK}/.loop/state-test.json"
    state_write_seed

    state_write_run \
        GITHUB_TOKEN='test-token' \
        STATE_FILE='.loop/state-test.json' \
        STATE_BRANCH='main' \
        TARGET_KEY='integration:main' \
        WRITE_TARGET_STATE='true' \
        STATE_WRITE_MODE='metadata' \
        OUTCOME='rejected' \
        SHA='ignored000000' \
        OPEN_REJECTIONS='[]' \
        GITHUB_REPOSITORY='test/repo' \
        GITHUB_RUN_ID='7' \
        GITHUB_RUN_ATTEMPT='1'
    [ "$status" -eq 0 ]
    run jq -e \
        '.targets["integration:main"].last_sha == "oldsha000000"
         and .targets["integration:main"].outcome == "rejected"
         and .targets["integration:main"].consecutive_failures == 1' \
        "${STATE_WRITE_WORK}/.loop/state-test.json"
    [ "$status" -eq 0 ]
}
@test "run.sh pending mode records pending without advancing last_sha" {
    printf '%s\n' '{"targets":{"integration:main":{"last_sha":"oldsha000000"}}}' \
        > "${STATE_WRITE_WORK}/.loop/state-test.json"
    state_write_seed

    state_write_run \
        GITHUB_TOKEN='test-token' \
        STATE_FILE='.loop/state-test.json' \
        STATE_BRANCH='main' \
        TARGET_KEY='integration:main' \
        WRITE_TARGET_STATE='true' \
        STATE_WRITE_MODE='pending' \
        OUTCOME='pr_created' \
        SHA='abcdefghi' \
        PENDING_PR_NUMBER='42' \
        PENDING_PR_URL='https://github.com/owner/repo/pull/42' \
        LOOP_NAME='changelog' \
        OPEN_REJECTIONS='[]' \
        GITHUB_REPOSITORY='test/repo' \
        GITHUB_RUN_ID='8' \
        GITHUB_RUN_ATTEMPT='1'
    [ "$status" -eq 0 ]
    run jq -e \
        '.targets["integration:main"].last_sha == "oldsha000000"
         and .targets["integration:main"].pending.pr == 42
         and .targets["integration:main"].pending.sha == "abcdefghi"' \
        "${STATE_WRITE_WORK}/.loop/state-test.json"
    [ "$status" -eq 0 ]
}
@test "run.sh promote mode advances last_sha from pending" {
    printf '%s\n' '{"targets":{"integration:main":{"last_sha":"oldsha000000","pending":{"sha":"newsha111111","pr":99}}}}' \
        > "${STATE_WRITE_WORK}/.loop/state-test.json"
    state_write_seed

    state_write_run \
        GITHUB_TOKEN='test-token' \
        STATE_FILE='.loop/state-test.json' \
        STATE_BRANCH='main' \
        TARGET_KEY='integration:main' \
        WRITE_TARGET_STATE='true' \
        STATE_WRITE_MODE='promote' \
        OUTCOME='pr_merged' \
        PENDING_PR_NUMBER='99' \
        OPEN_REJECTIONS='[]' \
        GITHUB_REPOSITORY='test/repo' \
        GITHUB_RUN_ID='9' \
        GITHUB_RUN_ATTEMPT='1'
    [ "$status" -eq 0 ]
    run jq -e \
        '.targets["integration:main"].last_sha == "newsha111111"
         and (.targets["integration:main"] | has("pending") | not)
         and .targets["integration:main"].outcome == "pr_merged"' \
        "${STATE_WRITE_WORK}/.loop/state-test.json"
    [ "$status" -eq 0 ]
}
@test "run.sh opens state PR fallback for advance pr_created when direct push is blocked" {
    state_write_block_push
    state_write_mock_gh

    state_write_run \
        PATH="${PATH}" \
        GITHUB_TOKEN='test-token' \
        STATE_FILE='.loop/state-test.json' \
        STATE_BRANCH='main' \
        TARGET_KEY='integration:main' \
        WRITE_TARGET_STATE='true' \
        STATE_WRITE_MODE='advance' \
        OUTCOME='pr_created' \
        SHA='abcdefghi' \
        OPEN_REJECTIONS='[]' \
        GITHUB_REPOSITORY='test/repo' \
        GITHUB_RUN_ID='14' \
        GITHUB_RUN_ATTEMPT='1'
    [ "$status" -eq 0 ]
    [[ $output != *"state PR fallback refused"* ]]
    [[ $output == *"State PR queued for auto-merge: https://github.com/test/repo/pull/99"* ]]
}
@test "run.sh refuses advance pr_pushed when direct push is blocked" {
    state_write_block_push
    state_write_mock_gh

    state_write_run \
        PATH="${PATH}" \
        GITHUB_TOKEN='test-token' \
        STATE_FILE='.loop/state-test.json' \
        STATE_BRANCH='main' \
        TARGET_KEY='integration:main' \
        WRITE_TARGET_STATE='true' \
        STATE_WRITE_MODE='advance' \
        OUTCOME='pr_pushed' \
        SHA='abcdefghi' \
        OPEN_REJECTIONS='[]' \
        GITHUB_REPOSITORY='test/repo' \
        GITHUB_RUN_ID='12' \
        GITHUB_RUN_ATTEMPT='1'
    [ "$status" -eq 1 ]
    [[ $output == *"::error::Direct push to main blocked and state PR fallback refused: advance mode with pr_pushed outcome."* ]]
    [[ $output != *"State PR queued"* ]]
}
@test "run.sh rejects invalid state push branch" {
    state_write_run \
        GITHUB_TOKEN='test-token' \
        STATE_FILE='.loop/state-test.json' \
        STATE_BRANCH='bad branch' \
        TARGET_KEY='integration:main' \
        WRITE_TARGET_STATE='false' \
        GITHUB_REPOSITORY='test/repo' \
        GITHUB_RUN_ID='1' \
        GITHUB_RUN_ATTEMPT='1'
    [ "$status" -eq 1 ]
    [[ $output == *"Invalid state read branch"* ]]
}
@test "run.sh rejects missing target_key" {
    state_write_run \
        GITHUB_TOKEN='test-token' \
        STATE_FILE='.loop/state-test.json' \
        STATE_BRANCH='main' \
        TARGET_KEY='' \
        WRITE_TARGET_STATE='false' \
        GITHUB_REPOSITORY='test/repo' \
        GITHUB_RUN_ID='1' \
        GITHUB_RUN_ATTEMPT='1'
    [ "$status" -eq 1 ]
    [[ $output == *"target_key is required"* ]]
}
@test "run.sh rejects missing state_branch" {
    state_write_run \
        GITHUB_TOKEN='test-token' \
        STATE_FILE='.loop/state-test.json' \
        TARGET_KEY='integration:main' \
        WRITE_TARGET_STATE='false' \
        GITHUB_REPOSITORY='test/repo' \
        GITHUB_RUN_ID='1' \
        GITHUB_RUN_ATTEMPT='1'
    [ "$status" -eq 1 ]
    [[ $output == *"::error::state_branch is required"* ]]
}
@test "run.sh skips state PR fallback when state_pr_skip is true" {
    state_write_block_push

    state_write_run \
        GITHUB_TOKEN='test-token' \
        STATE_FILE='.loop/state-test.json' \
        STATE_BRANCH='main' \
        TARGET_KEY='integration:main' \
        WRITE_TARGET_STATE='true' \
        OUTCOME='pr_merged' \
        SHA='abcdefghi' \
        OPEN_REJECTIONS='[]' \
        STATE_PR_SKIP='true' \
        GITHUB_REPOSITORY='test/repo' \
        GITHUB_RUN_ID='13' \
        GITHUB_RUN_ATTEMPT='1'
    [ "$status" -eq 0 ]
    [[ $output == *"::warning::Direct push blocked; skipping state PR (state_pr_skip=true)."* ]]
}
@test "run.sh writes target state and resets consecutive_failures on pr_created" {
    state_write_run \
        GITHUB_TOKEN='test-token' \
        STATE_FILE='.loop/state-test.json' \
        STATE_BRANCH='main' \
        TARGET_KEY='integration:main' \
        WRITE_TARGET_STATE='true' \
        OUTCOME='pr_created' \
        SHA='abcdefghi' \
        OPEN_REJECTIONS='[]' \
        GITHUB_REPOSITORY='test/repo' \
        GITHUB_RUN_ID='1' \
        GITHUB_RUN_ATTEMPT='1'
    [ "$status" -eq 0 ]
    [[ $output == *"State pushed to main"* ]]
    run jq -e \
        --arg sha 'abcdefghi' \
        '.targets["integration:main"].last_sha == $sha
         and .targets["integration:main"].outcome == "pr_created"
         and .targets["integration:main"].consecutive_failures == 0
         and .targets["integration:main"].open_rejections == []' \
        "${STATE_WRITE_WORK}/.loop/state-test.json"
    [ "$status" -eq 0 ]
}
@test "write_state_clear_pending clears pending without advancing last_sha" {
    TARGET_KEY='integration:main'
    OUTCOME='pr_closed'
    REJECT_REASON=''
    OPEN_REJECTIONS='[]'
    PENDING_PR_NUMBER='42'

    state_write_source_helpers
    STATE_TMP="$(mktemp)"
    printf '%s\n' '{"targets":{"integration:main":{"last_sha":"oldsha000000","pending":{"pr":42,"sha":"pendingsha111"}}}}' \
        > "${STATE_TMP}"

    write_state_clear_pending "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" 0

    run jq -e \
        '.targets["integration:main"].last_sha == "oldsha000000"
         and (.targets["integration:main"] | has("pending") | not)' \
        "${STATE_TMP}"
    [ "$status" -eq 0 ]
    rm -f "${STATE_TMP}"
}
@test "write_state_pending records pending without advancing last_sha" {
    TARGET_KEY='integration:main'
    SHA='pendingsha111'
    OUTCOME='pr_created'
    REJECT_REASON=''
    OPEN_REJECTIONS='[]'
    PENDING_PR_NUMBER='42'
    PENDING_PR_URL='https://github.com/test/repo/pull/42'
    LOOP_NAME='loop-ci-sweeper'

    state_write_source_helpers
    STATE_TMP="$(mktemp)"
    printf '%s\n' '{"targets":{"integration:main":{"last_sha":"oldsha000000"}}}' > "${STATE_TMP}"

    write_state_pending "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" 0

    run jq -e \
        '.targets["integration:main"].last_sha == "oldsha000000"
         and .targets["integration:main"].pending.sha == "pendingsha111"
         and .targets["integration:main"].pending.pr == 42' \
        "${STATE_TMP}"
    [ "$status" -eq 0 ]
    rm -f "${STATE_TMP}"
}
@test "write_state_promote promotes pending sha to last_sha" {
    TARGET_KEY='integration:main'
    OUTCOME='pr_merged'
    REJECT_REASON=''
    OPEN_REJECTIONS='[]'
    PENDING_PR_NUMBER='42'

    state_write_source_helpers
    STATE_TMP="$(mktemp)"
    printf '%s\n' '{"targets":{"integration:main":{"last_sha":"oldsha000000","pending":{"pr":42,"sha":"promotedsha111"}}}}' \
        > "${STATE_TMP}"

    write_state_promote "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" 0

    run jq -e \
        '.targets["integration:main"].last_sha == "promotedsha111"
         and (.targets["integration:main"] | has("pending") | not)' \
        "${STATE_TMP}"
    [ "$status" -eq 0 ]
    rm -f "${STATE_TMP}"
}

@test "validate_finalize_commit_path rejects path traversal" {
    # shellcheck disable=SC1090
    source "${RUN_SCRIPT}"
    run validate_finalize_commit_path "../outside.json"
    [ "$status" -eq 1 ]
    [ "$output" = "::error::finalize_commit_paths must not contain '..': ../outside.json" ]
}

@test "validate_state_file_path rejects non-loop path" {
    # shellcheck disable=SC1090
    source "${RUN_SCRIPT}"
    run bash -c 'source "'"${RUN_SCRIPT}"'"; STATE_FILE=state.json validate_state_file_path'
    [ "$status" -eq 1 ]
    [[ $output == *"must match .loop/state-<name>.json"* ]]
}
