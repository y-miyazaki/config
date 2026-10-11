#!/bin/bash
#######################################
# Description: Record test files changed by a test-gap run into the run ledger
#
# Usage: ./update_test_gap_ledger.sh
#   Intended as caller domain_persistence_script (loop-finalize). Inputs come from the environment.
#
# Output:
# - None on success (ledger file updated in place)
# - Warnings on stderr when prerequisites are missing or inputs are unusable
#
# Design Rules:
# - Always exit 0 so a ledger problem never blocks finalize (same policy as ci-sweeper update_run_ledger.sh)
# - Record only files in git diff <base>...<EXECUTE_BRANCH>; the maker does not have to cooperate
# - Skip no-action, error, escalated, and unknown outcomes
# - Prune entries older than the retention window
# - Write via mktemp + mv; keep unrelated entries intact
# - Source shared helpers from scripts/lib/all.sh (synced via scripts/self/apm/sync_skill_lib.sh)
#
# Dependencies:
# - bash (POSIX bash, /bin/bash)
# - git
# - jq
#
# Optional environment:
#   OUTCOME                  pr-created | rejected | watch | no-action | no-changes | error | escalated
#   VERDICT                  APPROVE | REJECT (used when OUTCOME is unset)
#   EXECUTE_BRANCH           Agent branch holding the test changes (required to record anything)
#   TEST_GAP_BASE_BRANCH     Base branch for the diff (default: main)
#   TEST_GAP_LEDGER_FILE     Ledger path, repository-relative (default: .loop/state-test-gap-ledger.json)
#   TEST_GAP_RETENTION_DAYS  Days an entry is kept (default: 30)
#   GITHUB_RUN_ID            Recorded as last_loop_run_id
#######################################

# Error handling: exit on error, unset variable, or failed pipeline
set -euo pipefail

# Secure defaults
umask 027
export LC_ALL=C.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load all-in-one library
# shellcheck source=./lib/all.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/all.sh"

#######################################
# Global variables
#######################################
OUTCOME="${OUTCOME-}"
LEDGER_FILE="${TEST_GAP_LEDGER_FILE:-.loop/state-test-gap-ledger.json}"
BASE_BRANCH="${TEST_GAP_BASE_BRANCH:-main}"
RETENTION_DAYS="${TEST_GAP_RETENTION_DAYS:-30}"

#######################################
# changed_files: List files changed on the execute branch relative to the base
#
# Globals:
#   BASE_BRANCH, EXECUTE_BRANCH - Read
#
# Arguments:
#   None
#
# Outputs:
#   One repository-relative path per line on stdout
#
# Returns:
#   0 on success; 1 when the branch cannot be resolved or git diff fails
#
#######################################
function changed_files {
    local base="${BASE_BRANCH}"
    local head="${EXECUTE_BRANCH:-}"

    [[ -z ${head} ]] && return 1
    if git rev-parse --verify --quiet "origin/${base}^{commit}" > /dev/null 2>&1; then
        base="origin/${base}"
    fi
    git rev-parse --verify --quiet "${base}^{commit}" > /dev/null 2>&1 || return 1
    if git rev-parse --verify --quiet "origin/${head}^{commit}" > /dev/null 2>&1; then
        head="origin/${head}"
    fi
    git rev-parse --verify --quiet "${head}^{commit}" > /dev/null 2>&1 || return 1
    git diff --name-only "${base}...${head}" 2> /dev/null
}

#######################################
# resolve_outcome: Normalize OUTCOME (empty means skip)
#
# Globals:
#   OUTCOME, VERDICT - Read; OUTCOME is updated in place
#
# Arguments:
#   None
#
# Outputs:
#   Warning on stderr for unknown outcomes
#
# Returns:
#   0
#
#######################################
function resolve_outcome {
    if [[ -z ${OUTCOME} ]]; then
        case "${VERDICT:-}" in
            APPROVE) OUTCOME="pr-created" ;;
            REJECT) OUTCOME="rejected" ;;
        esac
    fi
    case "${OUTCOME}" in
        pr-created | rejected | watch) ;;
        "" | no-action | no-changes | error | escalated)
            OUTCOME=""
            ;;
        *)
            log "WARN" "Unknown ledger outcome '${OUTCOME}'; skipping ledger update"
            OUTCOME=""
            ;;
    esac
}

