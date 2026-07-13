#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/validate-loop-caller-permissions/lib/validate.sh

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

VALIDATE_SCRIPT="$(bats_workspace_root)/.github/actions/validate-loop-caller-permissions/lib/validate.sh"
REGISTRY_FILE="$(bats_workspace_root)/.github/actions/validate-loop-caller-permissions/detect-permissions-profiles.yaml"
WRAPPER_SCRIPT="$(bats_workspace_root)/scripts/ci/validate_loop_caller_permissions.sh"

setup() {
    WORKFLOWS_TMPDIR="$(mktemp -d)"
    export REGISTRY_FILE
    export WORKFLOWS_DIR="${WORKFLOWS_TMPDIR}"
    export VERBOSE=false
}

teardown() {
    rm -rf "${WORKFLOWS_TMPDIR}"
}

write_loop_caller_fixture() {
    local name="$1"
    local permissions_block="$2"
    local uses_line="$3"
    local profile_line="${4:-}"

    cat > "${WORKFLOWS_TMPDIR}/${name}.yaml" << EOF
name: ${name}

on:
  workflow_dispatch: {}

permissions:
${permissions_block}

jobs:
  loop:
    uses: ./.github/workflows/${uses_line}
    with:
${profile_line}
      loop_name: test-loop
EOF
}

@test "fails when execute baseline permission is missing" {
    write_loop_caller_fixture "on-loop-missing-baseline" "  contents: write" "ci-loop-caller.yaml" ""

    run bash "${VALIDATE_SCRIPT}"
    [ "$status" -eq 1 ]
    [[ $output == *"missing execute baseline"* ]]
}

@test "fails when full-github profile lacks actions read" {
    write_loop_caller_fixture "on-loop-ci-sweeper" \
        "  contents: write
  copilot-requests: write
  pull-requests: write" \
        "ci-loop-caller-full-github.yaml" ""

    run bash "${VALIDATE_SCRIPT}"
    [ "$status" -eq 1 ]
    [[ $output == *"addition actions: read"* ]]
}

@test "fails when profile is not implemented" {
    write_loop_caller_fixture "on-loop-pr-scan" \
        "  contents: write
  copilot-requests: write
  pull-requests: write" \
        "ci-loop-caller.yaml" \
        "      detect_permissions_profile: pr-scan"

    run bash "${VALIDATE_SCRIPT}"
    [ "$status" -eq 1 ]
    [[ $output == *"not implemented in ci-loop-caller.yaml"* ]]
}

@test "passes for default profile caller" {
    write_loop_caller_fixture "on-loop-changelog" \
        "  contents: write
  copilot-requests: write
  pull-requests: write" \
        "ci-loop-caller.yaml" \
        ""

    run bash "${VALIDATE_SCRIPT}"
    [ "$status" -eq 0 ]
    [[ $output == *"validation passed (1 caller(s))"* ]]
}

@test "passes for full-github profile caller" {
    write_loop_caller_fixture "on-loop-ci-sweeper" \
        "  actions: read
  contents: write
  copilot-requests: write
  pull-requests: write" \
        "ci-loop-caller-full-github.yaml" \
        ""

    run bash "${VALIDATE_SCRIPT}"
    [ "$status" -eq 0 ]
    [[ $output == *"validation passed (1 caller(s))"* ]]
}

@test "passes when no loop callers are present" {
    run bash "${VALIDATE_SCRIPT}"
    [ "$status" -eq 0 ]
    [[ $output == *"No on-loop-* callers referencing ci-loop-caller reusable workflows found"* ]]
}

@test "requires REGISTRY_FILE environment variable" {
    unset REGISTRY_FILE

    run bash "${VALIDATE_SCRIPT}"
    [ "$status" -eq 1 ]
    [[ $output == *"REGISTRY_FILE is required"* ]]
}

@test "wrapper script validates dogfood callers" {
    run bash "${WRAPPER_SCRIPT}"
    [ "$status" -eq 0 ]
    [[ $output == *"validation passed"* ]]
}
