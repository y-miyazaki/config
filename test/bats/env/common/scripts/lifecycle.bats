#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for env/common/scripts/on_create.sh, update_content.sh, post_create.sh and post_start.sh
#
# Use cases:
# - adjust_ownership chowns existing config paths including ~/.claude and skips missing ones
# - every lifecycle script prints usage on --help and fails on an unknown argument
# - each lifecycle script runs exactly its own steps in the documented order
# - update_content installs mise tools and the global node before apm, aqua, pre-commit and tflint
# - install_apm runs apm install --frozen, warns with lockfile recovery steps on failure, and skips without apm.yml

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    REPO_ROOT="$(bats_workspace_root)"
    SCRIPT_DIR="${REPO_ROOT}/env/common/scripts"
}

# run_steps: Source one lifecycle script, stub every step to log its name, and run main
# Arguments:
#   $1 - script file name
run_steps() {
    local script="$1"
    run bash -c "
        source '${SCRIPT_DIR}/${script}'
        for fn in adjust_ownership configure_claude_statusline configure_cursor_statusline \
            configure_github_credentials index_codebase_memory install_apm \
            install_aqua install_gh_extension install_mise install_mise_global_node \
            install_pre_commit prepare_terraform; do
            eval \"\${fn}() { echo \${fn}; }\"
        done
        resolve_repo_root() { printf /nowhere; }
        main
    "
}

# run_install_apm: Run install_apm with a stub apm that exits with the given status
# Arguments:
#   $1 - exit status of the stub apm
#   $2 - "with-yml" to create apm.yml in the repo root, anything else to omit it
run_install_apm() {
    local apm_status="$1" yml="$2" fake_bin="${BATS_TEST_TMPDIR}/bin" root="${BATS_TEST_TMPDIR}/repo"
    mkdir -p "${fake_bin}" "${root}"
    [[ ${yml} == with-yml ]] && touch "${root}/apm.yml"
    printf '#!/bin/bash\necho "apm $*" >> "%s/apm.log"\nexit %s\n' "${BATS_TEST_TMPDIR}" "${apm_status}" > "${fake_bin}/apm"
    chmod +x "${fake_bin}/apm"
    run bash -c "
        export PATH='${fake_bin}':\"\${PATH}\"
        source '${REPO_ROOT}/env/common/scripts/lib/init_steps.sh'
        REPO_ROOT='${root}'
        install_apm
    "
}

@test "adjust_ownership chowns existing config paths including .claude and skips missing ones" {
    local fake_home="${BATS_TEST_TMPDIR}/home" fake_bin="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${fake_home}/.claude" "${fake_home}/.aws" "${fake_bin}"
    printf '#!/bin/bash\necho "$*" >> "%s/sudo.log"\n' "${BATS_TEST_TMPDIR}" > "${fake_bin}/sudo"
    chmod +x "${fake_bin}/sudo"
    run bash -c "
        export HOME='${fake_home}' PATH='${fake_bin}':\"\${PATH}\"
        source '${REPO_ROOT}/env/common/scripts/lib/init_steps.sh'
        adjust_ownership
    "
    [ "$status" -eq 0 ]
    grep -q "chown -R .* ${fake_home}/.claude\$" "${BATS_TEST_TMPDIR}/sudo.log"
    grep -q "chown -R .* ${fake_home}/.aws\$" "${BATS_TEST_TMPDIR}/sudo.log"
    run grep -q "\.ssh\|\.gitconfig\|\.local" "${BATS_TEST_TMPDIR}/sudo.log"
    [ "$status" -eq 1 ]
}

@test "every lifecycle script fails on an unknown argument" {
    local script
    for script in on_create update_content post_create post_start; do
        run bash "${SCRIPT_DIR}/${script}.sh" --bogus
        [ "$status" -eq 1 ]
        [[ $output == *"Unknown argument: --bogus"* ]]
    done
}

@test "every lifecycle script prints usage on --help" {
    local script
    for script in on_create update_content post_create post_start; do
        run bash "${SCRIPT_DIR}/${script}.sh" --help
        [ "$status" -eq 0 ]
        [[ $output == *"Usage: ${script}.sh"* ]]
    done
}

@test "install_apm runs apm install --frozen and prints no warning on success" {
    run_install_apm 0 with-yml
    [ "$status" -eq 0 ]
    grep -qx "apm install --frozen" "${BATS_TEST_TMPDIR}/apm.log"
    [[ $output != *"[warn]"* ]]
}


@test "install_apm skips apm when apm.yml is absent" {
    run_install_apm 1 no-yml
    [ "$status" -eq 0 ]
    [ ! -f "${BATS_TEST_TMPDIR}/apm.log" ]
}

@test "install_apm warns with the lockfile recovery steps when the frozen install fails" {
    run_install_apm 1 with-yml
    [ "$status" -eq 0 ]
    [[ $output == *"[warn] apm install --frozen failed"* ]]
    [[ $output == *"apm install"*"apm.lock.yaml"* ]]
}


@test "on_create runs only the ownership step" {
    run_steps on_create.sh
    [ "$status" -eq 0 ]
    [ "$output" = "adjust_ownership" ]
}

@test "post_create configures statuslines and credentials in order" {
    run_steps post_create.sh
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '%s\n' configure_claude_statusline configure_cursor_statusline configure_github_credentials)" ]
}

@test "post_start runs only the codebase index step" {
    run_steps post_start.sh
    [ "$status" -eq 0 ]
    [ "$output" = "index_codebase_memory" ]
}

@test "update_content installs mise tools and the global node before the dependent tools" {
    run_steps update_content.sh
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '%s\n' install_mise install_mise_global_node install_apm install_aqua install_gh_extension install_pre_commit prepare_terraform)" ]
}
