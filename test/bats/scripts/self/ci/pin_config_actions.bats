#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for scripts/self/ci/pin_config_actions.sh
#
# Use cases:
# - --help exits successfully
# - unknown options exit with an error
# - --dry-run completes without mutating an isolated repository
# - next_patch_tag increments the latest v-prefixed tag

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

PIN_SCRIPT="$(bats_workspace_root)/scripts/self/ci/pin_config_actions.sh"

setup() {
    git_test_repo_setup
}

@test "pin_config_actions --dry-run completes in an isolated repository" {
    mkdir -p "${GIT_TEST_REPO}/.github/workflows"
    cat > "${GIT_TEST_REPO}/.github/workflows/test.yaml" << 'EOF'
jobs:
  test:
    steps:
      - uses: y-miyazaki/config/.github/actions/example@abc1234 # v1.0.0
EOF
    git_test_repo_commit "add workflow"

    git_test_repo_run "bash '${PIN_SCRIPT}' --dry-run --no-push"
    [ "$status" -eq 0 ]
    [[ $output == *"Done."* ]]
    [[ $output == *"[dry-run]"* ]]
}

@test "pin_config_actions --help exits successfully" {
    run bash "${PIN_SCRIPT}" --help
    [ "$status" -eq 0 ]
    [[ $output == *"pin_config_actions.sh"* ]]
}

@test "next_patch_tag increments the latest patch version" {
    git_test_repo_commit "init"
    git -C "${GIT_TEST_REPO}" tag v1.2.3

    run bash -c "cd '${GIT_TEST_REPO}' && source '${PIN_SCRIPT}' && next_patch_tag"
    [ "$status" -eq 0 ]
    [ "$output" = "v1.2.4" ]
}

@test "pin_config_actions rejects unknown options" {
    run bash "${PIN_SCRIPT}" --unknown-option
    [ "$status" -eq 1 ]
    [[ $output == *"Unknown option"* ]]
}