#######################################
# validate_ledger_file: Reject empty, absolute, and parent-relative ledger paths
#
# Globals:
#   None
#
# Arguments:
#   $1 - Ledger path
#
# Outputs:
#   Warning on stderr when rejected
#
# Returns:
#   0 when usable; 1 when rejected
#
#######################################
function validate_ledger_file {
    local path="$1"
    local repo_root resolved

    if [[ -z ${path} ]]; then
        log "WARN" "TEST_GAP_LEDGER_FILE must not be empty"
        return 1
    fi
    if [[ ${path} == /* ]]; then
        log "WARN" "TEST_GAP_LEDGER_FILE must be a repository-relative path (got: ${path})"
        return 1
    fi
    repo_root="$(git rev-parse --show-toplevel 2> /dev/null || pwd)"
    resolved="$(realpath -m "${repo_root}/${path}")"
    if [[ ${resolved} != "${repo_root}"/* ]]; then
        log "WARN" "TEST_GAP_LEDGER_FILE must stay under the repository root (got: ${path})"
        return 1
    fi
}

#######################################
# main: Entry point
#
# Globals:
#   OUTCOME, LEDGER_FILE, RETENTION_DAYS - Read
#
# Arguments:
#   None
#
# Outputs:
#   Warnings on stderr
#
# Returns:
#   0 always
#
#######################################
function main {
    local files now cutoff tmp existing

    if ! command -v jq > /dev/null 2>&1; then
        log "WARN" "jq is required; skipping ledger update"
        return 0
    fi

    resolve_outcome
    if [[ -z ${OUTCOME} ]]; then
        return 0
    fi

    validate_ledger_file "${LEDGER_FILE}" || return 0

    if ! files="$(changed_files)"; then
        log "WARN" "cannot resolve execute branch '${EXECUTE_BRANCH:-}' against '${BASE_BRANCH}'; skipping ledger update"
        return 0
    fi
    if [[ -z ${files} ]]; then
        return 0
    fi

    existing='{"entries":{}}'
    if [[ -f ${LEDGER_FILE} ]]; then
        if jq -e '.entries | type == "object"' "${LEDGER_FILE}" > /dev/null 2>&1; then
            existing="$(cat "${LEDGER_FILE}")"
        else
            log "WARN" "ledger file is corrupt; starting from an empty ledger: ${LEDGER_FILE}"
        fi
    fi

    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    cutoff="$(date -u -d "${RETENTION_DAYS} days ago" +%Y-%m-%dT%H:%M:%SZ)"
    mkdir -p "$(dirname "${LEDGER_FILE}")"
    tmp="$(mktemp)"
    # shellcheck disable=SC2016  # jq filter; $vars are bound via --arg/--argjson below
    if ! printf '%s\n' "${files}" | jq -R -s -c \
        --argjson ledger "${existing}" \
        --arg now "${now}" \
        --arg cutoff "${cutoff}" \
        --arg outcome "${OUTCOME}" \
        --arg run_id "${GITHUB_RUN_ID:-}" '
        (split("\n") | map(select(length > 0))) as $paths
        | reduce $paths[] as $p ($ledger;
            .entries[$p] = {
              attempts: ((.entries[$p].attempts // 0) + 1),
              last_loop_run_id: $run_id,
              outcome: $outcome,
              processed_at: $now
            })
        | .entries |= with_entries(select((.value.processed_at // "") >= $cutoff))' > "${tmp}"; then
        log "WARN" "ledger update failed; leaving the ledger unchanged"
        rm -f "${tmp}"
        return 0
    fi
    mv "${tmp}" "${LEDGER_FILE}"
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
