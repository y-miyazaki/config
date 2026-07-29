#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-execute/lib/push.sh

# Use cases:
# - main rejects invalid branch names
# - main writes has_changes=false when loop produced no commits
# - main accepts valid branch name characters
# - main records redacted push failure when git push fails

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/loop-execute/lib/push.sh"
    GITHUB_OUTPUT=$(mktemp)
}

teardown() {
    rm -f "${GITHUB_OUTPUT:-}"
}

@test "main rejects invalid branch names" {
    BRANCH='loop/bad branch'
    GH_TOKEN='test-token'
    LOOP_HAS_CHANGES='true'
    WORKTREE_PATH='/tmp/worktree'
    run main
    [ "$status" -eq 1 ]
    [[ $output == *"Invalid branch name"* ]]
}

@test "main writes has_changes=false when loop produced no commits" {
    BRANCH='loop/docs-updater-abc'
    GH_TOKEN='test-token'
    LOOP_HAS_CHANGES='false'
    WORKTREE_PATH='/tmp/worktree'
    run main
    [ "$status" -eq 0 ]
    grep -q '^has_changes=false$' "${GITHUB_OUTPUT}"
}

@test "main accepts valid branch name characters" {
    BRANCH='loop/docs-updater_1.2'
    GH_TOKEN='test-token'
    LOOP_HAS_CHANGES='false'
    WORKTREE_PATH='/tmp/worktree'
    run main
    [ "$status" -eq 0 ]
}

@test "main records redacted push failure when git push fails" {
    local mock_bin status_dir worktree

    mock_bin="${BATS_TEST_TMPDIR}/bin"
    status_dir="${BATS_TEST_TMPDIR}/status"
    worktree="${BATS_TEST_TMPDIR}/worktree"
    mkdir -p "${mock_bin}" "${status_dir}" "${worktree}"
    git -C "${worktree}" init -q

    cat > "${mock_bin}/git" << 'EOF'
#!/bin/bash
if [[ "$1" == "config" ]]; then
    exit 0
fi
if [[ "$1" == "push" ]]; then
    echo "error: x-access-token:ghp_abcdefghijklmnopqrstuvwxyz rejected" >&2
    exit 1
fi
exit 0
EOF
    chmod +x "${mock_bin}/git"
    export PATH="${mock_bin}:${PATH}"

    BRANCH='loop/docs-updater-abc'
    GH_TOKEN='test-token'
    LOOP_HAS_CHANGES='true'
    WORKTREE_PATH="${worktree}"
    STATUS_DIR="${status_dir}"
    export STATUS_DIR

    run main
    [ "$status" -eq 1 ]
    [ -f "${status_dir}/failure.json" ]
    [ "$(jq -r '.failure_stage' "${status_dir}/failure.json")" = "push" ]
    [[ "$(jq -r '.failure_message' "${status_dir}/failure.json")" == *"[REDACTED]"* ]]
    [[ "$(jq -r '.failure_message' "${status_dir}/failure.json")" != *"ghp_"* ]]
}
