#!/usr/bin/env bats

# Tests for .apm/packages/go-hooks-*/.apm/hooks/scripts/golangci_lint.sh
#
# Use cases:
# - a changed package is linted on its own instead of the whole module
# - a changed go.mod lints the whole module
# - a package whose files are all excluded by build constraints is not linted
# - every agent package ships the same script

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    ROOT="$(bats_workspace_root)"
    HOOK="${ROOT}/.apm/packages/go-hooks-claude/.apm/hooks/scripts/golangci_lint.sh"
    REPO="${BATS_TEST_TMPDIR}/repo"
    STOP_JSON='{"hook_event_name":"Stop","stop_hook_active":false,"session_id":"s1"}'
    export GOCACHE="${BATS_TEST_TMPDIR}/gocache"
    export GOPATH="${BATS_TEST_TMPDIR}/gopath"
    export GOFLAGS=-mod=mod
    export TMPDIR="${BATS_TEST_TMPDIR}/state-tmp"
    mkdir -p "${TMPDIR}" "${BATS_TEST_TMPDIR}/bin"
    unset HOOK_BLOCK_LIMIT

    # Stub that records its arguments instead of linting
    cat > "${BATS_TEST_TMPDIR}/bin/golangci-lint" << 'STUB'
#!/bin/bash
echo "ARGS: $*"
STUB
    chmod +x "${BATS_TEST_TMPDIR}/bin/golangci-lint"

    mkdir -p "${REPO}/a" "${REPO}/b"
    git -C "${REPO}" init -q
    git -C "${REPO}" config user.email "test@example.com"
    git -C "${REPO}" config user.name "test"
    printf 'module example.com/hooktest\n\ngo 1.21\n' > "${REPO}/go.mod"
    printf 'package a\n' > "${REPO}/a/a.go"
    printf 'package b\n' > "${REPO}/b/b.go"
    git -C "${REPO}" add .
    git -C "${REPO}" commit -q -m init
}

run_hook() {
    run bash -c "cd '${REPO}' && PATH='${BATS_TEST_TMPDIR}/bin':\$PATH bash '${HOOK}' <<< '${STOP_JSON}'"
}

@test "a changed go.mod lints the whole module" {
    printf '\n// touch\n' >> "${REPO}/go.mod"
    cat > "${BATS_TEST_TMPDIR}/bin/golangci-lint" << 'STUB'
#!/bin/bash
echo "ARGS: $*" >&2
exit 1
STUB
    run_hook
    [[ ${output} == *'ARGS: run --fix ./...'* ]]
}

@test "a changed package is linted on its own instead of the whole module" {
    printf '\n// touch\n' >> "${REPO}/a/a.go"
    cat > "${BATS_TEST_TMPDIR}/bin/golangci-lint" << 'STUB'
#!/bin/bash
echo "ARGS: $*" >&2
exit 1
STUB
    run_hook
    [[ ${output} == *'ARGS: run --fix ./a'* ]]
    [[ ${output} != *'./b'* ]]
    [[ ${output} != *'./...'* ]]
}

@test "a package whose files are all excluded by build constraints is not linted" {
    mkdir -p "${REPO}/ign"
    printf '//go:build ignore\n\npackage ign\n' > "${REPO}/ign/i.go"
    cat > "${BATS_TEST_TMPDIR}/bin/golangci-lint" << 'STUB'
#!/bin/bash
echo "ARGS: $*" >&2
exit 1
STUB
    run_hook
    [ "$status" -eq 0 ]
    [[ ${output} != *'ARGS'* ]]
}

@test "every agent package ships the same golangci_lint.sh" {
    local agent
    for agent in copilot cursor; do
        cmp "${HOOK}" "${ROOT}/.apm/packages/go-hooks-${agent}/.apm/hooks/scripts/golangci_lint.sh"
    done
}
