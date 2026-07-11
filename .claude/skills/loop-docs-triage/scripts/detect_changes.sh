#!/bin/bash
#######################################
# Description: Detect code changes and identify candidate documentation files for loop-docs-triage
#
# Usage: ./detect_changes.sh [--scope staged|all|range] [--since <ref>]
#   --scope    Change detection scope (default: range for loop-detect)
#              range: git diff <ref>..HEAD (requires --since)
#   --since    Git ref for range scope (commit SHA from loop state)
#
# Output:
# - JSON object with changed_files, deleted_files, renamed_files, affected_docs, commit_range, skip
#
# Design Rules:
# - Collect changed files with diff-filter for accurate rename/delete detection
# - Output facts only; Skill builds semantic findings[]
# - Output structured JSON via shared lib/json.sh
# - Exit 0 always (errors reported in JSON status field)
# - Source shared helpers from scripts/lib/all.sh (synced via scripts/ai/sync_skill_lib.sh)
#
# Dependencies:
# - bash (POSIX bash, /bin/bash)
# - git
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
COMMIT_RANGE=""

declare -a CHANGED_FILES=()
declare -a RENAMED_FILES=()
declare -a DELETED_FILES=()
declare -a AFFECTED_DOCS=()

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
#######################################
function show_usage {
    cat << 'EOF'
Usage: detect_changes.sh [--scope staged|all|range] [--since <ref>]

Description:
    Detect code changes and identify candidate documentation files for loop-docs-triage.

Options:
    --scope    Change detection scope (default: range)
               staged: git diff --cached only
               all: git diff HEAD + untracked files
               range: git diff <ref>..HEAD (requires --since)
    --since    Git ref for range scope (commit SHA from loop state)

Examples:
    ./detect_changes.sh --scope range --since abc1234
    ./detect_changes.sh --scope all
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
#   None
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
                    json_object_start
                    json_field_string "status" "error" ","
                    json_field_string "message" "--scope requires a value" ""
                    json_object_end
                    exit 0
                fi
                SCOPE="$2"
                shift 2
                ;;
            --since)
                if [[ $# -lt 2 ]]; then
                    json_object_start
                    json_field_string "status" "error" ","
                    json_field_string "message" "--since requires a value" ""
                    json_object_end
                    exit 0
                fi
                SINCE_REF="$2"
                shift 2
                ;;
            *)
                json_object_start
                json_field_string "status" "error" ","
                json_field_string "message" "Unknown argument: $1" ""
                json_object_end
                exit 0
                ;;
        esac
    done

    if [[ ${SCOPE} != "staged" && ${SCOPE} != "all" && ${SCOPE} != "range" ]]; then
        json_object_start
        json_field_string "status" "error" ","
        json_field_string "message" "--scope must be staged, all, or range" ""
        json_object_end
        exit 0
    fi

    if [[ ${SCOPE} == "range" && -z ${SINCE_REF} ]]; then
        json_object_start
        json_field_string "status" "error" ","
        json_field_string "message" "--scope range requires --since <ref>" ""
        json_object_end
        exit 0
    fi
}

