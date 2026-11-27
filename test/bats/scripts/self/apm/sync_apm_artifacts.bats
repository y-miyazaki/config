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
# - --mcp-reclaim (or APM_SYNC_MCP_RECLAIM=true) removes only the .mcp.json entries of servers declared in enabled packages before apm install
# - without --mcp-reclaim .mcp.json is left untouched
# - an invalid-receipt failure sets the receipt aside, retries once with --force and removes the backup on success
# - a failed retry restores the receipt; a path outside the receipts directory and unrelated failures are left alone
# - the --apm-force hint is not printed when --apm-force is already set
# - a failed apm run replays its stdout on stderr; a successful run keeps it on stdout
# - a failed apm install after --mcp-reclaim restores the original .mcp.json
# - a successful apm install after --mcp-reclaim keeps the reclaimed .mcp.json and leaves no backup
# - --mcp-reclaim without a .mcp.json succeeds and creates none
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

# mcp_reclaim_repo: Build a repo with one enabled package, one disabled package and a hand-edited .mcp.json
function mcp_reclaim_repo {
    MR_ROOT="${TEST_TMP}/mcp_root"
    mkdir -p "${MR_ROOT}/.apm/packages/on" "${MR_ROOT}/.apm/packages/off"
    printf 'dependencies:\n  apm:\n    - ./.apm/packages/on\n    # - ./.apm/packages/off\n' > "${MR_ROOT}/apm.yml"
    printf 'dependencies:\n  apm: []\n  mcp:\n    - name: github\n      registry: false\n    - name: fetch\n      registry: false\n' > "${MR_ROOT}/.apm/packages/on/apm.yml"
    printf 'dependencies:\n  mcp:\n    - name: disabled-server\n' > "${MR_ROOT}/.apm/packages/off/apm.yml"
    printf '{"mcpServers":{"github":{"x":1},"fetch":{"x":2},"disabled-server":{"x":3},"mine":{"x":4}}}\n' > "${MR_ROOT}/.mcp.json"
}

@test "reclaim_apm_mcp_connections removes only entries of servers declared in enabled packages" {
    mcp_reclaim_repo
    run bash -c "source '${REPO_ROOT}/scripts/self/apm/sync_apm_artifacts.sh' && reclaim_apm_mcp_connections '${MR_ROOT}'"
    [ "$status" -eq 0 ]
    [[ $output == *"removed .mcp.json entry 'github'"* ]]
    run jq -c '.mcpServers|keys' "${MR_ROOT}/.mcp.json"
    [ "$output" = '["disabled-server","mine"]' ]
}

@test "reclaim_apm_mcp_connections does nothing when .mcp.json or apm.yml is absent" {
    mcp_reclaim_repo
    rm "${MR_ROOT}/.mcp.json"
    run bash -c "source '${REPO_ROOT}/scripts/self/apm/sync_apm_artifacts.sh' && reclaim_apm_mcp_connections '${MR_ROOT}'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "apm install reclaims .mcp.json entries with --mcp-reclaim and leaves them without it" {
    mcp_reclaim_repo
    local mock_bin="${BATS_TEST_TMPDIR}/mock_bin_reclaim"
    mkdir -p "${mock_bin}"
    printf '#!/bin/bash\nexit 0\n' > "${mock_bin}/apm"
    chmod +x "${mock_bin}/apm"
    local src="source '${REPO_ROOT}/scripts/self/apm/sync_apm_artifacts.sh' && check_agent_config_json() { return 0; } && resolve_repo_root() { echo '${MR_ROOT}'; }"
    run env PATH="${mock_bin}:${PATH}" bash -c "${src} && parse_arguments apm-install && run_apm_install_component"
    [ "$status" -eq 0 ]
    run jq -r '.mcpServers|keys|length' "${MR_ROOT}/.mcp.json"
    [ "$output" = "4" ]
    run env PATH="${mock_bin}:${PATH}" bash -c "${src} && parse_arguments --mcp-reclaim apm-install && run_apm_install_component"
    [ "$status" -eq 0 ]
    run jq -r '.mcpServers|keys|length' "${MR_ROOT}/.mcp.json"
    [ "$output" = "2" ]
    mcp_reclaim_repo
    run env APM_SYNC_MCP_RECLAIM=true PATH="${mock_bin}:${PATH}" bash -c "${src} && parse_arguments apm-install && run_apm_install_component"
    run jq -r '.mcpServers|keys|length' "${MR_ROOT}/.mcp.json"
    [ "$output" = "2" ]
}

