#!/bin/bash
#######################################
# Description: Detect code changes and identify candidate documentation files for loop-docs-triage
#
# Usage: ./detect_changes.sh [--scope staged|all|range] [--since <ref>]
#   --scope    Change detection scope (default: range for loop-detect)
#              staged: git diff --cached only
#              all: git diff HEAD + untracked files
#              range: git diff <ref>..HEAD (requires --since)
#   --since    Git ref for range scope (commit SHA from loop state)
#
# Output:
# - JSON object with changed_files, deleted_files, renamed_files, affected_docs, commit_range, skip
#
# Design Rules:
# - Collect changed files with diff-filter for accurate rename/delete detection
# - Output facts only; Skill builds semantic findings[]
# - Candidate doc paths: caller env DOCS_TRIAGE_DOC_GLOBS (comma-separated globs);
#   optional DOCS_TRIAGE_EXTRA_FILES (comma-separated non-markdown doc config paths)
# - When DOCS_TRIAGE_DOC_GLOBS is unset, discover all *.md excluding generated/hidden paths
# - Output structured JSON via shared lib/json.sh
# - Exit 0 always (errors reported in JSON status field)
# - Source shared helpers from scripts/lib/all.sh (synced via scripts/ai/sync_skill_lib.sh)
#
# Dependencies:
# - bash (POSIX bash, /bin/bash)
# - git
#
# Optional environment:
#   DOCS_TRIAGE_DOC_GLOBS      Comma-separated glob patterns for candidate doc discovery
#   DOCS_TRIAGE_EXTRA_FILES    Comma-separated non-markdown documentation config paths
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
# Usage:
#   show_usage
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
# append_docs_from_extra_files: Add configured non-markdown documentation files
#
# Append paths from DOCS_TRIAGE_EXTRA_FILES when each file exists.
#
# Arguments:
#   None
#
# Global Variables:
#   AFFECTED_DOCS - Output array of candidate document paths
#   DOCS_TRIAGE_EXTRA_FILES - Comma-separated repository-relative paths (caller env)
#
# Returns:
#   None
#
# Usage:
#   append_docs_from_extra_files
#
#######################################
function append_docs_from_extra_files {
    local -a extras=()
    local extra

    [[ -z ${DOCS_TRIAGE_EXTRA_FILES:-} ]] && return 0

    IFS=',' read -ra extras <<< "${DOCS_TRIAGE_EXTRA_FILES}"
    for extra in "${extras[@]}"; do
        append_unique_doc "$(trim_whitespace "${extra}")"
    done
}

#######################################
# append_docs_from_find: Discover markdown files with standard prune paths
#
# Find repository markdown files excluding generated and hidden directories.
#
# Arguments:
#   None
#
# Global Variables:
#   AFFECTED_DOCS - Output array of candidate document paths
#
# Returns:
#   None
#
# Usage:
#   append_docs_from_find
#
#######################################
function append_docs_from_find {
    local doc_file

    while IFS= read -r doc_file; do
        append_unique_doc "${doc_file}"
    done < <(find . \
        \( -path './.git' -o \
        -path '*/.*' -o \
        -path './.agents' -o \
        -path './.cursor' -o \
        -path './.claude' -o \
        -path './.kiro' -o \
        -path './.vscode' -o \
        -path './apm_modules' -o \
        -path './node_modules' -o \
        -path './dist' -o \
        -path './build' -o \
        -path './bin' \) -prune -o \
        -name '*.md' -type f -print 2> /dev/null | sed 's|^\./||')
}

#######################################
# append_docs_from_globs: Expand comma-separated globs into AFFECTED_DOCS
#
# Resolve caller-configured glob patterns into existing documentation paths.
#
# Arguments:
#   $1 - Comma-separated glob patterns (repository-relative)
#
# Global Variables:
#   AFFECTED_DOCS - Output array of candidate document paths
#
# Returns:
#   None
#
# Usage:
#   append_docs_from_globs "${DOCS_TRIAGE_DOC_GLOBS}"
#
#######################################
function append_docs_from_globs {
    local globs_csv="$1"
    local -a globs=()
    local glob pattern match

    IFS=',' read -ra globs <<< "${globs_csv}"
    shopt -s globstar nullglob
    for glob in "${globs[@]}"; do
        pattern="$(trim_whitespace "${glob}")"
        [[ -z ${pattern} ]] && continue
        for match in ${pattern}; do
            match="${match#./}"
            append_unique_doc "${match}"
        done
    done
    shopt -u globstar nullglob
}

#######################################
# append_unique_doc: Add a documentation path once to AFFECTED_DOCS
#
# Append a repository-relative path when the file exists and is not duplicated.
#
# Arguments:
#   $1 - Repository-relative file path
#
# Global Variables:
#   AFFECTED_DOCS - Output array of candidate document paths
#
# Returns:
#   None
#
# Usage:
#   append_unique_doc "docs/guide/overview.md"
#
#######################################
function append_unique_doc {
    local path="$1"
    local existing

    [[ -z ${path} ]] && return 0
    [[ ! -f ${path} ]] && return 0

    for existing in "${AFFECTED_DOCS[@]}"; do
        [[ ${existing} == "${path}" ]] && return 0
    done
    AFFECTED_DOCS+=("${path}")
}

#######################################
# collect_affected_docs: Collect candidate documentation files
#
# When non-markdown changes or markdown deletes/renames exist, populate
# AFFECTED_DOCS from DOCS_TRIAGE_DOC_GLOBS or a generic markdown scan.
#
# Arguments:
#   None
#
# Global Variables:
#   CHANGED_FILES - Source of change detection
#   DELETED_FILES - Deleted files
#   RENAMED_FILES - Renamed files
#   AFFECTED_DOCS - Output array of candidate document paths
#   DOCS_TRIAGE_DOC_GLOBS - Comma-separated glob patterns (caller env)
#
# Returns:
#   None
#
# Usage:
#   collect_affected_docs
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
            *.md) ;; # markdown-only changes checked below
            *)
                has_relevant_change="true"
                break
                ;;
        esac
    done

    # Markdown renames or deletions can break cross-references
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

    if [[ -n ${DOCS_TRIAGE_DOC_GLOBS:-} ]]; then
        append_docs_from_globs "${DOCS_TRIAGE_DOC_GLOBS}"
    else
        append_docs_from_find
    fi
    append_docs_from_extra_files
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
# Usage:
#   collect_changes
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

    # Include untracked files only for 'all' scope (not range)
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
#   SCOPE - Detection scope
#   SINCE_REF - Range start ref
#   COMMIT_RANGE - Active diff range label
#   CHANGED_FILES - Array of changed file paths
#   DELETED_FILES - Array of deleted file paths
#   RENAMED_FILES - Array of old->new rename pairs
#   AFFECTED_DOCS - Array of candidate document paths
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
# trim_whitespace: Remove leading and trailing whitespace from a string
#
# Arguments:
#   $1 - Input string
#
# Global Variables:
#   None
#
# Returns:
#   Trimmed string on stdout
#
# Usage:
#   value="$(trim_whitespace "${input}")"
#
#######################################
function trim_whitespace {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "${value}"
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
    collect_changes
    collect_affected_docs
    output_json
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
