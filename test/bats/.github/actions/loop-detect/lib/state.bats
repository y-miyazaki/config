#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

bats_require_minimum_version 1.5.0
# Tests for .github/actions/loop-detect/lib/state.sh

# Use cases:
# - target_pending_pr_state reports none, OPEN, CLOSED, MERGED or unknown (a fact; admission decides what blocks)
# - target_state_apply_merged_pending promotes pending.sha only for a MERGED pending PR
# - target_last_sha returns the stored sha unchanged unless verification is requested
# - target_last_sha falls back to HEAD~10 with a stderr warning for an unreachable sha when verifying

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

@test "target_pending_pr_state reports none when pending is absent or its pr is not a number" {
    run target_pending_pr_state '{"last_sha":"abc123"}'
    [ "$status" -eq 0 ]
    [ "$output" = "none" ]
    run target_pending_pr_state '{"pending":{"pr":"42","sha":"abc123"}}'
    [ "$output" = "none" ]
}

@test "target_pending_pr_state reports the live state of the pending PR" {
    local state
    for state in OPEN CLOSED MERGED; do
        install_gh_pr_state_mock "${state}"
        export GITHUB_TOKEN='test-token'
        run target_pending_pr_state '{"pending":{"pr":42,"sha":"abc123"}}'
        [ "$status" -eq 0 ]
        [ "$output" = "${state}" ]
    done
}

@test "target_pending_pr_state reports unknown when gh cannot resolve the PR or the token is missing" {
    bats_require_minimum_version 1.5.0
    install_gh_failing_mock
    export GITHUB_TOKEN='test-token'
    run --separate-stderr target_pending_pr_state '{"pending":{"pr":42,"sha":"abc123"}}'
    [ "$output" = "unknown" ]
    [[ $stderr == *"unresolved"* ]]

    unset GITHUB_TOKEN || true
    run --separate-stderr target_pending_pr_state '{"pending":{"pr":42,"sha":"abc123"}}'
    [ "$output" = "unknown" ]
    [[ $stderr == *"unavailable"* ]]
}

@test "target_state_apply_merged_pending promotes pending.sha only for a MERGED pending PR" {
    local state='{"last_sha":"old","pending":{"pr":42,"sha":"new"}}'
    run --separate-stderr target_state_apply_merged_pending "${state}" "MERGED"
    [ "$(jq -r '.last_sha' <<< "${output}")" = "new" ]
    [ "$(jq -r 'has("pending")' <<< "${output}")" = "false" ]
    for fact in OPEN CLOSED unknown none; do
        run --separate-stderr target_state_apply_merged_pending "${state}" "${fact}"
        [ "$output" = "${state}" ]
    done
}

# make_last_sha_repo: create a repository with 3 commits in BATS_TEST_TMPDIR/repo
make_last_sha_repo() {
    REPO="${BATS_TEST_TMPDIR}/repo"
    git init -q "${REPO}"
    git -C "${REPO}" config user.email "test@example.com"
    git -C "${REPO}" config user.name "Test User"
    git -C "${REPO}" commit -q --allow-empty -m one
    git -C "${REPO}" commit -q --allow-empty -m two
    git -C "${REPO}" commit -q --allow-empty -m three
}

@test "target_last_sha falls back to HEAD~10 for an unreachable sha when verifying" {
    local expected
    make_last_sha_repo
    expected="$(git -C "${REPO}" rev-list --max-parents=0 HEAD | head -1)"
    run --separate-stderr bash -c "cd '${REPO}' && source '$(bats_workspace_root)/.github/actions/loop-detect/lib/state.sh' && target_last_sha '{\"last_sha\":\"deadbeefdeadbeefdeadbeefdeadbeefdeadbeef\"}' main true"
    [ "$status" -eq 0 ]
    [ "$output" = "${expected}" ]
    [[ $stderr == *"::warning::"* ]]
    [[ $stderr == *"deadbeef"* ]]
}

@test "target_last_sha keeps a reachable sha when verifying" {
    local sha
    make_last_sha_repo
    sha="$(git -C "${REPO}" rev-parse HEAD~1)"
    run --separate-stderr bash -c "cd '${REPO}' && source '$(bats_workspace_root)/.github/actions/loop-detect/lib/state.sh' && target_last_sha '{\"last_sha\":\"${sha}\"}' main true"
    [ "$status" -eq 0 ]
    [ "$output" = "${sha}" ]
    [ -z "$stderr" ]
}

@test "target_last_sha returns the stored sha without verification by default" {
    make_last_sha_repo
    run --separate-stderr bash -c "cd '${REPO}' && source '$(bats_workspace_root)/.github/actions/loop-detect/lib/state.sh' && target_last_sha '{\"last_sha\":\"deadbeef\"}' main"
    [ "$status" -eq 0 ]
    [ "$output" = "deadbeef" ]
}
