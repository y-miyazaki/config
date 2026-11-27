#!/bin/bash
#######################################
# Description: Sync all APM distribution artifacts from repository source-of-truth paths
#
# Usage: ./sync_apm_artifacts.sh [--check] [--force] [--apm-force] [--mcp-reclaim] [--skip-install] [--skip-audit] [component...]
#   --check         Dry-run for bash-based sync scripts; skip apm install/audit
#   --force         Run even when the inputs are unchanged since the last full sync
#   --mcp-reclaim   Before apm install, drop the .mcp.json entries of MCP servers declared in the
#                   enabled packages so apm regenerates them (see reclaim_apm_mcp_connections);
#                   a failed apm install restores the original .mcp.json
#   --apm-force     Pass --force to apm install (recovery when apm has no trusted
#                   deployment baseline; also bypasses apm's critical security-scan block)
#   --skip-install  Apply sync but do not run apm install --update
#   --skip-audit    Apply sync/install but do not run apm audit --ci
#   component       skill-lib | validate-mirror | guidelines | loop-contract |
#                   apm-install | apm-skill-drift | apm-audit | all (default)
#
# Source-of-truth map (edit canonical files, then run this script):
#   skill-lib         → scripts/lib/
#   validate-mirror   → scripts/{shell-script,go,terraform}/
#   guidelines        → category-*.md under *-review skills (via Perl sync)
#   loop-contract     → loop PR body templates/envelopes under .apm/packages/
#   apm-install       → apm install --update (.apm/packages → agent install dirs)
#   apm-skill-drift   → loop skill sources vs installed mirrors (post-install check)
#   apm-audit         → apm audit --ci
#
# Default (no args): run all sync + install + drift check + audit.
#
# Change detection: a default run (no components, no --check/--skip-*) is skipped when
# .apm, scripts, apm.yml and apm.lock.yaml are byte-identical to the state recorded after
# the last successful full run (stored in the git dir, so it never needs a .gitignore entry).
# Explicit components, --check and --force always run.
#
# See CLAUDE.md § Edit Targets and .apm/CLAUDE.md § Validation Scripts Mirror.
#######################################

# Error handling: exit on error, unset variable, or failed pipeline
set -euo pipefail

# Secure defaults
umask 027
export LC_ALL=C.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CHECK_MODE="false"
FORCE="false"
APM_FORCE="false"
APM_LAST_FAILURE=""
MCP_RECLAIM="${APM_SYNC_MCP_RECLAIM:-false}"
SKIP_INSTALL="false"
SKIP_AUDIT="false"
declare -a COMPONENTS=()
EXPLICIT_COMPONENTS="false"

# Inputs whose content decides whether a default run has anything to sync
declare -a WATCHED_PATHS=(.apm scripts apm.yml apm.lock.yaml)

declare -a SYNC_COMPONENTS=(
    skill-lib
    validate-mirror
    guidelines
)

#######################################
# show_usage: Display usage information
#######################################
function show_usage {
    cat << 'EOF'
Usage: sync_apm_artifacts.sh [--check] [--force] [--apm-force] [--mcp-reclaim] [--skip-install] [--skip-audit] [component...]

Description:
    Sync APM artifacts, install package outputs, and verify integrity.
    A default run is skipped when .apm, scripts, apm.yml and apm.lock.yaml are unchanged
    since the last successful full run.

Components:
    skill-lib         scripts/lib/ → skill scripts/lib/ copies
    validate-mirror   scripts/<domain>/ → validation skill scripts/
    guidelines        category-*.md → instructions and common-checklist.md
    loop-contract     loop PR body templates/envelopes consistency checks
    apm-install       apm install --update (skipped with --check or --skip-install)
    apm-skill-drift   loop skill sources vs installed .claude/.agents mirrors
    apm-audit         apm audit --ci (skipped with --check or --skip-audit)
    all               all of the above (default)

Options:
    --check         Dry-run where supported; skip apm install and apm audit
    --force         Run even when the inputs are unchanged since the last full sync
    --apm-force     Pass --force to apm install (no trusted deployment baseline)
    --mcp-reclaim   Ignore drift in .mcp.json: remove entries of apm-declared MCP servers before
                    install so apm regenerates them (env APM_SYNC_MCP_RECLAIM=true does the same)
    --skip-install  Do not run apm install --update after sync
    --skip-audit    Do not run apm audit --ci after install

Examples:
    ./sync_apm_artifacts.sh
    ./sync_apm_artifacts.sh --check
    ./sync_apm_artifacts.sh --force
    ./sync_apm_artifacts.sh --skip-audit guidelines skill-lib
EOF
    exit 0
}

