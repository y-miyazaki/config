#!/usr/bin/env bats

# Tests for .apm/packages/github-actions/.apm/skills/github-actions-validation/scripts/validate.sh
#
# Use cases:
# - actionlint runs from the repository root so .github/actionlint.yaml applies
# - a workflows directory the caller gave resolves against the current directory (relative or absolute)
# - ghalint takes no path argument and always runs from the repository root, whatever directory the caller passed
# - a workflows directory that does not exist is an error
# - an explicit directory scopes ORD-01 to that directory, even when it spells the default path

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    ROOT="$(bats_workspace_root)"
    VALIDATE="${ROOT}/.apm/packages/github-actions/.apm/skills/github-actions-validation/scripts/validate.sh"
}

# mock_ghalint: Put a ghalint shim on PATH that records its arguments and working directory
mock_ghalint() {
    MOCK_BIN="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${MOCK_BIN}"
    cat > "${MOCK_BIN}/ghalint" << 'SHIM'
#!/bin/bash
echo "args=[$*] cwd=$(pwd -P)" > "${GHALINT_ARGS_FILE}"
SHIM
    chmod +x "${MOCK_BIN}/ghalint"
}

@test "a workflows directory argument that is a file is an error" {
    : > "${BATS_TEST_TMPDIR}/ci.yml"
    run bash -c "cd '${BATS_TEST_TMPDIR}' && source '${VALIDATE}' && parse_arguments ci.yml"
    [ "$status" -ne 0 ]
    [[ $output == *"Path is not a directory: ci.yml"* ]]
}

@test "a workflows directory that does not exist is an error" {
    run bash -c "cd '${BATS_TEST_TMPDIR}' && source '${VALIDATE}' && parse_arguments no/such/dir"
    [ "$status" -ne 0 ]
    [[ $output == *"Path does not exist: no/such/dir"* ]]
}

@test "an explicit empty workflows directory yields no ORD-01 targets" {
    mkdir -p "${BATS_TEST_TMPDIR}/empty"
    run bash -c "cd '${BATS_TEST_TMPDIR}' && source '${VALIDATE}' && parse_arguments empty && targets=() && collect_yaml_map_order_targets targets && echo \"count=\${#targets[@]}\""
    [ "$status" -eq 0 ]
    [ "$output" = "count=0" ]
}

@test "an explicit workflows directory scopes ORD-01 to that directory even when it is the default path" {
    mkdir -p "${BATS_TEST_TMPDIR}/proj/.github/workflows" "${BATS_TEST_TMPDIR}/proj/.github/actions/x"
    : > "${BATS_TEST_TMPDIR}/proj/.github/workflows/a.yml"
    : > "${BATS_TEST_TMPDIR}/proj/.github/actions/x/action.yml"
    run bash -c "cd '${BATS_TEST_TMPDIR}/proj' && source '${VALIDATE}' && parse_arguments .github/workflows && targets=() && collect_yaml_map_order_targets targets && printf '%s\n' \"\${targets[@]}\""
    [ "$status" -eq 0 ]
    [ "$output" = ".github/workflows/a.yml" ]
}

@test "ghalint runs from the repository root when the caller passes a workflows directory" {
    mock_ghalint
    mkdir -p "${BATS_TEST_TMPDIR}/repo/sub/wf"
    git -C "${BATS_TEST_TMPDIR}/repo" init -q
    run env PATH="${MOCK_BIN}:${PATH}" GHALINT_ARGS_FILE="${BATS_TEST_TMPDIR}/args" bash -c "cd '${BATS_TEST_TMPDIR}/repo/sub' && source '${VALIDATE}' && parse_arguments wf && validate_ghalint"
    [ "$status" -eq 0 ]
    [ "$(cat "${BATS_TEST_TMPDIR}/args")" = "args=[run] cwd=$(cd "${BATS_TEST_TMPDIR}/repo" && pwd -P)" ]
}

@test "ghalint runs from the repository root when run from a subdirectory without arguments" {
    mock_ghalint
    mkdir -p "${BATS_TEST_TMPDIR}/repo/sub"
    git -C "${BATS_TEST_TMPDIR}/repo" init -q
    run env PATH="${MOCK_BIN}:${PATH}" GHALINT_ARGS_FILE="${BATS_TEST_TMPDIR}/args" bash -c "cd '${BATS_TEST_TMPDIR}/repo/sub' && source '${VALIDATE}' && parse_arguments && validate_ghalint"
    [ "$status" -eq 0 ]
    [ "$(cat "${BATS_TEST_TMPDIR}/args")" = "args=[run] cwd=$(cd "${BATS_TEST_TMPDIR}/repo" && pwd -P)" ]
}

@test "validate.sh succeeds when run from skill directory" {
    cd "${ROOT}/.apm/packages/github-actions/.apm/skills/github-actions-validation"
    run bash "${VALIDATE}" -q
    [ "$status" -eq 0 ]
}