# receipt_repo: Mock apm that rejects an existing receipt; sets RC_HOME, RC_RECEIPT, RC_BIN, RC_LOG
function receipt_repo {
    RC_HOME="${BATS_TEST_TMPDIR}/rc_home"
    RC_RECEIPT="${RC_HOME}/.apm/deployment-receipts/abc123.json"
    RC_BIN="${BATS_TEST_TMPDIR}/rc_bin"
    RC_LOG="${BATS_TEST_TMPDIR}/rc_apm.log"
    mkdir -p "${RC_HOME}/.apm/deployment-receipts" "${RC_BIN}"
    printf '{}\n' > "${RC_RECEIPT}"
    cat > "${RC_BIN}/apm" << 'EOF'
#!/bin/bash
echo "$*" >> "${RC_LOG}"
if [[ -f ${RC_REJECT} ]]; then
    echo "Invalid local materialization evidence at ${RC_REJECT}: installation binding does not match."
    exit 1
fi
exit 0
EOF
    chmod +x "${RC_BIN}/apm"
}

# receipt_run: Run run_apm_install_component against the receipt mock (RC_REJECT and RC_ARGS come from the caller environment)
function receipt_run {
    local src="source '${REPO_ROOT}/scripts/self/apm/sync_apm_artifacts.sh' && check_agent_config_json() { return 0; } && resolve_repo_root() { echo '${BATS_TEST_TMPDIR}'; }"
    run env HOME="${RC_HOME}" RC_LOG="${RC_LOG}" RC_REJECT="${RC_REJECT:-${RC_RECEIPT}}" PATH="${RC_BIN}:${PATH}" bash -c "${src} && parse_arguments ${RC_ARGS:-} apm-install && run_apm_install_component"
}

@test "an invalid receipt is set aside, the install retried once with --force and the backup removed" {
    receipt_repo
    receipt_run
    [ "$status" -eq 0 ]
    [[ $output == *"apm-recover: set aside invalid receipt ${RC_RECEIPT}"* ]]
    [ ! -e "${RC_RECEIPT}" ]
    [ ! -e "${RC_RECEIPT}.bak" ]
    [ "$(wc -l < "${RC_LOG}")" -eq 2 ]
    [[ "$(sed -n 2p "${RC_LOG}")" == *"--force"* ]]
    [[ "$(sed -n 1p "${RC_LOG}")" != *"--force"* ]]
}

@test "the retry does not repeat --force when --apm-force is already set and no hint is printed" {
    receipt_repo
    RC_ARGS="--apm-force" receipt_run
    [ "$status" -eq 0 ]
    [ "$(grep -o -- '--force' <<< "$(sed -n 2p "${RC_LOG}")" | wc -l)" -eq 1 ]
    [[ $output != *"HINT"* ]]
}

@test "a receipt outside the receipts directory is left alone" {
    receipt_repo
    local other="${BATS_TEST_TMPDIR}/elsewhere.json"
    printf '{}\n' > "${other}"
    RC_REJECT="${other}" receipt_run
    [ "$status" -eq 1 ]
    [[ $output == *"not recovering"* ]]
    [ -e "${other}" ]
    [ ! -e "${other}.bak" ]
    [ "$(wc -l < "${RC_LOG}")" -eq 1 ]
}

@test "a failed retry restores the receipt and fails" {
    receipt_repo
    cat > "${RC_BIN}/apm" << 'EOF'
#!/bin/bash
echo "Invalid local materialization evidence at ${RC_REJECT}: x"
exit 1
EOF
    receipt_run
    [ "$status" -eq 1 ]
    [[ $output == *"retry failed; restored ${RC_RECEIPT}"* ]]
    [[ $output != *"HINT"* ]]
    [ -e "${RC_RECEIPT}" ]
    [ ! -e "${RC_RECEIPT}.bak" ]
}

@test "an unrelated apm failure does not touch the receipt and prints the hint" {
    receipt_repo
    printf '#!/bin/bash\necho "network down"\nexit 1\n' > "${RC_BIN}/apm"
    receipt_run
    [ "$status" -eq 1 ]
    [ -e "${RC_RECEIPT}" ]
    [[ $output == *"HINT"* ]]
}

