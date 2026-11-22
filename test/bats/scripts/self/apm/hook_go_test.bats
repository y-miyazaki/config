#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .apm/packages/go-hooks-*/.apm/hooks/scripts/go_test.sh
#
# Use cases:
# - a changed package with a failing test blocks the agent with the go test output
# - a changed package with passing tests exits silently
# - unchanged packages are not tested even when their tests fail
# - changed Go files outside any Go module are skipped
# - a changed go.mod tests every package of the module
# - a removed Go file still tests its surviving package
# - a removed package directory tests the whole module
# - a changed package whose files are all excluded by build constraints is skipped
# - an unchanged failing state blocks twice by default, then is skipped
# - every agent package ships the script and its hook config

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    ROOT="$(bats_workspace_root)"
    HOOK="${ROOT}/.apm/packages/go-hooks-claude/.apm/hooks/scripts/go_test.sh"
    REPO="${BATS_TEST_TMPDIR}/repo"
    STOP_JSON='{"hook_event_name":"Stop","stop_hook_active":false,"session_id":"s1"}'
    export GOCACHE="${BATS_TEST_TMPDIR}/gocache"
    export GOPATH="${BATS_TEST_TMPDIR}/gopath"
    export GOFLAGS=-mod=mod
    export TMPDIR="${BATS_TEST_TMPDIR}/state-tmp"
    mkdir -p "${TMPDIR}"
    unset HOOK_BLOCK_LIMIT

    mkdir -p "${REPO}/bad" "${REPO}/good"
    git -C "${REPO}" init -q
    git -C "${REPO}" config user.email "test@example.com"
    git -C "${REPO}" config user.name "test"
    printf 'module example.com/hooktest\n\ngo 1.21\n' > "${REPO}/go.mod"
    printf 'package bad\n\nfunc F() int { return 1 }\n' > "${REPO}/bad/bad.go"
    printf 'package bad\n\nimport "testing"\n\nfunc TestF(t *testing.T) { t.Fatal("boom") }\n' > "${REPO}/bad/bad_test.go"
    printf 'package good\n\nfunc F() int { return 1 }\n' > "${REPO}/good/good.go"
    printf 'package good\n\nimport "testing"\n\nfunc TestF(t *testing.T) { if F() != 1 { t.Fatal("x") } }\n' > "${REPO}/good/good_test.go"
    git -C "${REPO}" add .
    git -C "${REPO}" commit -q -m init
}

run_hook() {
    run bash -c "cd '${REPO}' && bash '${HOOK}' <<< '${STOP_JSON}'"
}

@test "an unchanged failing state blocks twice by default and is then skipped" {
    printf '\n// touch\n' >> "${REPO}/bad/bad.go"
    run_hook
    [[ ${output} == *'"decision": "block"'* ]]

    run_hook
    [[ ${output} == *'"decision": "block"'* ]]

    run_hook
    [ "$status" -eq 0 ]
    [ -z "${output}" ]
}

@test "changed Go files outside any Go module are skipped" {
    rm "${REPO}/go.mod"
    git -C "${REPO}" add -A
    git -C "${REPO}" commit -q -m "no module"
    printf '\n// touch\n' >> "${REPO}/bad/bad.go"
    run_hook
    [ "$status" -eq 0 ]
    [ -z "${output}" ]
}

@test "a changed package with a failing test blocks with go test output" {
    printf '\n// touch\n' >> "${REPO}/bad/bad.go"
    run_hook
    [ "$status" -eq 0 ]
    [[ ${output} == *'"decision": "block"'* ]]
    [[ ${output} == *'go test failed'* ]]
    [[ ${output} == *'boom'* ]]
}

@test "a changed package with passing tests exits silently" {
    printf '\n// touch\n' >> "${REPO}/good/good.go"
    run_hook
    [ "$status" -eq 0 ]
    [ -z "${output}" ]
}

@test "unchanged packages are not tested even when their tests fail" {
    printf '\n// touch\n' >> "${REPO}/good/good.go"
    run_hook
    [ "$status" -eq 0 ]
    [[ ${output} != *'boom'* ]]
}

@test "every agent package ships go_test.sh with the package-scoped test command" {
    local agent script
    for agent in claude copilot cursor; do
        script="${ROOT}/.apm/packages/go-hooks-${agent}/.apm/hooks/scripts/go_test.sh"
        [ -x "${script}" ]
        grep -q '^function collect_module_packages' "${script}"
        grep -q 'go test -short -timeout' "${script}"
        grep -q 'go_test.sh' "${ROOT}/.apm/packages/go-hooks-${agent}/.apm/hooks/go-test.json"
    done
}

@test "a changed go.mod tests every package of the module" {
    printf '\n// touch\n' >> "${REPO}/go.mod"
    run_hook
    [ "$status" -eq 0 ]
    [[ ${output} == *'"decision": "block"'* ]]
    [[ ${output} == *'boom'* ]]
}

@test "a removed Go file still tests its surviving package" {
    rm "${REPO}/good/good.go"
    run_hook
    [ "$status" -eq 0 ]
    [[ ${output} == *'"decision": "block"'* ]]
    [[ ${output} == *'go test failed'* ]]
}

@test "a removed package directory tests the whole module" {
    rm -r "${REPO}/good"
    run_hook
    [ "$status" -eq 0 ]
    [[ ${output} == *'"decision": "block"'* ]]
    [[ ${output} == *'boom'* ]]
}

@test "a changed package whose files are all excluded by build constraints is skipped" {
    mkdir -p "${REPO}/ign"
    printf '//go:build ignore\n\npackage ign\n' > "${REPO}/ign/i.go"
    run_hook
    [ "$status" -eq 0 ]
    [ -z "${output}" ]
}
