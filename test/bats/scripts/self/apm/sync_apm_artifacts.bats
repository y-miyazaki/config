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
# - apm install gets --force only with --apm-force, and a failed install prints the --apm-force recovery hint
# - check_agent_config_json refuses an agent config file that is not valid JSON and accepts valid or absent files
# - apm install is not started when an agent config file is not valid JSON
# - the guidelines component runs the generator from the repository root whatever the caller's directory, and fails when the generator fails

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

# apm_install_run: Source the script with a mock apm and run the install component
function apm_install_run {
    local mock_bin="${BATS_TEST_TMPDIR}/mock_bin"
    local apm_exit="$1"
    shift
    mkdir -p "${mock_bin}"
    printf '#!/bin/bash\nprintf "apm-args:%%s\\n" "$*"\nexit %s\n' "${apm_exit}" > "${mock_bin}/apm"
    chmod +x "${mock_bin}/apm"
    run env PATH="${mock_bin}:${PATH}" bash -c "source '${REPO_ROOT}/scripts/self/apm/sync_apm_artifacts.sh' && check_agent_config_json() { return 0; } && $* && run_apm_install_component"
}

@test "apm install runs without --force by default" {
    apm_install_run 0 "parse_arguments apm-install"
    [ "$status" -eq 0 ]
    [[ $output == *"apm-args:install --update"* ]]
    [[ $output != *"--force"* ]]
}

@test "--apm-force passes --force to apm install" {
    apm_install_run 0 "parse_arguments --apm-force apm-install"
    [ "$status" -eq 0 ]
    [[ $output == *"apm-args:install --update --force"* ]]
}

@test "a failed apm install prints the --apm-force recovery hint" {
    apm_install_run 1 "parse_arguments apm-install"
    [ "$status" -eq 1 ]
    [[ $output == *"--apm-force"* ]]
}

@test "check_agent_config_json refuses an agent config file that is not valid JSON" {
    local root="${TEST_TMP}/root"
    mkdir -p "${root}/.claude"
    printf '{\n  // "Bash(git push:*)",\n  "permissions": {}\n}\n' > "${root}/.claude/settings.json"
    run bash -c "source '${REPO_ROOT}/scripts/self/apm/sync_apm_artifacts.sh' && check_agent_config_json '${root}'"
    [ "$status" -eq 1 ]
    [[ $output == *".claude/settings.json is not valid JSON"* ]]
}

@test "check_agent_config_json accepts valid and absent agent config files" {
    local root="${TEST_TMP}/root_ok"
    mkdir -p "${root}/.claude"
    printf '{"permissions":{}}\n' > "${root}/.claude/settings.json"
    run bash -c "source '${REPO_ROOT}/scripts/self/apm/sync_apm_artifacts.sh' && check_agent_config_json '${root}'"
    [ "$status" -eq 0 ]
    rm -f "${root}/.claude/settings.json"
    run bash -c "source '${REPO_ROOT}/scripts/self/apm/sync_apm_artifacts.sh' && check_agent_config_json '${root}'"
    [ "$status" -eq 0 ]
}

@test "apm install is not started when an agent config file is not valid JSON" {
    local root="${TEST_TMP}/root_bad" mock_bin="${TEST_TMP}/bin_bad"
    mkdir -p "${root}/.claude" "${mock_bin}"
    printf '{ // comment\n}\n' > "${root}/.claude/settings.json"
    printf '#!/bin/bash\necho apm-called\n' > "${mock_bin}/apm"
    chmod +x "${mock_bin}/apm"
    run env PATH="${mock_bin}:${PATH}" bash -c "source '${REPO_ROOT}/scripts/self/apm/sync_apm_artifacts.sh' && resolve_repo_root() { echo '${root}'; } && run_apm_install_component"
    [ "$status" -eq 1 ]
    [[ $output != *"apm-called"* ]]
}

@test "the guidelines component runs the generator from the repository root whatever the caller's directory" {
    local root="${TEST_TMP}/root_guidelines" mock_bin="${TEST_TMP}/bin_guidelines" elsewhere="${TEST_TMP}/elsewhere"
    mkdir -p "${root}" "${mock_bin}" "${elsewhere}"
    printf '#!/bin/bash\npwd\n' > "${mock_bin}/perl"
    chmod +x "${mock_bin}/perl"
    run env PATH="${mock_bin}:${PATH}" bash -c "source '${REPO_ROOT}/scripts/self/apm/sync_apm_artifacts.sh' && resolve_repo_root() { echo '${root}'; } && cd '${elsewhere}' && sync_guidelines_component"
    [ "$status" -eq 0 ]
    [ "${lines[-1]}" = "$(cd "${root}" && pwd)" ]
}

@test "the guidelines component fails when the generator fails" {
    local root="${TEST_TMP}/root_guidelines_fail" mock_bin="${TEST_TMP}/bin_guidelines_fail"
    mkdir -p "${root}" "${mock_bin}"
    printf '#!/bin/bash\nexit 3\n' > "${mock_bin}/perl"
    chmod +x "${mock_bin}/perl"
    run env PATH="${mock_bin}:${PATH}" bash -c "source '${REPO_ROOT}/scripts/self/apm/sync_apm_artifacts.sh' && resolve_repo_root() { echo '${root}'; } && sync_guidelines_component"
    [ "$status" -eq 3 ]
}