#######################################
# collect_affected_docs: Collect candidate documentation files
#
# Arguments:
#   None
#
# Global Variables:
#   CHANGED_FILES - Source of change detection
#   DELETED_FILES - Deleted files
#   RENAMED_FILES - Renamed files
#   AFFECTED_DOCS - Output array of candidate document paths
#
# Returns:
#   None
#
#######################################
function collect_affected_docs {
    local has_relevant_change="false"
    local all_files=("${CHANGED_FILES[@]}" "${DELETED_FILES[@]}")

    local rename
    for rename in "${RENAMED_FILES[@]}"; do
        all_files+=("${rename%%->*}")
        all_files+=("${rename##*->}")
    done

    local file
    for file in "${all_files[@]}"; do
        [[ -z ${file} ]] && continue
        case "${file}" in
            *.md) ;;
            *)
                has_relevant_change="true"
                break
                ;;
        esac
    done

    if [[ ${has_relevant_change} == "false" ]]; then
        if [[ ${#DELETED_FILES[@]} -gt 0 || ${#RENAMED_FILES[@]} -gt 0 ]]; then
            local item
            for item in "${DELETED_FILES[@]}"; do
                [[ ${item} == *.md ]] && has_relevant_change="true" && break
            done
            if [[ ${has_relevant_change} == "false" ]]; then
                for item in "${RENAMED_FILES[@]}"; do
                    [[ ${item} == *.md* ]] && has_relevant_change="true" && break
                done
            fi
        fi
    fi

    if [[ ${has_relevant_change} == "false" ]]; then
        return
    fi

    local doc_file
    while IFS= read -r doc_file; do
        AFFECTED_DOCS+=("${doc_file}")
    done < <(find . -maxdepth 1 -name '*.md' -type f 2> /dev/null | sed 's|^\./||')
    while IFS= read -r doc_file; do
        AFFECTED_DOCS+=("${doc_file}")
    done < <(find docs -name '*.md' -type f 2> /dev/null || true)
    while IFS= read -r doc_file; do
        AFFECTED_DOCS+=("${doc_file}")
    done < <(find . -mindepth 2 \
        -path './docs' -prune -o \
        -path '*/.*' -prune -o \
        -path './.agents' -prune -o \
        -path './.cursor' -prune -o \
        -path './.claude' -prune -o \
        -path './.kiro' -prune -o \
        -path './.vscode' -prune -o \
        -path './apm_modules' -prune -o \
        -name 'README.md' -type f -print 2> /dev/null | sed 's|^\./||' || true)
    if [[ -f "mkdocs.yml" ]]; then
        AFFECTED_DOCS+=("mkdocs.yml")
    fi
}

#######################################
# collect_changes: Collect changed files from git
#
# Arguments:
#   None
#
# Global Variables:
#   SCOPE - Detection scope
#   SINCE_REF - Range start ref
#   COMMIT_RANGE - Populated for range scope
#   CHANGED_FILES - Array of changed file paths
#   RENAMED_FILES - Array of old->new rename pairs
#   DELETED_FILES - Array of deleted file paths
#
# Returns:
#   None
#
#######################################
function collect_changes {
    if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        json_object_start
        json_field_string "status" "error" ","
        json_field_string "message" "Not a git repository" ""
        json_object_end
        exit 0
    fi

    local diff_ref

    if [[ ${SCOPE} == "range" ]]; then
        diff_ref="${SINCE_REF}..HEAD"
        COMMIT_RANGE="${diff_ref}"
    else
        local use_head="false"

        if [[ ${SCOPE} == "staged" ]]; then
            local staged_count
            staged_count="$(git diff --cached --name-only 2> /dev/null | wc -l)"
            if [[ ${staged_count} -eq 0 ]]; then
                use_head="true"
            fi
        else
            use_head="true"
        fi

        diff_ref="--cached"
        if [[ ${use_head} == "true" ]]; then
            diff_ref="HEAD"
        fi
        COMMIT_RANGE="${diff_ref}"
    fi

    mapfile -t CHANGED_FILES < <(git diff "${diff_ref}" --name-only --diff-filter=ACMR 2> /dev/null || true)
    mapfile -t DELETED_FILES < <(git diff "${diff_ref}" --name-only --diff-filter=D 2> /dev/null || true)

    local rename_lines
    mapfile -t rename_lines < <(git diff "${diff_ref}" -M --diff-filter=R --name-status 2> /dev/null || true)
    local line
    for line in "${rename_lines[@]}"; do
        [[ -z ${line} ]] && continue
        local old new
        old="$(echo "${line}" | cut -f2)"
        new="$(echo "${line}" | cut -f3)"
        if [[ -n ${old} && -n ${new} ]]; then
            RENAMED_FILES+=("${old}->${new}")
        fi
    done

    if [[ ${SCOPE} == "all" ]]; then
        local untracked
        mapfile -t untracked < <(git ls-files --others --exclude-standard 2> /dev/null || true)
        CHANGED_FILES+=("${untracked[@]}")
    fi
}

#######################################
# output_json: Print structured JSON result using lib/json.sh helpers
#
# Arguments:
#   None
#
# Global Variables:
#   SCOPE, SINCE_REF, COMMIT_RANGE, CHANGED_FILES, DELETED_FILES, RENAMED_FILES, AFFECTED_DOCS
#
# Returns:
#   None
#
#######################################
function output_json {
    local skip="false"
    if [[ ${#AFFECTED_DOCS[@]} -eq 0 ]]; then
        skip="true"
    fi

    local changed_arr deleted_arr renamed_arr affected_arr
    changed_arr="$(json_string_array "${CHANGED_FILES[@]}")"
    deleted_arr="$(json_string_array "${DELETED_FILES[@]}")"
    renamed_arr="$(json_string_array "${RENAMED_FILES[@]}")"
    affected_arr="$(json_string_array "${AFFECTED_DOCS[@]}")"

    json_object_start
    json_field_string "status" "ok" ","
    json_field_string "scope" "${SCOPE}" ","
    json_field_string "since" "${SINCE_REF}" ","
    json_field_string "commit_range" "${COMMIT_RANGE}" ","
    json_field_bool "skip" "${skip}" ","
    json_field_array "changed_files" "${changed_arr}" ","
    json_field_array "deleted_files" "${deleted_arr}" ","
    json_field_array "renamed_files" "${renamed_arr}" ","
    json_field_array "affected_docs" "${affected_arr}" ""
    json_object_end
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
#######################################
function main {
    parse_arguments "$@"
    collect_changes
    collect_affected_docs
    output_json
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
