#!/usr/bin/env bats

# Tests for .github/actions/loop-resolve-push-token/lib/resolve.sh
#
# Use cases:
# - prefers App token over INPUT_GITHUB_TOKEN and GITHUB_TOKEN
# - falls back to INPUT_GITHUB_TOKEN when App token is empty
# - falls back to GITHUB_TOKEN when both optional tokens are empty

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

RESOLVE_LIB="$(bats_workspace_root)/.github/actions/loop-resolve-push-token/lib/resolve.sh"
ACTION_YML="$(bats_workspace_root)/.github/actions/loop-resolve-push-token/action.yml"

setup() {
    export GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/github_output"
    : > "${GITHUB_OUTPUT}"
    export GITHUB_TOKEN="actions-default-token"
}

@test "action.yml requests workflows permission for workflow file pushes" {
    grep -q 'permission-workflows: write' "${ACTION_YML}"
}

@test "action.yml passes github.token as GITHUB_TOKEN for composite step fallback" {
    local line
    line="$(grep '^[[:space:]]*GITHUB_TOKEN:' "${ACTION_YML}")"
    [[ ${line} == *'github.token'* ]]
}

@test "resolve_github_token emits warning when app token generation failed" {
    # shellcheck disable=SC1090
    source "${RESOLVE_LIB}"
    run bash -c 'source "'"${RESOLVE_LIB}"'"; BOT_APP_CONFIGURED=true APP_TOKEN= INPUT_GITHUB_TOKEN=override-token GITHUB_TOKEN=default-token GITHUB_OUTPUT="'"${GITHUB_OUTPUT}"'" resolve_github_token'
    [ "$status" -eq 0 ]
    grep -q '^github_token=override-token$' "${GITHUB_OUTPUT}"
    [[ $output == *"GitHub App token generation failed"* ]]
}

@test "resolve_github_token prefers app token" {
    # shellcheck disable=SC1090
    source "${RESOLVE_LIB}"
    run bash -c 'source "'"${RESOLVE_LIB}"'"; APP_TOKEN=app-token INPUT_GITHUB_TOKEN=override-token GITHUB_TOKEN=default-token GITHUB_OUTPUT="'"${GITHUB_OUTPUT}"'" resolve_github_token'
    [ "$status" -eq 0 ]
    grep -q '^github_token=app-token$' "${GITHUB_OUTPUT}"
}

@test "resolve_github_token falls back to explicit github_token input" {
    # shellcheck disable=SC1090
    source "${RESOLVE_LIB}"
    run bash -c 'source "'"${RESOLVE_LIB}"'"; APP_TOKEN= INPUT_GITHUB_TOKEN=override-token GITHUB_TOKEN=default-token GITHUB_OUTPUT="'"${GITHUB_OUTPUT}"'" resolve_github_token'
    [ "$status" -eq 0 ]
    grep -q '^github_token=override-token$' "${GITHUB_OUTPUT}"
}

@test "resolve_github_token falls back to GITHUB_TOKEN" {
    # shellcheck disable=SC1090
    source "${RESOLVE_LIB}"
    run bash -c 'source "'"${RESOLVE_LIB}"'"; APP_TOKEN= INPUT_GITHUB_TOKEN= GITHUB_TOKEN=default-token GITHUB_OUTPUT="'"${GITHUB_OUTPUT}"'" resolve_github_token'
    [ "$status" -eq 0 ]
    grep -q '^github_token=default-token$' "${GITHUB_OUTPUT}"
}
