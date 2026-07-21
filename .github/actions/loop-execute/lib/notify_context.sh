#!/bin/bash
#######################################
# Description:
#   Build notify_context_json for loop-notify-pr from worktree diff and detect facts.
#   Environment variables mirror loop-execute composite action inputs.
#
# Usage:
#   BASE_BRANCH=main WORKTREE_PATH=/path/to/wt HAS_CHANGES=true bash lib/notify_context.sh
#
# Design Rules:
#   - fix_summary is platform-owned from detect_result_json failures
#   - changed_files and diff_stat come from origin/BASE...HEAD (excludes .loop/)
#     with HEAD^ fallback when origin/BASE is unavailable
#   - agent_summary is optional; parsed from <!-- loop-agent-summary:v1 --> only
#   - agent_report_overview is optional; parsed from ## Overview until next H2
#   - agent_report_summary is optional; parsed from ## Summary until next H2
#
# Output:
#   Writes notify_context_json multiline output to GITHUB_OUTPUT
#
# Dependencies:
#   - bash, git, jq, openssl
#######################################

# Error handling: exit on error, unset variable, or failed pipeline
set -euo pipefail

# Secure defaults
umask 027
export LC_ALL=C.UTF-8

#######################################
# Global variables
#######################################
BASE_BRANCH="${BASE_BRANCH:-}"
DETECT_RESULT_JSON="${DETECT_RESULT_JSON:-"{}"}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-}"
HAS_CHANGES="${HAS_CHANGES:-false}"
STATUS_DIR="${STATUS_DIR:-}"
WORKTREE_PATH="${WORKTREE_PATH:-}"

#######################################
# build_fix_summary: Template fix summary from detect facts
#
# Globals:
#   None
#
# Arguments:
#   $1 - Detect result JSON
#
# Outputs:
#   Summary string to stdout
#
# Returns:
#   0 on success
#
#######################################
function build_fix_summary {
    local detect_json="$1"
    local job_name workflow_name

    if [[ -z ${detect_json} ]] || ! jq -e . <<< "${detect_json}" > /dev/null 2>&1; then
        printf '%s' "Loop automated fix"
        return 0
    fi

    job_name=$(jq -r '.failures[0].job_name // "CI"' <<< "${detect_json}")
    workflow_name=$(jq -r '.failures[0].workflow_name // .workflow_name // "workflow"' <<< "${detect_json}")
    printf 'Address CI failure in %s (%s)' "${job_name}" "${workflow_name}"
}

#######################################
# extract_agent_section: Extract a ## heading section from agent output
#
# Globals:
#   None
#
# Arguments:
#   $1 - Agent output file path
#   $2 - Section title (e.g. Overview, Summary)
#
# Outputs:
#   Section body to stdout (may be empty)
#
# Returns:
#   0 on success
#
#######################################
function extract_agent_section {
    local output_file="$1"
    local section_title="$2"
    [[ -f ${output_file} ]] || return 0
    awk -v title="${section_title}" '
      $0 ~ "^## " title "[[:space:]]*$" {grab=1; next}
      /^## / {if (grab) exit}
      grab {print}
    ' "${output_file}" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'
}

#######################################
# extract_agent_report_overview: Extract ## Overview section from agent output
#
# Globals:
#   None
#
# Arguments:
#   $1 - Agent output file path
#
# Outputs:
#   Overview section body to stdout (may be empty)
#
# Returns:
#   0 on success
#
#######################################
function extract_agent_report_overview {
    extract_agent_section "$1" "Overview"
}

#######################################
# extract_agent_report_summary: Extract ## Summary section from agent output
#
# Globals:
#   None
#
# Arguments:
#   $1 - Agent output file path
#
# Outputs:
#   Summary section body to stdout (may be empty)
#
# Returns:
#   0 on success
#
#######################################
function extract_agent_report_summary {
    extract_agent_section "$1" "Summary"
}

#######################################
# parse_agent_summary: Extract optional agent summary block
#
# Globals:
#   None
#
# Arguments:
#   $1 - Agent output file path
#
# Outputs:
#   Summary text to stdout (may be empty)
#
# Returns:
#   0 on success
#
#######################################
function parse_agent_summary {
    local output_file="$1"
    local summary=""

    if [[ ! -f ${output_file} ]]; then
        return 0
    fi

    if grep -q '<!-- loop-agent-summary:v1 -->' "${output_file}"; then
        summary=$(awk '/<!-- loop-agent-summary:v1 -->/{found=1; next} found{print}' "${output_file}" \
            | sed '/^```/,$d')
    fi
    printf '%s' "${summary}"
}

