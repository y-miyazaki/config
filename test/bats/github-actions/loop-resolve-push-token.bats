#!/usr/bin/env bats

# Tests for .github/actions/loop-resolve-push-token/lib/resolve.sh
#
# Use cases:
# - prefers App token over GH_TOKEN_PUSH and GITHUB_TOKEN
# - falls back to GH_TOKEN_PUSH when App token is empty
# - falls back to GITHUB_TOKEN when both optional tokens are empty

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

RESOLVE_LIB="$(bats_workspace_root)/.github/actions/loop-resolve-push-token/lib/resolve.sh"

setup() {
    export GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/github_output"
    : > "${GITHUB_OUTPUT}"
    export GITHUB_TOKEN="actions-default-token"
}

@test "resolve_push_token emits warning when app token generation failed" {
    # shellcheck disable=SC1090
    source "${RESOLVE_LIB}"
    run bash -c 'source "'"${RESOLVE_LIB}"'"; BOT_APP_CONFIGURED=true APP_TOKEN= GH_TOKEN_PUSH=push-token GITHUB_TOKEN=default-token GITHUB_OUTPUT="'"${GITHUB_OUTPUT}"'" resolve_push_token'
    [ "$status" -eq 0 ]
    grep -q '^token=push-token$' "${GITHUB_OUTPUT}"
    [[ $output == *"GitHub App token generation failed"* ]]
}

@test "resolve_push_token prefers app token" {
    # shellcheck disable=SC1090
    source "${RESOLVE_LIB}"
    run bash -c 'source "'"${RESOLVE_LIB}"'"; APP_TOKEN=app-token GH_TOKEN_PUSH=push-token GITHUB_TOKEN=default-token GITHUB_OUTPUT="'"${GITHUB_OUTPUT}"'" resolve_push_token'
    [ "$status" -eq 0 ]
    grep -q '^token=app-token$' "${GITHUB_OUTPUT}"
}

@test "resolve_push_token falls back to gh token push" {
    # shellcheck disable=SC1090
    source "${RESOLVE_LIB}"
    run bash -c 'source "'"${RESOLVE_LIB}"'"; APP_TOKEN= GH_TOKEN_PUSH=push-token GITHUB_TOKEN=default-token GITHUB_OUTPUT="'"${GITHUB_OUTPUT}"'" resolve_push_token'
    [ "$status" -eq 0 ]
    grep -q '^token=push-token$' "${GITHUB_OUTPUT}"
}

@test "resolve_push_token falls back to github token" {
    # shellcheck disable=SC1090
    source "${RESOLVE_LIB}"
    run bash -c 'source "'"${RESOLVE_LIB}"'"; APP_TOKEN= GH_TOKEN_PUSH= GITHUB_TOKEN=default-token GITHUB_OUTPUT="'"${GITHUB_OUTPUT}"'" resolve_push_token'
    [ "$status" -eq 0 ]
    grep -q '^token=default-token$' "${GITHUB_OUTPUT}"
}
