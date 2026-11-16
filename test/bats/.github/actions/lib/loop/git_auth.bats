#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/lib/loop/git_auth.sh
#
# Use cases:
# - git_auth_configure sets identity and the auth header in the local git config
# - git_auth_configure fails without writing config when GITHUB_TOKEN is empty

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/lib/loop/git_auth.sh"
    REPO="${BATS_TEST_TMPDIR}/repo"
    git init -q "${REPO}"
    cd "${REPO}" || return 1
}

@test "git_auth_configure fails without writing config when GITHUB_TOKEN is empty" {
    GITHUB_TOKEN="" run git_auth_configure
    [ "$status" -eq 1 ]
    [[ $output == *"GITHUB_TOKEN is required"* ]]
    run git config --local --get user.name
    [ "$status" -ne 0 ]
}

@test "git_auth_configure sets identity and the auth header in the local git config" {
    GITHUB_TOKEN="placeholder-token" run git_auth_configure
    [ "$status" -eq 0 ]
    [ "$(git config --local user.name)" = "github-actions[bot]" ]
    [ "$(git config --local user.email)" = "github-actions[bot]@users.noreply.github.com" ]
    expected="AUTHORIZATION: basic $(printf 'x-access-token:%s' placeholder-token | base64 -w0)"
    [ "$(git config --local http.https://github.com/.extraheader)" = "${expected}" ]
}
