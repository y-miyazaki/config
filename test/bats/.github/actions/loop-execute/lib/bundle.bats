#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-execute/lib/bundle.sh

# Use cases:
# - main rejects invalid branch names
# - main writes has_changes=false when loop produced no commits
# - main skips the bundle and warns when LOOP_DENYLIST_BLOCKED is true
# - main bundles only commits not on origin/base
# - main records a bundle failure
# - main does not read GITHUB_TOKEN

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/loop-execute/lib/bundle.sh"
    GITHUB_OUTPUT=$(mktemp)
    BUNDLE_FILE="${BATS_TEST_TMPDIR}/out/branch.bundle"
    BASE_BRANCH='main'
}

teardown() {
    rm -f "${GITHUB_OUTPUT:-}"
}

# make_repo: bare origin with main, plus a work clone on loop/x/20261018-000000
# holding one commit that is not on origin/main.
function make_repo {
    local origin="${BATS_TEST_TMPDIR}/origin.git"
    WORKTREE_PATH="${BATS_TEST_TMPDIR}/work"
    git init -q --bare -b main "${origin}"
    git clone -q "${origin}" "${WORKTREE_PATH}" 2> /dev/null
    git -C "${WORKTREE_PATH}" config user.email t@example.com
    git -C "${WORKTREE_PATH}" config user.name t
    git -C "${WORKTREE_PATH}" checkout -q -b main
    echo base > "${WORKTREE_PATH}/a.txt"
    git -C "${WORKTREE_PATH}" add a.txt
    git -C "${WORKTREE_PATH}" commit -q -m base
    git -C "${WORKTREE_PATH}" push -q origin main
    git -C "${WORKTREE_PATH}" fetch -q origin
    git -C "${WORKTREE_PATH}" checkout -q -b loop/x/20261018-000000
    echo change > "${WORKTREE_PATH}/b.txt"
    git -C "${WORKTREE_PATH}" add b.txt
    git -C "${WORKTREE_PATH}" commit -q -m change
    BRANCH='loop/x/20261018-000000'
}

@test "main rejects invalid branch names" {
    BRANCH='loop/bad branch'
    LOOP_HAS_CHANGES='true'
    WORKTREE_PATH='/tmp/worktree'
    run main
    [ "$status" -eq 1 ]
    [[ $output == *"Invalid branch name"* ]]
}

@test "main writes has_changes=false when loop produced no commits" {
    BRANCH='loop/docs-updater-abc'
    LOOP_HAS_CHANGES='false'
    WORKTREE_PATH='/tmp/worktree'
    run main
    [ "$status" -eq 0 ]
    grep -q '^has_changes=false$' "${GITHUB_OUTPUT}"
}

@test "main skips the bundle and warns when LOOP_DENYLIST_BLOCKED is true" {
    BRANCH='loop/docs-updater-abc'
    LOOP_HAS_CHANGES='true'
    LOOP_DENYLIST_BLOCKED='true'
    WORKTREE_PATH='/tmp/worktree'
    run main
    [ "$status" -eq 0 ]
    [[ $output == *"Skipping bundle: final diff still matches the denylist"* ]]
    grep -q '^has_changes=false$' "${GITHUB_OUTPUT}"
    [ ! -e "${BUNDLE_FILE}" ]
}

@test "main bundles only commits not on origin/base" {
    local base_sha clone
    make_repo
    LOOP_HAS_CHANGES='true'
    run main
    [ "$status" -eq 0 ]
    grep -q '^has_changes=true$' "${GITHUB_OUTPUT}"
    [ -f "${BUNDLE_FILE}" ]

    run git bundle list-heads "${BUNDLE_FILE}"
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "${output}" | wc -l)" -eq 1 ]
    [[ $output == *" refs/heads/loop/x/20261018-000000" ]]

    base_sha="$(git -C "${WORKTREE_PATH}" rev-parse origin/main)"
    run git -C "${WORKTREE_PATH}" bundle verify "${BUNDLE_FILE}"
    [ "$status" -eq 0 ]
    [[ $output == *"${base_sha}"* ]]

    # An empty repository lacks the prerequisite and cannot fetch the bundle
    git init -q "${BATS_TEST_TMPDIR}/empty"
    run git -C "${BATS_TEST_TMPDIR}/empty" fetch "${BUNDLE_FILE}" 'refs/heads/loop/x/20261018-000000'
    [ "$status" -ne 0 ]

    # A clone that has main can
    clone="${BATS_TEST_TMPDIR}/clone"
    git clone -q "${BATS_TEST_TMPDIR}/origin.git" "${clone}" 2> /dev/null
    run git -C "${clone}" fetch "${BUNDLE_FILE}" 'refs/heads/loop/x/20261018-000000'
    [ "$status" -eq 0 ]
}

@test "main records a bundle failure" {
    local status_dir="${BATS_TEST_TMPDIR}/status"
    make_repo
    mkdir -p "${status_dir}"
    STATUS_DIR="${status_dir}"
    export STATUS_DIR
    BASE_BRANCH='missing-base'
    LOOP_HAS_CHANGES='true'
    run main
    [ "$status" -eq 1 ]
    [ -f "${status_dir}/failure.json" ]
    [ "$(jq -r '.failure_stage' "${status_dir}/failure.json")" = "bundle" ]
}

@test "main does not read GITHUB_TOKEN" {
    run grep -c GITHUB_TOKEN "$(bats_workspace_root)/.github/actions/loop-execute/lib/bundle.sh"
    [ "${output}" = "0" ]
}