@test "a failed apm run replays its stdout on stderr and a successful run keeps it on stdout" {
    local mock_bin="${BATS_TEST_TMPDIR}/mock_bin_stdout"
    mkdir -p "${mock_bin}"
    cat > "${mock_bin}/apm" << 'EOF'
#!/bin/bash
echo "apm-reason"
exit "${APM_MOCK_RC}"
EOF
    chmod +x "${mock_bin}/apm"
    local src="source '${REPO_ROOT}/scripts/self/apm/sync_apm_artifacts.sh'"
    run env APM_MOCK_RC=1 PATH="${mock_bin}:${PATH}" bash -c "${src} && run_apm_command install 2>&1 >/dev/null"
    [ "$status" -eq 1 ]
    [ "$output" = "apm-reason" ]
    run env APM_MOCK_RC=0 PATH="${mock_bin}:${PATH}" bash -c "${src} && run_apm_command install 2>/dev/null"
    [ "$status" -eq 0 ]
    [ "$output" = "apm-reason" ]
}

@test "a failed apm install after --mcp-reclaim restores the original .mcp.json" {
    mcp_reclaim_repo
    local before mock_bin="${BATS_TEST_TMPDIR}/mock_bin_reclaim_fail"
    before="$(cat "${MR_ROOT}/.mcp.json")"
    mkdir -p "${mock_bin}"
    printf '#!/bin/bash\nexit 1\n' > "${mock_bin}/apm"
    chmod +x "${mock_bin}/apm"
    local src="source '${REPO_ROOT}/scripts/self/apm/sync_apm_artifacts.sh' && check_agent_config_json() { return 0; } && resolve_repo_root() { echo '${MR_ROOT}'; }"
    run env PATH="${mock_bin}:${PATH}" bash -c "${src} && parse_arguments --mcp-reclaim apm-install && run_apm_install_component"
    [ "$status" -eq 1 ]
    [[ $output == *"restored .mcp.json"* ]]
    [ "$(cat "${MR_ROOT}/.mcp.json")" = "${before}" ]
}

@test "a successful apm install after --mcp-reclaim keeps the reclaimed .mcp.json and leaves no backup" {
    mcp_reclaim_repo
    local mock_bin="${BATS_TEST_TMPDIR}/mock_bin_reclaim_ok" tmpdir="${BATS_TEST_TMPDIR}/tmpdir_ok"
    mkdir -p "${mock_bin}" "${tmpdir}"
    printf '#!/bin/bash\nexit 0\n' > "${mock_bin}/apm"
    chmod +x "${mock_bin}/apm"
    local src="source '${REPO_ROOT}/scripts/self/apm/sync_apm_artifacts.sh' && check_agent_config_json() { return 0; } && resolve_repo_root() { echo '${MR_ROOT}'; }"
    run env TMPDIR="${tmpdir}" PATH="${mock_bin}:${PATH}" bash -c "${src} && parse_arguments --mcp-reclaim apm-install && run_apm_install_component"
    [ "$status" -eq 0 ]
    run jq -c '.mcpServers|keys' "${MR_ROOT}/.mcp.json"
    [ "$output" = '["disabled-server","mine"]' ]
    [ -z "$(ls -A "${tmpdir}")" ]
}

@test "--mcp-reclaim without a .mcp.json succeeds and creates none" {
    mcp_reclaim_repo
    rm "${MR_ROOT}/.mcp.json"
    local mock_bin="${BATS_TEST_TMPDIR}/mock_bin_reclaim_none"
    mkdir -p "${mock_bin}"
    printf '#!/bin/bash\nexit 0\n' > "${mock_bin}/apm"
    chmod +x "${mock_bin}/apm"
    local src="source '${REPO_ROOT}/scripts/self/apm/sync_apm_artifacts.sh' && check_agent_config_json() { return 0; } && resolve_repo_root() { echo '${MR_ROOT}'; }"
    run env PATH="${mock_bin}:${PATH}" bash -c "${src} && parse_arguments --mcp-reclaim apm-install && run_apm_install_component"
    [ "$status" -eq 0 ]
    [ ! -e "${MR_ROOT}/.mcp.json" ]
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
