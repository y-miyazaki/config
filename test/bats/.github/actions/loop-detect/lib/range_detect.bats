#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-detect/lib/range_detect.sh
#
# Use cases:
# - range_detect skips when only .loop/ files, the state file and the run log changed
# - range_detect reports changed files and the since..head range in verifier_context
# - range_detect runs with a range-only verifier_context when a changed path is unsafe
# - range_detect fails (rc 1) when git cannot diff the range
# - range_detect caps the changed file list in verifier_context at 100 entries

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/lib/loop/edit_paths.sh"
    bats_source_rel ".github/actions/loop-detect/lib/range_detect.sh"
    REPO="${BATS_TEST_TMPDIR}/repo"
    mkdir -p "${REPO}/.loop" "${REPO}/src"
    git init -q "${REPO}"
    git -C "${REPO}" config user.email "test@example.com"
    git -C "${REPO}" config user.name "Test User"
    printf 'one\n' > "${REPO}/src/a.sh"
    printf '{}\n' > "${REPO}/.loop/state-x.json"
    printf 'log\n' > "${REPO}/.loop/run-log.md"
    git -C "${REPO}" add -A
    git -C "${REPO}" commit -q -m base
    SINCE="$(git -C "${REPO}" rev-parse HEAD)"
}

teardown() {
    rm -rf "${REPO}"
}

# commit_all MESSAGE: stage and commit everything in the test repository
commit_all() {
    git -C "${REPO}" add -A
    git -C "${REPO}" commit -q -m "$1"
}

# run_range_detect: run range_detect in the test repository from SINCE to HEAD
run_range_detect() {
    local head

    head="$(git -C "${REPO}" rev-parse HEAD)"
    run --separate-stderr bash -c \
        "cd '${REPO}' && source '$(bats_workspace_root)/.github/actions/lib/loop/edit_paths.sh' && source '$(bats_workspace_root)/.github/actions/loop-detect/lib/range_detect.sh' && range_detect '${1:-${SINCE}}' '${head}' '${REPO}/.loop/state-x.json' '${REPO}/.loop/run-log.md'"
}

@test "range_detect caps the changed file list in verifier_context at 100 entries" {
    local i
    for i in $(seq 1 120); do printf 'x\n' > "${REPO}/src/f${i}.sh"; done
    commit_all "many"
    run_range_detect
    [ "$status" -eq 0 ]
    [ "$(jq -r '.result.changed_count' <<< "$output")" -eq 120 ]
    [ "$(jq -r '.verifier_context' <<< "$output" | grep -c '^- src/')" -eq 100 ]
}

@test "range_detect fails on git error" {
    printf 'two\n' >> "${REPO}/src/a.sh"
    commit_all "change"
    run_range_detect "0000000000000000000000000000000000000000"
    [ "$status" -eq 1 ]
}

@test "range_detect reports changed files and range in verifier_context" {
    local head
    printf 'two\n' >> "${REPO}/src/a.sh"
    commit_all "change"
    head="$(git -C "${REPO}" rev-parse HEAD)"
    run_range_detect
    [ "$status" -eq 0 ]
    [ "$(jq -r '.skip' <<< "$output")" = "false" ]
    [ "$(jq -r '.result.changed_count' <<< "$output")" -eq 1 ]
    [ "$(jq -r '.result.since' <<< "$output")" = "${SINCE}" ]
    [ "$(jq -r '.result.head' <<< "$output")" = "${head}" ]
    jq -r '.verifier_context' <<< "$output" | grep -qF "${SINCE}..${head}"
    jq -r '.verifier_context' <<< "$output" | grep -qF "src/a.sh"
}

@test "range_detect runs with a range-only verifier_context when a path is unsafe" {
    printf 'x\n' > "${REPO}/src/$(printf 'a\nb.sh')"
    commit_all "unsafe"
    run_range_detect
    [ "$status" -eq 0 ]
    [ "$(jq -r '.skip' <<< "$output")" = "false" ]
    local context
    context="$(jq -r '.verifier_context' <<< "$output")"
    [[ ${context} == "Range: ${SINCE}.."* ]]
    [[ ${context} != *"Changed files"* ]]
    [ "$(jq -r '.result.changed_count' <<< "$output")" = "null" ]
}

@test "range_detect skips when only .loop/ and the run log changed" {
    printf '{"x":1}\n' > "${REPO}/.loop/state-x.json"
    printf 'more\n' >> "${REPO}/.loop/run-log.md"
    commit_all "platform writes"
    run_range_detect
    [ "$status" -eq 0 ]
    [ "$output" = '{"skip":true}' ]
}