#######################################
# parse_arguments: Parse command line arguments
#######################################
function parse_arguments {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help)
                show_usage
                ;;
            --check)
                CHECK_MODE="true"
                shift
                ;;
            --force)
                FORCE="true"
                shift
                ;;
            --apm-force)
                APM_FORCE="true"
                shift
                ;;
            --mcp-reclaim)
                MCP_RECLAIM="true"
                shift
                ;;
            --skip-install)
                SKIP_INSTALL="true"
                shift
                ;;
            --skip-audit)
                SKIP_AUDIT="true"
                shift
                ;;
            apm-audit | apm-install | apm-skill-drift | guidelines | loop-contract | skill-lib | validate-mirror | all)
                COMPONENTS+=("$1")
                EXPLICIT_COMPONENTS="true"
                shift
                ;;
            *)
                echo "ERROR: Unknown argument: $1" >&2
                exit 1
                ;;
        esac
    done

    if [[ ${#COMPONENTS[@]} -eq 0 ]]; then
        COMPONENTS=("all")
    fi
}

#######################################
# check_agent_config_json: Refuse to run apm install over an agent config file that is not valid JSON
#
# Description:
#   apm install merges hooks into .claude/settings.json and .cursor/hooks.json. A file that does not
#   parse (for example one with // comment lines) is rewritten with the hooks only, and every
#   permission rule in it is lost. Failing early keeps the file untouched.
#
# Globals:
#   None
#
# Arguments:
#   $1 - Repository root
#
# Outputs:
#   ERROR line on stderr naming each invalid file
#
# Returns:
#   0 when every existing file parses; 1 otherwise
#
#######################################
function check_agent_config_json {
    local root="$1"
    local file rc=0

    for file in .claude/settings.json .cursor/hooks.json; do
        [[ -f ${root}/${file} ]] || continue
        if ! jq -e . "${root}/${file}" > /dev/null 2>&1; then
            echo "ERROR: ${file} is not valid JSON (comments are not allowed); apm install would overwrite it and drop its permissions. Fix it and rerun." >&2
            rc=1
        fi
    done
    return "${rc}"
}

#######################################
# check_apm_skill_drift_component: Detect APM skill install drift
#######################################
function check_apm_skill_drift_component {
    echo "==> apm-skill-drift"
    bash "${SCRIPT_DIR}/check_apm_skill_install_drift.sh"
}

#######################################
# check_loop_contract_component: Validate loop PR body skill contract files
#######################################
function check_loop_contract_component {
    echo "==> loop-contract"
    bash "${SCRIPT_DIR}/check_loop_pr_body_contract.sh"
}

#######################################
# component_selected: Return whether a component should run
#
# Globals:
#   COMPONENTS
#
# Arguments:
#   $1 - Component name
#
# Outputs:
#   None
#
# Returns:
#   0 when selected; 1 otherwise
#
#######################################
function component_selected {
    local component="$1"
    local selected

    for selected in "${COMPONENTS[@]}"; do
        if [[ ${selected} == "all" || ${selected} == "${component}" ]]; then
            return 0
        fi
    done
    return 1
}

#######################################
# compute_inputs_fingerprint: Hash the content of every tracked or untracked (non-ignored) watched file
#
# Globals:
#   WATCHED_PATHS - Paths whose content decides whether a sync is needed
#
# Arguments:
#   $1 - Repository root
#
# Outputs:
#   sha256 hex digest to stdout; empty when the root is not a git work tree
#
# Returns:
#   0 on success; 1 when the fingerprint cannot be computed
#######################################
function compute_inputs_fingerprint {
    local root="$1"

    if ! git -C "${root}" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        return 1
    fi

    # File names are part of the hash input, so renames and deletions change the digest too
    (
        cd "${root}"
        git ls-files -z --cached --others --exclude-standard -- "${WATCHED_PATHS[@]}" \
            | while IFS= read -r -d '' file; do
                # A tracked file deleted in the work tree is simply absent from the digest
                [[ -f ${file} ]] && sha256sum -- "${file}"
            done \
            | LC_ALL=C sort \
            | sha256sum \
            | cut -d' ' -f1
    )
}

#######################################
# ensure_apm_modules_local_permissions: Fix permissions on local APM modules when present
#######################################
function ensure_apm_modules_local_permissions {
    local repo_root apm_modules_local

    repo_root="$(resolve_repo_root)"
    apm_modules_local="${repo_root}/apm_modules/_local"

    if [[ ! -d ${apm_modules_local} ]]; then
        return 0
    fi

    # u+rwX: owner access, execute only on directories and files that already have it
    echo "==> chmod -R u+rwX ${apm_modules_local}"
    chmod -R u+rwX "${apm_modules_local}"
}

#######################################
# fingerprint_file: Print where the last-sync fingerprint is stored
#
# Globals:
#   None
#
# Arguments:
#   $1 - Repository root
#
# Outputs:
#   Absolute path inside the git dir (untracked, needs no .gitignore entry)
#
# Returns:
#   0 on success; 1 when the git dir cannot be resolved
#######################################
function fingerprint_file {
    local root="$1"
    local git_dir

    git_dir="$(git -C "${root}" rev-parse --absolute-git-dir 2> /dev/null)" || return 1
    printf '%s/apm-sync-fingerprint\n' "${git_dir}"
}

#######################################
# resolve_repo_root: Return the git repository root directory
#######################################
function resolve_repo_root {
    local root

    root="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel 2> /dev/null || true)"
    if [[ -n ${root} ]]; then
        printf '%s' "${root}"
        return 0
    fi

    cd "${SCRIPT_DIR}/../../.." && pwd
}

#######################################
# run_apm_audit_component: Run APM integrity audit for CI
#######################################
function run_apm_audit_component {
    echo "==> apm-audit"
    if ! command -v apm > /dev/null 2>&1; then
        echo "ERROR: apm command not found; install APM CLI before running sync_apm_artifacts.sh" >&2
        return 1
    fi
    run_apm_command audit --ci --no-drift
}

#######################################
# run_apm_command: Run an apm subcommand without known-benign discovery noise
#
# Description:
#   - Skips org policy discovery outside CI: the policy repo (.github-private) is not
#     published for this repository, so every run only warns "Policy repo ... not found".
#     CI keeps discovery so real policy violations still surface.
#   - Streams apm's stdout as it arrives and, when apm fails, replays it on stderr so the
#     failure reason is visible, and keeps the failed run's output in APM_LAST_FAILURE
#     (empty after a successful run).
#   - Drops the "hook event casing mismatch" warning for afterFileEdit: it is a native
#     Cursor event, but apm has no casing mapping for the cursor target.
#
# Arguments:
#   $@ - apm subcommand and arguments
#
# Returns:
#   Exit status of the apm command
#######################################
function run_apm_command {
    local -a env_args=()

    if [[ -z ${CI:-} ]]; then
        env_args+=(APM_POLICY_DISABLE=1)
    fi

    # Filter via a temp file (not process substitution) so no stderr arrives after we return.
    # apm reports many failures on stdout; a failing run replays it on stderr, the only stream
    # a failed Stop hook shows.
    local err_file out_file rc=0
    err_file="$(mktemp)"
    out_file="$(mktemp)"
    env "${env_args[@]}" apm "$@" 2> "${err_file}" | tee "${out_file}" || rc=${PIPESTATUS[0]}
    APM_LAST_FAILURE=""
    if [[ ${rc} -ne 0 ]]; then
        cat "${out_file}" >&2
        APM_LAST_FAILURE="$(cat "${out_file}" "${err_file}")"
    fi
    grep -v 'hook event casing mismatch (no mapping): afterFileEdit' "${err_file}" >&2 || true
    rm -f "${err_file}" "${out_file}"
    return "${rc}"
}

#######################################
# reclaim_apm_mcp_connections: Drop .mcp.json entries that apm would otherwise treat as conflicts
#
# Description:
#   apm refuses to overwrite a .mcp.json server entry it does not own (for example one that was
#   edited by hand) and --force does not change that. This removes the entries of every MCP server
#   declared in the enabled packages (uncommented ./.apm/packages/* lines of apm.yml) so the
#   following apm install regenerates them. Servers not declared by a package are left alone.
#
# Globals:
#   None
#
# Arguments:
#   $1 - Repository root
#
# Outputs:
#   One line per removed entry on stdout
#
# Returns:
#   0 always (nothing to do when .mcp.json or apm.yml is absent)
#
#######################################
function reclaim_apm_mcp_connections {
    local root="$1"
    local mcp_file="${root}/.mcp.json" pkg name tmp
    local -a names=()

    [[ -f ${mcp_file} && -f ${root}/apm.yml ]] || return 0
    while IFS= read -r pkg; do
        [[ -f ${root}/${pkg}/apm.yml ]] || continue
        while IFS= read -r name; do
            names+=("${name}")
        done < <(awk '/^  mcp:/{f=1;next} f&&/^    - name:/{print $3} f&&/^[^ ]/{f=0}' "${root}/${pkg}/apm.yml")
    done < <(sed -n 's/^[[:space:]]*-[[:space:]]*\(\.\/\.apm\/packages\/[A-Za-z0-9_-]*\)[[:space:]]*$/\1/p' "${root}/apm.yml")

    tmp="$(mktemp)"
    for name in "${names[@]}"; do
        if jq -e --arg n "${name}" '.mcpServers[$n]' "${mcp_file}" > /dev/null 2>&1; then
            jq --arg n "${name}" 'del(.mcpServers[$n])' "${mcp_file}" > "${tmp}" && cat "${tmp}" > "${mcp_file}"
            echo "mcp-reclaim: removed .mcp.json entry '${name}' (apm regenerates it)"
        fi
    done
    rm -f "${tmp}"
}

#######################################
# recover_invalid_receipt: Set aside the deployment receipt apm rejected as invalid
#
# Description:
#   apm refuses to run when its receipt under ~/.apm/deployment-receipts no longer matches
#   the installed files, and --force does not bypass that. The receipt is a derived cache and
#   the sync targets are git-tracked outputs, so the receipt is renamed (not deleted) and the
#   caller retries once; the caller restores it when the retry fails. Only a path inside the
#   receipts directory named by apm's own error is touched.
#
# Globals:
#   APM_LAST_FAILURE - Output of the failed apm run
#   HOME - Location of the receipts directory
#
# Arguments:
#   None
#
# Outputs:
#   STDOUT - Original receipt path (the backup is that path plus .bak)
#   STDERR - One line naming the receipt that was set aside
#
# Returns:
#   0 when a receipt was set aside, 1 when the failure is not an invalid receipt
#######################################
function recover_invalid_receipt {
    local receipt_dir="${HOME}/.apm/deployment-receipts" receipt
    [[ ${APM_LAST_FAILURE} == *"Invalid local materialization evidence"* ]] || return 1
    receipt="$(printf '%s\n' "${APM_LAST_FAILURE}" | sed -n 's/.*Invalid local materialization evidence at[[:space:]]*\([^[:space:]]*\.json\).*/\1/p' | head -n 1)"
    if [[ -z ${receipt} ]]; then
        # apm wraps long lines: the path can start on the next line
        receipt="$(printf '%s\n' "${APM_LAST_FAILURE}" | tr '\n' ' ' | sed -n 's/.*Invalid local materialization evidence at[[:space:]]*\([^[:space:]]*\.json\).*/\1/p' | head -n 1)"
    fi
    if [[ ${receipt} != "${receipt_dir}/"* || ${receipt} == *..* || ! -f ${receipt} ]]; then
        echo "apm-recover: apm reported an invalid receipt but its path is not a usable file in ${receipt_dir}; not recovering" >&2
        return 1
    fi
    mv "${receipt}" "${receipt}.bak" || return 1
    echo "apm-recover: set aside invalid receipt ${receipt}; retrying once with --force" >&2
    printf '%s\n' "${receipt}"
}

#######################################
# run_apm_install_component: Install APM package outputs into agent directories
#
# Description:
#   With --mcp-reclaim, .mcp.json is backed up first and restored when apm install fails,
#   because the reclaimed entries are only regenerated by a successful install.
#   An invalid deployment receipt is set aside and the install retried once (see
#   recover_invalid_receipt).
#######################################
function run_apm_install_component {
    echo "==> apm-install"
    if ! command -v apm > /dev/null 2>&1; then
        echo "ERROR: apm command not found; install APM CLI before running sync_apm_artifacts.sh" >&2
        return 1
    fi
    check_agent_config_json "$(resolve_repo_root)" || return 1
    local mcp_file mcp_backup=""
    mcp_file="$(resolve_repo_root)/.mcp.json"
    if [[ ${MCP_RECLAIM} == "true" ]]; then
        # Keep a copy: the reclaim removes entries that only a successful apm install regenerates
        if [[ -f ${mcp_file} ]]; then
            mcp_backup="$(mktemp)"
            # shellcheck disable=SC2064
            trap "rm -f '${mcp_backup}'; trap - RETURN" RETURN
            cat "${mcp_file}" > "${mcp_backup}"
        fi
        reclaim_apm_mcp_connections "$(resolve_repo_root)"
    fi
    local -a install_args=(install --update)

    if [[ ${APM_FORCE} == "true" ]]; then
        install_args+=(--force)
    fi
    local rc=0 receipt="" retried="false"
    run_apm_command "${install_args[@]}" || rc=$?
    if [[ ${rc} -ne 0 ]] && receipt="$(recover_invalid_receipt)"; then
        rc=0
        retried="true"
        local -a retry_args=("${install_args[@]}")
        [[ ${APM_FORCE} == "true" ]] || retry_args+=(--force)
        run_apm_command "${retry_args[@]}" || rc=$?
        if [[ ${rc} -eq 0 ]]; then
            rm -f "${receipt}.bak"
        else
            mv "${receipt}.bak" "${receipt}"
            echo "apm-recover: retry failed; restored ${receipt}" >&2
        fi
    fi
    if [[ ${rc} -ne 0 ]]; then
        # Sync targets are git-tracked outputs that are never hand-edited, so overwriting
        # them with --force is safe.
        if [[ -n ${mcp_backup} ]]; then
            cat "${mcp_backup}" > "${mcp_file}"
            rm -f "${mcp_backup}"
            echo "mcp-reclaim: apm install failed; restored .mcp.json" >&2
        fi
        if [[ ${APM_FORCE} != "true" && ${retried} != "true" ]]; then
            echo "HINT: if apm reports an invalid or missing deployment baseline, rerun with --apm-force" \
                "instead of deleting the receipt; review git status afterwards." >&2
        fi
        return 1
    fi
    [[ -z ${mcp_backup} ]] || rm -f "${mcp_backup}"
}

#######################################
# run_check_flag: Print --check when enabled
#######################################
function run_check_flag {
    if [[ ${CHECK_MODE} == "true" ]]; then
        printf '%s' "--check"
    fi
}

#######################################
# save_fingerprint: Record the post-sync state of the watched inputs
#
# Description:
#   Only a successful default run records the state; partial runs (explicit components,
#   --check, --skip-install, --skip-audit) never do, so they cannot hide pending work.
#
# Globals:
#   CHECK_MODE - Dry-run flag
#   EXPLICIT_COMPONENTS - Whether components were named on the command line
#   SKIP_AUDIT - Whether apm audit was skipped
#   SKIP_INSTALL - Whether apm install was skipped
#
# Arguments:
#   None
#
# Outputs:
#   None
#
# Returns:
#   0 always (recording is best effort)
#######################################
function save_fingerprint {
    local root file fingerprint

    if [[ ${CHECK_MODE} == "true" || ${EXPLICIT_COMPONENTS} == "true" || ${SKIP_INSTALL} == "true" || ${SKIP_AUDIT} == "true" ]]; then
        return 0
    fi

    root="$(resolve_repo_root)"
    file="$(fingerprint_file "${root}")" || return 0
    fingerprint="$(compute_inputs_fingerprint "${root}")" || return 0
    [[ -n ${fingerprint} ]] || return 0
    printf '%s\n' "${fingerprint}" > "${file}" 2> /dev/null || true
}

#######################################
# should_run_apm_audit: Return whether apm audit should run
#
# Globals:
#   CHECK_MODE
#   SKIP_AUDIT
#
# Arguments:
#   None
#
# Outputs:
#   None
#
# Returns:
#   0 when apm audit should run; 1 otherwise
#
#######################################
function should_run_apm_audit {
    if [[ ${CHECK_MODE} == "true" || ${SKIP_AUDIT} == "true" ]]; then
        return 1
    fi

    if component_selected "apm-audit"; then
        return 0
    fi

    should_run_apm_install
}

#######################################
# should_run_apm_install: Return whether apm install should run
#
# Globals:
#   CHECK_MODE
#   SKIP_INSTALL
#   COMPONENTS
#
# Arguments:
#   None
#
# Outputs:
#   None
#
# Returns:
#   0 when apm install should run; 1 otherwise
#
#######################################
function should_run_apm_install {
    local component

    if [[ ${CHECK_MODE} == "true" || ${SKIP_INSTALL} == "true" ]]; then
        return 1
    fi

    if component_selected "apm-install"; then
        return 0
    fi

    for component in "${SYNC_COMPONENTS[@]}"; do
        if component_selected "${component}"; then
            return 0
        fi
    done

    return 1
}

#######################################
# should_skip_unchanged: Return whether a default run has nothing to do
#
# Globals:
#   CHECK_MODE - Dry-run flag
#   EXPLICIT_COMPONENTS - Whether components were named on the command line
#   FORCE - Whether --force was given
#   SKIP_AUDIT - Whether apm audit was skipped
#   SKIP_INSTALL - Whether apm install was skipped
#
# Arguments:
#   None
#
# Outputs:
#   None
#
# Returns:
#   0 when the watched inputs match the last recorded full sync; 1 otherwise
#######################################
function should_skip_unchanged {
    local root file current recorded

    if [[ ${FORCE} == "true" || ${CHECK_MODE} == "true" || ${EXPLICIT_COMPONENTS} == "true" || ${SKIP_INSTALL} == "true" || ${SKIP_AUDIT} == "true" ]]; then
        return 1
    fi

    root="$(resolve_repo_root)"
    file="$(fingerprint_file "${root}")" || return 1
    [[ -f ${file} ]] || return 1
    recorded="$(cat "${file}" 2> /dev/null || true)"
    current="$(compute_inputs_fingerprint "${root}")" || return 1
    [[ -n ${current} && ${current} == "${recorded}" ]]
}

#######################################
# sync_guidelines_component: Regenerate instructions from category files
#######################################
function sync_guidelines_component {
    if [[ ${CHECK_MODE} == "true" ]]; then
        echo "==> guidelines (no --check mode; run without --check to apply)"
        return 0
    fi
    echo "==> guidelines"
    # The generator resolves .apm/ paths against the current directory, so run it from the repository root
    (cd "$(resolve_repo_root)" && perl "${SCRIPT_DIR}/sync_guidelines_from_categories.pl")
}

#######################################
# sync_skill_lib_component: Sync scripts/lib to skill copies
#######################################
function sync_skill_lib_component {
    echo "==> skill-lib"
    # shellcheck disable=SC2046
    bash "${SCRIPT_DIR}/sync_skill_lib.sh" $(run_check_flag)
}

#######################################
# sync_validate_mirror_component: Sync validation script mirrors
#######################################
function sync_validate_mirror_component {
    echo "==> validate-mirror"
    # shellcheck disable=SC2046
    bash "${SCRIPT_DIR}/sync_validate_mirror.sh" $(run_check_flag)
}

#######################################
# main: Run selected sync components in dependency order
#######################################
function main {
    local component

    parse_arguments "$@"

    if should_skip_unchanged; then
        echo "sync_apm_artifacts: no changes in ${WATCHED_PATHS[*]} since the last full sync; skipping (use --force to run anyway)."
        return 0
    fi

    # Mutates permissions, so skip for --check (and --help, which exits in parse_arguments)
    if [[ ${CHECK_MODE} != "true" ]]; then
        ensure_apm_modules_local_permissions
    fi

    for component in "${SYNC_COMPONENTS[@]}"; do
        if component_selected "${component}"; then
            case "${component}" in
                skill-lib) sync_skill_lib_component ;;
                validate-mirror) sync_validate_mirror_component ;;
                guidelines) sync_guidelines_component ;;
            esac
        fi
    done

    if component_selected "loop-contract"; then
        check_loop_contract_component
    fi

    if should_run_apm_install; then
        run_apm_install_component
    fi

    if component_selected "apm-skill-drift"; then
        check_apm_skill_drift_component
    fi

    if should_run_apm_audit; then
        run_apm_audit_component
    fi

    save_fingerprint

    echo ""
    echo "sync_apm_artifacts: done."
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