#######################################
# redact_sensitive_text: Redact common secret patterns
#
# Globals:
#   None
#
# Arguments:
#   $1 - Input text
#
# Outputs:
#   Redacted text to stdout
#
# Returns:
#   0 on success
#
#######################################
function redact_sensitive_text {
    local text="$1"
    # Keep patterns aligned with loop-ci-sweeper sanitize_log_excerpt.
    text=$(sed -E 's/gh[pousr]_[A-Za-z0-9_]{20,}/[REDACTED]/g' <<< "${text}")
    text=$(sed -E 's/AKIA[0-9A-Z]{16}/[REDACTED]/g' <<< "${text}")
    text=$(sed -E 's/(password|secret|token|api[_-]?key)[[:space:]]*[:=][[:space:]]*[^[:space:]\"]+/\1=[REDACTED]/gi' <<< "${text}")
    text=$(sed -E 's/x-access-token:[A-Za-z0-9._-]+/x-access-token:[REDACTED]/g' <<< "${text}")
    text=$(sed -E 's/Bearer[[:space:]]+[A-Za-z0-9._-]+/Bearer [REDACTED]/g' <<< "${text}")
    text=$(sed -E 's/Authorization:[[:space:]]*[^[:space:]\"]+/Authorization: [REDACTED]/gi' <<< "${text}")
    text=$(sed -E 's/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/[REDACTED-JWT]/g' <<< "${text}")
    text=$(sed -E 's/-----BEGIN [A-Z ]+-----[^-]*-----END [A-Z ]+-----/[REDACTED-PEM]/g' <<< "${text}")
    printf '%s' "${text}"
}

