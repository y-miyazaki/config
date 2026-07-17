#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-detect/lib/state.sh

# Use cases:
# - no pending / non-numeric pending.pr → do not block
# - pending + OPEN → block (live reality)
# - pending + CLOSED / MERGED → do not block (stale; promote should clear)
# - pending + unresolved / no token / no gh → fail closed (block)

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

install_gh_pr_state_mock() {
    local state="$1"
    local mock_bin="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${mock_bin}"
    cat > "${mock_bin}/gh" << EOF
#!/usr/bin/env bash
if [[ \$1 == "pr" && \$2 == "view" ]]; then
    printf '%s\\n' "${state}"
    exit 0
fi
exit 1
EOF
    chmod +x "${mock_bin}/gh"
    export PATH="${mock_bin}:${PATH}"
}

install_gh_failing_mock() {
    local mock_bin="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${mock_bin}"
    cat > "${mock_bin}/gh" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "${mock_bin}/gh"
    export PATH="${mock_bin}:${PATH}"
}

setup() {
    bats_source_rel ".github/actions/loop-detect/lib/state.sh"
}

@test "target_pending_blocks_detect returns false when pending is absent" {
    local target_state='{"last_sha":"abc123"}'
    run target_pending_blocks_detect "${target_state}"
    [ "$status" -eq 1 ]
}

@test "target_pending_blocks_detect returns false when pending pr is not a number" {
    local target_state='{"pending":{"pr":"42","sha":"abc123"}}'
    run target_pending_blocks_detect "${target_state}"
    [ "$status" -eq 1 ]
}

@test "target_pending_blocks_detect returns true when pending PR is OPEN" {
    local target_state='{"pending":{"pr":42,"sha":"abc123"}}'
    install_gh_pr_state_mock "OPEN"
    export GH_TOKEN='test-token'
    run target_pending_blocks_detect "${target_state}"
    [ "$status" -eq 0 ]
}

@test "target_pending_blocks_detect returns false when pending PR is CLOSED" {
    local target_state='{"pending":{"pr":42,"sha":"abc123"}}'
    install_gh_pr_state_mock "CLOSED"
    export GH_TOKEN='test-token'
    run target_pending_blocks_detect "${target_state}"
    [ "$status" -eq 1 ]
    [[ ${output} == *"stale"* ]]
}

@test "target_pending_blocks_detect returns false when pending PR is MERGED" {
    local target_state='{"pending":{"pr":42,"sha":"abc123"}}'
    install_gh_pr_state_mock "MERGED"
    export GH_TOKEN='test-token'
    run target_pending_blocks_detect "${target_state}"
    [ "$status" -eq 1 ]
    [[ ${output} == *"stale"* ]]
}

@test "target_pending_blocks_detect returns true when gh cannot resolve PR state" {
    local target_state='{"pending":{"pr":42,"sha":"abc123"}}'
    install_gh_failing_mock
    export GH_TOKEN='test-token'
    run target_pending_blocks_detect "${target_state}"
    [ "$status" -eq 0 ]
    [[ ${output} == *"unresolved"* ]]
}

@test "target_pending_blocks_detect returns true when token missing" {
    local target_state='{"pending":{"pr":42,"sha":"abc123"}}'
    unset GH_TOKEN GITHUB_TOKEN || true
    run target_pending_blocks_detect "${target_state}"
    [ "$status" -eq 0 ]
    [[ ${output} == *"unavailable"* ]]
}
