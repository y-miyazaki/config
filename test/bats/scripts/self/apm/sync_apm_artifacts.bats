#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for scripts/self/apm/sync_apm_artifacts.sh
#
# Use cases:
# - sync_apm_artifacts.sh --check loop-contract runs contract validation only
# - sync_apm_artifacts.sh --check skips apm install and audit components
# - sync_apm_artifacts.sh --skip-install skips apm install
# - sync path never runs a separate apm-postinstall step
# - a default run is skipped when the watched inputs are unchanged since the last full sync
# - an edit to .apm, scripts, apm.yml or apm.lock.yaml makes the default run proceed
# - --force, --check, explicit components and --skip-* flags never skip
# - only a successful default run records the fingerprint
# - the fingerprint lives in the git dir and ignores files outside the watched paths

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

# fingerprint_repo: Create a throwaway git repo with the watched inputs and a copy of the script
function fingerprint_repo {
    FP_REPO="${BATS_TEST_TMPDIR}/fp_repo"
    rm -rf "${FP_REPO}"
    mkdir -p "${FP_REPO}/.apm/pkg" "${FP_REPO}/scripts/self/apm"
    git -C "${FP_REPO}" init -q
    echo a > "${FP_REPO}/.apm/pkg/file"
    echo s > "${FP_REPO}/scripts/tool.sh"
    echo y > "${FP_REPO}/apm.yml"
    echo l > "${FP_REPO}/apm.lock.yaml"
    cp "${REPO_ROOT}/scripts/self/apm/sync_apm_artifacts.sh" "${FP_REPO}/scripts/self/apm/"
}

# fp_decide: Source the copied script and print SKIP or RUN for the given env assignments
function fp_decide {
    run env -u GIT_DIR -u GIT_WORK_TREE bash -c "cd '${FP_REPO}' && source scripts/self/apm/sync_apm_artifacts.sh && $* ; if should_skip_unchanged; then echo SKIP; else echo RUN; fi"
}

@test "a default run is skipped when the watched inputs are unchanged since the last full sync" {
    fingerprint_repo
    fp_decide "save_fingerprint"
    [ "$status" -eq 0 ]
    [[ ${lines[-1]} == "SKIP" ]]
}

@test "an edit to .apm, scripts, apm.yml or apm.lock.yaml makes the default run proceed" {
    fingerprint_repo
    local target
    for target in .apm/pkg/file scripts/tool.sh apm.yml apm.lock.yaml; do
        fp_decide "save_fingerprint; echo changed >> '${FP_REPO}/${target}'"
        [ "$status" -eq 0 ]
        [[ ${lines[-1]} == "RUN" ]]
    done
    fp_decide "save_fingerprint; echo new > '${FP_REPO}/scripts/new_untracked.sh'"
    [[ ${lines[-1]} == "RUN" ]]
}

@test "--force, --check, explicit components and --skip-* flags never skip" {
    fingerprint_repo
    local flag
    for flag in FORCE=true CHECK_MODE=true EXPLICIT_COMPONENTS=true SKIP_INSTALL=true SKIP_AUDIT=true; do
        fp_decide "save_fingerprint; ${flag}"
        [ "$status" -eq 0 ]
        [[ ${lines[-1]} == "RUN" ]]
    done
}

@test "only a successful default run records the fingerprint" {
    fingerprint_repo
    local flag
    for flag in CHECK_MODE=true EXPLICIT_COMPONENTS=true SKIP_INSTALL=true SKIP_AUDIT=true; do
        run env -u GIT_DIR -u GIT_WORK_TREE bash -c "cd '${FP_REPO}' && source scripts/self/apm/sync_apm_artifacts.sh && ${flag} save_fingerprint"
        [ "$status" -eq 0 ]
        [ ! -e "${FP_REPO}/.git/apm-sync-fingerprint" ]
    done
    run env -u GIT_DIR -u GIT_WORK_TREE bash -c "cd '${FP_REPO}' && source scripts/self/apm/sync_apm_artifacts.sh && save_fingerprint"
    [ -s "${FP_REPO}/.git/apm-sync-fingerprint" ]
}

@test "the fingerprint lives in the git dir and ignores files outside the watched paths" {
    fingerprint_repo
    fp_decide "save_fingerprint; echo other > '${FP_REPO}/README.md'; mkdir -p '${FP_REPO}/.claude'; echo gen > '${FP_REPO}/.claude/generated'"
    [ "$status" -eq 0 ]
    [[ ${lines[-1]} == "SKIP" ]]
    [ -s "${FP_REPO}/.git/apm-sync-fingerprint" ]
    run git -C "${FP_REPO}" status --porcelain
    [[ $output != *"apm-sync-fingerprint"* ]]
}