#######################################
# truncate_text: Truncate text to max length
#
# Globals:
#   None
#
# Arguments:
#   $1 - Input text
#   $2 - Maximum length
#
# Outputs:
#   Truncated text to stdout
#
# Returns:
#   0 on success
#
#######################################
function truncate_text {
    local text="$1"
    local max="$2"
    if [[ ${#text} -le ${max} ]]; then
        printf '%s' "${text}"
    else
        printf '%s' "${text:0:max}"
    fi
}

#######################################
# validate_required_inputs: Validate required notify_context environment
#
# Globals:
#   BASE_BRANCH - Base branch for merge-base diff
#   GITHUB_OUTPUT - GitHub Actions output file path
#   WORKTREE_PATH - Absolute path to the worktree
#
# Arguments:
#   None
#
# Outputs:
#   None
#
# Returns:
#   Exits 1 when required input is missing
#
#######################################
function validate_required_inputs {
    : "${GITHUB_OUTPUT:?}"
    : "${WORKTREE_PATH:?}"
    : "${BASE_BRANCH:?}"
}

#######################################
# write_notify_context_output: Write notify_context_json multiline output
#
# Globals:
#   GITHUB_OUTPUT - GitHub Actions output file path
#
# Arguments:
#   $1 - notify_context JSON string
#
# Outputs:
#   None
#
# Returns:
#   None
#
#######################################
function write_notify_context_output {
    local notify_json="$1"
    local delim

    delim="NOTIFY_CONTEXT_$(openssl rand -hex 8)"
    {
        echo "notify_context_json<<${delim}"
        echo "${notify_json}"
        echo "${delim}"
    } >> "${GITHUB_OUTPUT}"
}

#######################################
# main: Build and write notify_context_json
#
# Globals:
#   BASE_BRANCH - Base branch for merge-base diff
#   DETECT_RESULT_JSON - Detect script JSON result (optional)
#   HAS_CHANGES - Whether loop produced commits (true/false)
#   STATUS_DIR - Attempt artifact directory (optional)
#   WORKTREE_PATH - Absolute path to the worktree
#
# Arguments:
#   None
#
# Outputs:
#   None
#
# Returns:
#   0 on success
#
#######################################
function main {
    local detect_json
    local loop_detect_lib
    local has_changes="${HAS_CHANGES}"
    local baseline_ref changed_files_json diff_stat fix_summary agent_summary=""
    local agent_report_overview=""
    local agent_report_summary=""
    local -a files=()
    local file count=0 extra=0 last_output notify_json

    loop_detect_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../loop-detect/lib" && pwd)"
    # shellcheck source=../../loop-detect/lib/handoff.sh
    # shellcheck disable=SC1091
    source "${loop_detect_lib}/handoff.sh"
    detect_json="$(loop_handoff_resolve_detect_result_json)"

    validate_required_inputs

    if [[ -n ${detect_json} ]] && ! jq -e . <<< "${detect_json}" > /dev/null 2>&1; then
        detect_json='{}'
    fi

    cd "${WORKTREE_PATH}" || exit 1
    git fetch origin "${BASE_BRANCH}" --prune > /dev/null 2>&1 || true

    # Align with loop.sh / verifier.sh: triple-dot vs origin/BASE.
    # Never fall back to HEAD alone when has_changes — that yields an empty diff
    # (seen on shallow clones when merge-base fails).
    if git rev-parse --verify "origin/${BASE_BRANCH}" > /dev/null 2>&1; then
        baseline_ref="$(git merge-base "origin/${BASE_BRANCH}" HEAD 2> /dev/null || git rev-parse "origin/${BASE_BRANCH}")"
    else
        baseline_ref="$(git rev-parse "HEAD^" 2> /dev/null || git rev-parse HEAD)"
    fi
    if [[ ${has_changes} == "true" && ${baseline_ref} == "$(git rev-parse HEAD)" ]]; then
        baseline_ref="$(git rev-parse "HEAD^" 2> /dev/null || git rev-parse HEAD)"
    fi

    fix_summary="$(build_fix_summary "${detect_json}")"
    fix_summary="$(truncate_text "$(redact_sensitive_text "${fix_summary}")" 2000)"

    changed_files_json='[]'
    diff_stat=""

    if [[ ${has_changes} == "true" ]]; then
        while IFS= read -r file; do
            [[ -z ${file} ]] && continue
            if [[ ${count} -lt 20 ]]; then
                files+=("${file}")
                count=$((count + 1))
            else
                extra=$((extra + 1))
            fi
        done < <(
            if git rev-parse --verify "origin/${BASE_BRANCH}" > /dev/null 2>&1; then
                git diff --name-only "origin/${BASE_BRANCH}...HEAD" -- . ':!.loop/' 2> /dev/null || true
            else
                git diff --name-only "${baseline_ref}" HEAD -- . ':!.loop/' 2> /dev/null || true
            fi
        )

        if [[ ${#files[@]} -gt 0 ]]; then
            changed_files_json="$(printf '%s\n' "${files[@]}" | jq -R . | jq -s .)"
            if [[ ${extra} -gt 0 ]]; then
                changed_files_json="$(jq --arg note "… (+${extra} more)" '. + [$note]' <<< "${changed_files_json}")"
            fi
        fi

        if git rev-parse --verify "origin/${BASE_BRANCH}" > /dev/null 2>&1; then
            diff_stat="$(git diff --stat "origin/${BASE_BRANCH}...HEAD" -- . ':!.loop/' 2> /dev/null | tail -1 || true)"
        else
            diff_stat="$(git diff --stat "${baseline_ref}" HEAD -- . ':!.loop/' 2> /dev/null | tail -1 || true)"
        fi
        diff_stat="$(truncate_text "$(redact_sensitive_text "${diff_stat}")" 500)"
    fi

    if [[ -n ${STATUS_DIR} && -d ${STATUS_DIR} ]]; then
        last_output="$(find "${STATUS_DIR}" -name 'agent-output.txt' 2> /dev/null | sort -V | tail -1 || true)"
        if [[ -n ${last_output} ]]; then
            agent_summary="$(parse_agent_summary "${last_output}")"
            agent_summary="$(truncate_text "$(redact_sensitive_text "${agent_summary}")" 2000)"
            agent_report_overview="$(extract_agent_report_overview "${last_output}")"
            agent_report_overview="$(truncate_text "$(redact_sensitive_text "${agent_report_overview}")" 2000)"
            agent_report_summary="$(extract_agent_report_summary "${last_output}")"
            agent_report_summary="$(truncate_text "$(redact_sensitive_text "${agent_report_summary}")" 4000)"
        fi
    fi

    notify_json="$(jq -nc \
        --argjson changed_files "${changed_files_json}" \
        --arg diff_stat "${diff_stat}" \
        --arg fix_summary "${fix_summary}" \
        --arg agent_report_overview "${agent_report_overview}" \
        --arg agent_report_summary "${agent_report_summary}" \
        --arg agent_summary "${agent_summary}" \
        --arg baseline_ref "${baseline_ref}" \
        '{
            changed_files: $changed_files,
            diff_stat: $diff_stat,
            fix_summary: $fix_summary,
            agent_report_overview: $agent_report_overview,
            agent_report_summary: $agent_report_summary,
            agent_summary: $agent_summary,
            baseline_ref: $baseline_ref
        }')"

    write_notify_context_output "${notify_json}"
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
