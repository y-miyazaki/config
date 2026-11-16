#!/bin/bash
#######################################
# Description:
#   Stop hook: run the Bats suites that correspond to shell files changed in git.
#   Blocks the stop with the failing output when a suite fails.
#
# Usage:
#   Called by Claude Code as a Stop hook (configured in .claude/settings.local.json);
#   receives the hook event JSON on stdin. Also runnable by hand from the repository.
#
# Design Rules:
#   - Repository-specific: not distributed through apm.
#   - Changed files come from git (working tree, index, untracked); a changed *.bats runs itself.
#   - A changed *.sh/*.bash maps to every suite whose header line is "# Tests for <repo-relative path>"
#     (no fixed test directory layout is assumed).
#   - Exit 0 silently when bats/jq is missing, nothing changed, or no suite maps.
#   - Never re-block while stop_hook_active is true (avoids endless stop loops).
#   - Runs suites in parallel when parallel or rush is installed (BATS_JOBS overrides, 1 = serial).
#
# Output:
#   Claude Code Stop JSON {"decision":"block","reason":...} on failure; nothing otherwise.
#######################################

set -euo pipefail

# Secure defaults
umask 027
export LC_ALL=C.UTF-8

# Capture stdin (hook event JSON); must be read before any other stdin use.
HOOK_STDIN_DATA=""
if [[ ! -t 0 ]]; then
    HOOK_STDIN_DATA=$(cat)
fi

BATS_SUITE_ROOT="${BATS_SUITE_ROOT:-test/bats}"

#######################################
# get_changed_files: Collect changed shell-related files from git
#
# Globals:
#   None
#
# Arguments:
#   None
#
# Outputs:
#   Newline-separated unique existing file paths to stdout
#
# Returns:
#   0
#######################################
function get_changed_files {
    local -a globs=('*.sh' '*.bash' '*.bats')
    local path
    while IFS= read -r path; do
        [[ -z ${path} ]] && continue
        [[ -f ${path} ]] || continue
        printf '%s\n' "${path}"
    done < <(
        {
            git diff --name-only --diff-filter=ACMR HEAD -- "${globs[@]}" 2> /dev/null || true
            git ls-files --others --exclude-standard -- "${globs[@]}" 2> /dev/null || true
        } | awk 'NF' | sort -u
    )
}

#######################################
# report_failure: Block the Claude Code stop with a reason
#
# Globals:
#   None
#
# Arguments:
#   $1 - Reason text
#
# Outputs:
#   Stop-hook JSON to stdout
#
# Returns:
#   Exits 0
#######################################
function report_failure {
    printf '%s' "$1" | jq -Rs '{decision: "block", reason: .}'
    exit 0
}

#######################################
# resolve_runner_bin: Resolve a parallel runner to a binary bats can launch
#
# Description:
#   A mise shim re-resolves PATH when run, which drops the bats libexec directory and
#   makes bats-exec-file unfindable. Return the real binary path for shims, else the name.
#
# Globals:
#   None
#
# Arguments:
#   $1 - Runner name (parallel or rush)
#
# Outputs:
#   Runner name or real binary path to stdout
#
# Returns:
#   0
#######################################
function resolve_runner_bin {
    local name="$1" found real
    found=$(command -v "$name" 2> /dev/null || true)
    if [[ $found == */shims/* ]] && command -v mise > /dev/null 2>&1; then
        real=$(mise which "$name" 2> /dev/null || true)
        if [[ -n $real && -x $real ]]; then
            printf '%s\n' "$real"
            return 0
        fi
    fi
    printf '%s\n' "$name"
}

#######################################
# resolve_bats_suites: Map changed files to Bats suites
#
# Globals:
#   BATS_SUITE_ROOT - Directory searched for suites (default test/bats)
#
# Arguments:
#   $@ - Changed file paths
#
# Outputs:
#   Unique suite paths to stdout, one per line
#
# Returns:
#   0
#######################################
function resolve_bats_suites {
    local path escaped
    {
        for path in "$@"; do
            if [[ $path == *.bats ]]; then
                printf '%s\n' "$path"
                continue
            fi
            [[ -d $BATS_SUITE_ROOT ]] || continue
            escaped=$(printf '%s' "$path" | sed 's/[][\.*^$+?(){}|]/\\&/g')
            grep -rlE --include='*.bats' "^# Tests for ${escaped}([[:space:]]|$)" "$BATS_SUITE_ROOT" 2> /dev/null || true
        done
    } | sort -u
}

#######################################
# main: Entry point
#
# Globals:
#   HOOK_STDIN_DATA - Hook event JSON
#   BATS_JOBS - Optional parallel job count
#
# Arguments:
#   None
#
# Outputs:
#   Stop-hook JSON on failure
#
# Returns:
#   0 on success or skip
#######################################
function main {
    # Inside a bats run (parallel mode) the bats libexec dir is first on PATH and holds an inner
    # "bats" script that is not the CLI entry point; drop it so `bats` resolves to bin/bats.
    PATH=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v '/libexec/bats-core$' | paste -sd: -)
    command -v jq > /dev/null 2>&1 || exit 0
    command -v bats > /dev/null 2>&1 || exit 0

    if [[ -n $HOOK_STDIN_DATA ]] && [[ $(printf '%s' "$HOOK_STDIN_DATA" | jq -r '.stop_hook_active // false' 2> /dev/null) == "true" ]]; then
        exit 0
    fi

    local root
    root=$(git rev-parse --show-toplevel 2> /dev/null) || exit 0
    cd "$root" || exit 0

    local -a files=()
    mapfile -t files < <(get_changed_files)
    [[ ${#files[@]} -gt 0 ]] || exit 0

    local -a suites=()
    mapfile -t suites < <(resolve_bats_suites "${files[@]}")
    [[ ${#suites[@]} -gt 0 ]] || exit 0

    local -a opts=()
    local jobs="${BATS_JOBS:-$(nproc 2> /dev/null || echo 1)}"
    local runner=""
    if [[ $jobs -gt 1 ]]; then
        if command -v parallel > /dev/null 2>&1; then
            runner="parallel"
        elif command -v rush > /dev/null 2>&1; then
            runner="rush"
        fi
    fi
    if [[ -n $runner ]]; then
        opts+=(--jobs "$jobs" --parallel-binary-name "$(resolve_runner_bin "$runner")" --no-parallelize-within-files)
    fi

    local output
    if ! output=$(bats ${opts[@]+"${opts[@]}"} "${suites[@]}" 2>&1); then
        report_failure "bats failed for suites mapped from changed files (${suites[*]}):
$(printf '%s\n' "$output" | tail -n 80)"
    fi
}

# Only call main function if script is executed directly, not sourced
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
