#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for scripts/self/apm/sync_apm_artifacts.sh
#
# Use cases:
# - sync_apm_artifacts.sh --check loop-contract runs contract validation only
# - sync_apm_artifacts.sh --check skips apm install and audit components
# - sync_apm_artifacts.sh --skip-install skips apm install
# - sync path never runs a separate apm-postinstall step

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    REPO_ROOT="$(bats_workspace_root)"
    TEST_TMP="${BATS_TEST_TMPDIR}/sync_apm_artifacts"
    mkdir -p "${TEST_TMP}"
}

@test "sync_apm_artifacts.sh --check loop-contract runs contract validation only" {
    run bash "${REPO_ROOT}/scripts/self/apm/sync_apm_artifacts.sh" --check loop-contract
    [ "$status" -eq 0 ]
    [[ $output == *"==> loop-contract"* ]]
    [[ $output == *"loop PR body contract: OK"* ]]
    [[ $output != *"==> apm-install"* ]]
    [[ $output != *"==> apm-audit"* ]]
}

@test "sync_apm_artifacts.sh --check skips apm install and audit components" {
    run bash "${REPO_ROOT}/scripts/self/apm/sync_apm_artifacts.sh" --check apm-install apm-audit
    [ "$status" -eq 0 ]
    [[ $output != *"==> apm-install"* ]]
    [[ $output != *"==> apm-postinstall"* ]]
    [[ $output != *"==> apm-audit"* ]]
}

@test "sync_apm_artifacts.sh --skip-install skips apm install" {
    run bash "${REPO_ROOT}/scripts/self/apm/sync_apm_artifacts.sh" --skip-install --skip-audit loop-contract
    [ "$status" -eq 0 ]
    [[ $output == *"==> loop-contract"* ]]
    [[ $output != *"==> apm-install"* ]]
    [[ $output != *"==> apm-postinstall"* ]]
}

@test "sync_apm_artifacts.sh source has no postinstall step" {
    run grep -E 'apm run postinstall|apm-postinstall|run_apm_postinstall' \
        "${REPO_ROOT}/scripts/self/apm/sync_apm_artifacts.sh"
    [ "$status" -eq 1 ]
}

@test "sync_apm_artifacts.sh does not hardcode /workspace" {
    run grep -E '/workspace/apm_modules' "${REPO_ROOT}/scripts/self/apm/sync_apm_artifacts.sh"
    [ "$status" -eq 1 ]
}
