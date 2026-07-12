#!/bin/bash
#######################################
# Description:
#   Detect unreleased changelog-worthy commits for loop-changelog.
#
# Usage: ./detect_changelog_commits.sh [--scope all|range] [--since <ref>]
#   --scope    Change detection scope (default: range for loop-detect)
#              all: last CHANGELOG_MAX_COMMITS commits on HEAD (local debugging)
#              range: git log <ref>..HEAD (requires --since; production path)
#   --since    Git ref for range scope (commit SHA from loop state)
#
# Output:
# - JSON object with changelog_file, changelog_exists, commit_range, commits[], repository, repository_url, compare_url, skip
#
# Design Rules:
# - Include conventional commits (feat:, fix:, chore:, …)
# - Include other explicit prefixed commits (renovate(scope):, chore(deps):, …)
# - Skip subjects without a clear "prefix: description" shape
# - Output structured JSON via shared lib/json.sh
# - Exit 0 always (errors reported in JSON status field)
# - Source shared helpers from scripts/lib/all.sh (synced via scripts/ai/sync_skill_lib.sh)
#
# Dependencies:
# - bash (POSIX bash, /bin/bash)
# - git
#
# Optional environment:
#   CHANGELOG_FILE            Target changelog path (default: CHANGELOG.md)
#   CHANGELOG_MAX_COMMITS     Max commits for --scope all (default: 100)
#   CHANGELOG_MERGE_COMMITS   Include merge commits when "true" (default: false)
#   CHANGELOG_REPOSITORY      owner/repo override (optional)
#   CHANGELOG_REPOSITORY_URL  Repository web base URL override (optional, no trailing slash)
#   GITHUB_SERVER_URL         Used with GITHUB_REPOSITORY in Actions (auto)
#   GITHUB_REPOSITORY         Used with GITHUB_SERVER_URL in Actions (auto)
#######################################

set -euo pipefail

umask 027
export LC_ALL=C.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_DIR

# shellcheck source=lib/all.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/all.sh"

#######################################
# Global variables
#######################################
SCOPE="range"
SINCE_REF=""
CHANGELOG_FILE="${CHANGELOG_FILE:-CHANGELOG.md}"
CHANGELOG_MAX_COMMITS="${CHANGELOG_MAX_COMMITS:-100}"
CHANGELOG_MERGE_COMMITS="${CHANGELOG_MERGE_COMMITS:-false}"
REPOSITORY="${CHANGELOG_REPOSITORY:-}"
REPOSITORY_URL="${CHANGELOG_REPOSITORY_URL:-}"
COMPARE_URL=""
HEAD_SHA=""
COMMIT_RANGE=""
CHANGELOG_EXISTS="false"
CONVENTIONAL_TYPES="feat fix docs style refactor perf test build ci chore revert"

declare -a COMMITS_JSON=()

#######################################
# show_usage: Display script usage information
#
# Arguments:
#   None
#
# Global Variables:
#   None
#
# Returns:
#   Exits with code 0
#
# Usage:
#   show_usage
#
#######################################
function show_usage {
    cat << 'EOF'
Usage: detect_changelog_commits.sh [--scope all|range] [--since <ref>]

Description:
    Detect unreleased changelog-worthy commits for loop-changelog.

Options:
    --scope    Change detection scope (default: range)
               all: last CHANGELOG_MAX_COMMITS commits on HEAD (debugging)
               range: git log <ref>..HEAD (requires --since)
    --since    Git ref for range scope (commit SHA from loop state)

Examples:
    ./detect_changelog_commits.sh --scope range --since abc1234
    ./detect_changelog_commits.sh --scope all
EOF
    exit 0
}

#######################################
# parse_arguments: Parse command line arguments
#
# Arguments:
#   $@ - Command line arguments
#
# Global Variables:
#   SCOPE - Detection scope
#   SINCE_REF - Git ref for range scope
#
# Returns:
#   None (calls output_error on invalid input)
#
# Usage:
#   parse_arguments "$@"
#
#######################################
function parse_arguments {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help)
                show_usage
                ;;
            --scope)
                if [[ $# -lt 2 ]]; then
                    output_error "--scope requires a value"
                fi
                SCOPE="$2"
                shift 2
                ;;
            --since)
                if [[ $# -lt 2 ]]; then
                    output_error "--since requires a value"
                fi
                SINCE_REF="$2"
                shift 2
                ;;
            *)
                output_error "Unknown argument: $1"
                ;;
        esac
    done

    if [[ ${SCOPE} != "all" && ${SCOPE} != "range" ]]; then
        output_error "--scope must be all or range"
    fi

    if [[ ${SCOPE} == "range" && -z ${SINCE_REF} ]]; then
        output_error "--scope range requires --since <ref>"
    fi
}

#######################################
# collect_commits: Collect changelog-worthy commits from git log
#
# Description:
#   Resolve the active git range, scan commit subjects, and populate COMMITS_JSON.
#
# Arguments:
#   None
#
# Global Variables:
#   SCOPE - Detection scope
#   SINCE_REF - Range start ref
#   COMMIT_RANGE - Active diff range label
#   CHANGELOG_FILE - Target changelog path
#   CHANGELOG_EXISTS - Whether CHANGELOG_FILE exists
#   CHANGELOG_MERGE_COMMITS - Merge commit inclusion flag
#   COMMITS_JSON - Output array of commit JSON objects
#
# Returns:
#   None (calls output_error on fatal errors)
#
# Usage:
#   collect_commits
#
#######################################
function collect_commits {
    local diff_ref
    local log_args=()
    local sha subject body commit_type scope breaking rest

    if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        output_error "Not a git repository"
    fi

    detect_changelog_exists

    if [[ ${CHANGELOG_MERGE_COMMITS} != "true" ]]; then
        log_args+=(--no-merges)
    fi

    if [[ ${SCOPE} == "range" ]]; then
        diff_ref="${SINCE_REF}..HEAD"
        COMMIT_RANGE="${diff_ref}"
    else
        diff_ref="HEAD"
        COMMIT_RANGE="HEAD~${CHANGELOG_MAX_COMMITS}..HEAD"
        log_args+=(-n "${CHANGELOG_MAX_COMMITS}")
    fi

    while IFS=$'\t' read -r sha subject body; do
        [[ -z ${sha} ]] && continue
        if ! parse_commit_subject "${subject}" commit_type scope breaking rest; then
            continue
        fi
        if is_loop_maintenance_commit "${commit_type}" "${scope}" "${rest}"; then
            continue
        fi
        if grep -qi 'BREAKING CHANGE' <<< "${body}"; then
            breaking="true"
        fi

        COMMITS_JSON+=("$(commit_object_json "${sha}" "${commit_type}" "${scope}" "${breaking}" "${rest}")")
    done < <(git log "${log_args[@]}" "${diff_ref}" --pretty=format:'%H%x09%s%x09%b%n' 2> /dev/null || true)

    HEAD_SHA="$(git rev-parse HEAD 2> /dev/null || true)"
}

# get_repository_from_git: Resolve owner/repo from origin remote URL
#
# Returns:
#   0 with owner/repo on stdout when detected, 1 otherwise
#
function get_repository_from_git {
    local remote_url

    if ! git remote get-url origin &> /dev/null; then
        return 1
    fi

    remote_url="$(git remote get-url origin)"
    if [[ ${remote_url} =~ github\.com[:/]([^/]+)/(.+?)(\.git)?$ ]]; then
        printf '%s/%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]%.git}"
        return 0
    fi

    return 1
}

# resolve_repository_context: Populate REPOSITORY and REPOSITORY_URL
#
# Description:
#   Prefer CHANGELOG_* overrides, then GitHub Actions env, then git remote.
#
function resolve_repository_context {
    local detected_repo=""

    if [[ -n ${REPOSITORY_URL} ]]; then
        REPOSITORY_URL="${REPOSITORY_URL%/}"
        if [[ -z ${REPOSITORY} ]]; then
            if [[ ${REPOSITORY_URL} =~ github\.com/([^/]+/[^/]+)$ ]]; then
                REPOSITORY="${BASH_REMATCH[1]}"
            fi
        fi
        return 0
    fi

    if [[ -n ${GITHUB_SERVER_URL:-} && -n ${GITHUB_REPOSITORY:-} ]]; then
        REPOSITORY="${GITHUB_REPOSITORY}"
        REPOSITORY_URL="${GITHUB_SERVER_URL%/}/${GITHUB_REPOSITORY}"
        return 0
    fi

    if [[ -n ${REPOSITORY} ]]; then
        REPOSITORY_URL="https://github.com/${REPOSITORY}"
        return 0
    fi

    if detected_repo="$(get_repository_from_git)"; then
        REPOSITORY="${detected_repo}"
        REPOSITORY_URL="https://github.com/${REPOSITORY}"
        return 0
    fi

    REPOSITORY=""
    REPOSITORY_URL=""
}

# resolve_compare_url: Set COMPARE_URL from repository context and active range
#
function resolve_compare_url {
    COMPARE_URL=""

    if [[ -z ${REPOSITORY_URL} || -z ${HEAD_SHA} ]]; then
        return 0
    fi

    if [[ ${SCOPE} == "range" && -n ${SINCE_REF} ]]; then
        COMPARE_URL="${REPOSITORY_URL}/compare/${SINCE_REF}...${HEAD_SHA}"
    fi
}

#######################################
# commit_object_json: Build one commit object as JSON
#
# Arguments:
#   $1 - Commit SHA
#   $2 - Commit type prefix
#   $3 - Optional scope
#   $4 - Breaking flag (true|false)
#   $5 - Subject text after the prefix
#
# Global Variables:
#   None
#
# Returns:
#   JSON object on stdout
#
# Usage:
#   commit_object_json "${sha}" "${commit_type}" "${scope}" "${breaking}" "${rest}"
#
#######################################
function commit_object_json {
    local sha="$1"
    local commit_type="$2"
    local scope="$3"
    local breaking="$4"
    local subject="$5"

    cat << EOF
{
  "sha": "$(json_escape "${sha}")",
  "type": "$(json_escape "${commit_type}")",
  "scope": "$(json_escape "${scope}")",
  "breaking": ${breaking},
  "subject": "$(json_escape "${subject}")"
}
EOF
}

#######################################
# commits_array_json: Join commit objects into a JSON array string
#
# Arguments:
#   None
#
# Global Variables:
#   COMMITS_JSON - Source commit objects
#
# Returns:
#   JSON array string on stdout
#
# Usage:
#   commits_array="$(commits_array_json)"
#
#######################################
function commits_array_json {
    local joined="" commit
    if [[ ${#COMMITS_JSON[@]} -eq 0 ]]; then
        printf '%s' "[]"
        return
    fi
    for commit in "${COMMITS_JSON[@]}"; do
        if [[ -n ${joined} ]]; then
            joined+=","
        fi
        joined+="${commit}"
    done
    printf '[%s]' "${joined}"
}

#######################################
# detect_changelog_exists: Set CHANGELOG_EXISTS from CHANGELOG_FILE
#
# Arguments:
#   None
#
# Global Variables:
#   CHANGELOG_FILE - Path to inspect
#   CHANGELOG_EXISTS - Set to true when the file exists
#
# Returns:
#   None
#
# Usage:
#   detect_changelog_exists
#
#######################################
function detect_changelog_exists {
    if [[ -f ${CHANGELOG_FILE} ]]; then
        CHANGELOG_EXISTS="true"
    fi
}

#######################################
# is_conventional_type: Check whether a type is a conventional commit prefix
#
# Arguments:
#   $1 - Commit type prefix
#
# Global Variables:
#   CONVENTIONAL_TYPES - Allowed conventional type list
#
# Returns:
#   0 if conventional, 1 otherwise
#
# Usage:
#   if is_conventional_type "${commit_type}"; then ...
#
#######################################
function is_conventional_type {
    local commit_type="$1"
    local allowed

    for allowed in ${CONVENTIONAL_TYPES}; do
        [[ ${commit_type} == "${allowed}" ]] && return 0
    done
    return 1
}

#######################################
# is_loop_maintenance_commit: Return 0 for loop-changelog automation commits
#
# Description:
#   Skip commits produced by this loop so they are not re-ingested on the next scan.
#
# Arguments:
#   $1 - Parsed commit type
#   $2 - Parsed commit scope
#   $3 - Subject text after the prefix
#
# Global Variables:
#   None
#
# Returns:
#   0 when the commit should be skipped, 1 otherwise
#
# Usage:
#   if is_loop_maintenance_commit "${commit_type}" "${scope}" "${rest}"; then continue; fi
#
#######################################
function is_loop_maintenance_commit {
    local commit_type="$1"
    local scope="$2"
    local subject="$3"

    if [[ ${commit_type} == "chore" && ${scope} == "changelog" ]]; then
        return 0
    fi
    if [[ ${subject} == *"(loop-changelog)"* ]]; then
        return 0
    fi
    return 1
}

#######################################
# output_error: Print structured JSON error and exit
#
# Arguments:
#   $1 - Error message
#
# Global Variables:
#   SCOPE - Detection scope
#   SINCE_REF - Range start ref
#   CHANGELOG_FILE - Target changelog path
#   CHANGELOG_EXISTS - Whether CHANGELOG_FILE exists
#   COMMIT_RANGE - Active diff range label
#
# Returns:
#   Exits with code 0
#
# Usage:
#   output_error "Not a git repository"
#
#######################################
function output_error {
    local message="$1"
    json_object_start
    json_field_string "status" "error" ","
    json_field_string "scope" "${SCOPE}" ","
    json_field_string "since" "${SINCE_REF}" ","
    json_field_string "changelog_file" "${CHANGELOG_FILE}" ","
    json_field_bool "changelog_exists" "${CHANGELOG_EXISTS}" ","
    json_field_string "commit_range" "${COMMIT_RANGE}" ","
    json_field_string "repository" "${REPOSITORY}" ","
    json_field_string "repository_url" "${REPOSITORY_URL}" ","
    json_field_string "compare_url" "${COMPARE_URL}" ","
    json_field_bool "skip" "true" ","
    json_field_array "commits" "[]" ","
    json_field_string "message" "${message}" ""
    json_object_end
    exit 0
}

#######################################
# output_json: Print structured JSON result using lib/json.sh helpers
#
# Arguments:
#   None
#
# Global Variables:
#   SCOPE - Detection scope
#   SINCE_REF - Range start ref
#   CHANGELOG_FILE - Target changelog path
#   CHANGELOG_EXISTS - Whether CHANGELOG_FILE exists
#   COMMIT_RANGE - Active diff range label
#   COMMITS_JSON - Collected commit objects
#
# Returns:
#   None
#
# Usage:
#   output_json
#
#######################################
function output_json {
    local skip="false"
    local commits_array

    if [[ ${#COMMITS_JSON[@]} -eq 0 ]]; then
        skip="true"
    fi

    commits_array="$(commits_array_json)"
    resolve_repository_context
    resolve_compare_url

    json_object_start
    json_field_string "status" "ok" ","
    json_field_string "scope" "${SCOPE}" ","
    json_field_string "since" "${SINCE_REF}" ","
    json_field_string "changelog_file" "${CHANGELOG_FILE}" ","
    json_field_bool "changelog_exists" "${CHANGELOG_EXISTS}" ","
    json_field_string "commit_range" "${COMMIT_RANGE}" ","
    json_field_string "repository" "${REPOSITORY}" ","
    json_field_string "repository_url" "${REPOSITORY_URL}" ","
    json_field_string "compare_url" "${COMPARE_URL}" ","
    json_field_bool "skip" "${skip}" ","
    json_field_array "commits" "${commits_array}" ""
    json_object_end
}

#######################################
# parse_commit_subject: Parse a changelog-worthy commit subject line
#
# Description:
#   Accept conventional commits and other explicit "prefix(scope): subject" lines.
#
# Arguments:
#   $1 - Full commit subject
#   $2 - Nameref for commit type output
#   $3 - Nameref for scope output
#   $4 - Nameref for breaking flag output
#   $5 - Nameref for subject text output
#
# Global Variables:
#   CONVENTIONAL_TYPES - Allowed conventional type list
#
# Returns:
#   0 when parsed, 1 when the subject should be skipped
#
# Usage:
#   parse_commit_subject "${subject}" commit_type scope breaking rest
#
#######################################
function parse_commit_subject {
    local subject="$1"
    # shellcheck disable=SC2034  # nameref output parameters are written by assignment
    local -n out_type="$2"
    local -n out_scope="$3"
    local -n out_breaking="$4"
    local -n out_rest="$5"
    local header

    header="${subject%%: *}"
    out_rest="${subject#*: }"
    [[ -z ${out_rest} || ${out_rest} == "${subject}" ]] && return 1
    [[ ${#out_rest} -lt 3 ]] && return 1

    local breaking="false"
    if [[ ${header} == *'!'* ]]; then
        breaking="true"
        header="${header//'!'/}"
    fi
    # shellcheck disable=SC2034
    out_breaking="${breaking}"

    if [[ ${header} == *"("*")" ]]; then
        out_type="${header%%(*}"
        out_scope="${header#*(}"
        out_scope="${out_scope%%)*}"
    else
        out_type="${header}"
        out_scope=""
    fi

    [[ -z ${out_type} ]] && return 1

    if is_conventional_type "${out_type}"; then
        return 0
    fi

    if [[ ${out_type} =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
        return 0
    fi

    return 1
}

#######################################
# main: Entry point
#
# Arguments:
#   $@ - Command line arguments
#
# Global Variables:
#   None
#
# Returns:
#   0 always
#
# Usage:
#   main "$@"
#
#######################################
function main {
    parse_arguments "$@"
    collect_commits
    output_json
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
