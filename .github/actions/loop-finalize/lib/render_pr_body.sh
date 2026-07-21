#!/bin/bash
#######################################
# Description:
#   Compose hybrid PR body markdown from caller prefix, detect failures,
#   changed files, agent overview/summary, and run metadata.
#   Environment variables mirror loop-finalize Create PR step inputs.
#
# Usage:
#   PR_BODY_PREFIX=... DETECT_RESULT_JSON=... bash lib/render_pr_body.sh
#
# Design Rules:
#   - Pure composition; no gh/git side effects
#   - Optional sections omit quietly when data is missing
#   - Failures list all entries up to FAILURES_MAX, then "… and N more"
#   - Redact patterns aligned with loop-execute/lib/notify_context.sh
#
# Output:
#   Full PR body markdown on stdout
#
# Dependencies:
#   - bash, jq
#######################################

# Error handling: exit on error, unset variable, or failed pipeline
set -euo pipefail

# Secure defaults
umask 027
export LC_ALL=C.UTF-8

#######################################
# Global variables
#######################################
AGENT_REPORT_OVERVIEW="${AGENT_REPORT_OVERVIEW:-}"
AGENT_REPORT_SUMMARY="${AGENT_REPORT_SUMMARY:-}"
AGENT_REPORT_VERIFICATION="${AGENT_REPORT_VERIFICATION:-}"
CHANGED_FILES_JSON="${CHANGED_FILES_JSON:-"[]"}"
DETECT_RESULT_JSON="${DETECT_RESULT_JSON:-"{}"}"
FAILURES_MAX="${FAILURES_MAX:-5}"
LEVEL="${LEVEL:-}"
OVERVIEW_MAX_CHARS="${OVERVIEW_MAX_CHARS:-2000}"
PR_BODY_PREFIX="${PR_BODY_PREFIX:-}"
SKIP_REASON="${SKIP_REASON:-}"
SUMMARY_MAX_CHARS="${SUMMARY_MAX_CHARS:-4000}"
TARGET_KEY="${TARGET_KEY:-}"
VERIFICATION_MAX_CHARS="${VERIFICATION_MAX_CHARS:-2000}"

#######################################
# redact_sensitive_text: Redact common secret patterns
#
# Description:
#   Replace common credential patterns with placeholders. Keep patterns
#   aligned with loop-execute/lib/notify_context.sh.
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
# render_agent_section: Render a redacted agent report section with heading
#
# Description:
#   Wrap pre-extracted agent body text under a ## heading. Empty input yields
#   no output.
#
# Globals:
#   None
#
# Arguments:
#   $1 - Pre-extracted body text (no heading)
#   $2 - Section heading (e.g. ## Overview)
#   $3 - Maximum length after redact
#
# Outputs:
#   Section markdown to stdout (empty when blank)
#
# Returns:
#   0 on success
#
#######################################
function render_agent_section {
    local text="${1:-}"
    local heading="${2:-}"
    local max_chars="${3:-}"

    text="$(truncate_text "$(redact_sensitive_text "${text}")" "${max_chars}")"
    if [[ -z ${text} ]]; then
        return 0
    fi
    printf '%s\n' "${heading}"
    printf '%s\n' "${text}"
    printf '\n'
}

#######################################
# render_agent_overview_section: Render agent ## Overview section
#
# Description:
#   Wrap pre-extracted agent overview body text under a ## Overview heading.
#   Empty input yields no output.
#
# Globals:
#   OVERVIEW_MAX_CHARS - Maximum length after redact
#
# Arguments:
#   $1 - Pre-extracted overview body text (no heading)
#
# Outputs:
#   Section markdown to stdout (empty when blank)
#
# Returns:
#   0 on success
#
#######################################
function render_agent_overview_section {
    render_agent_section "${1:-}" "## Overview" "${OVERVIEW_MAX_CHARS}"
}

#######################################
# render_agent_summary_section: Render agent ## Summary section
#
# Description:
#   Wrap pre-extracted agent summary body text under a ## Summary heading.
#   Empty input yields no output.
#
# Globals:
#   SUMMARY_MAX_CHARS - Maximum length after redact
#
# Arguments:
#   $1 - Pre-extracted summary body text (no heading)
#
# Outputs:
#   Section markdown to stdout (empty when blank)
#
# Returns:
#   0 on success
#
#######################################
function render_agent_summary_section {
    render_agent_section "${1:-}" "## Summary" "${SUMMARY_MAX_CHARS}"
}

#######################################
# render_agent_verification_section: Render agent ## Verification section
#
# Description:
#   Wrap pre-extracted agent verification body text under a ## Verification heading.
#   Empty input yields no output.
#
# Globals:
#   VERIFICATION_MAX_CHARS - Maximum length after redact
#
# Arguments:
#   $1 - Pre-extracted verification body text (no heading)
#
# Outputs:
#   Section markdown to stdout (empty when blank)
#
# Returns:
#   0 on success
#
#######################################
function render_agent_verification_section {
    render_agent_section "${1:-}" "## Verification" "${VERIFICATION_MAX_CHARS}"
}

#######################################
# agent_summary_has_detailed_changes: Return whether summary owns change detail
#
# Description:
#   When the agent Summary includes a Changes (or legacy Fixes Applied) subsection,
#   skip the mechanical git-diff ## Changes list to avoid duplicate file rosters.
#
# Globals:
#   None
#
# Arguments:
#   $1 - Agent summary body text
#
# Outputs:
#   None
#
# Returns:
#   0 when detailed changes subsection is present; 1 otherwise
#
#######################################
function agent_summary_has_detailed_changes {
    local summary="${1:-}"

    [[ ${summary} == *"### Changes"* || ${summary} == *"### Fixes Applied"* ]]
}

#######################################
# render_changes_section: Render ## Changes section
#
# Description:
#   List changed file paths from a JSON string array. Strips notify-style
#   overflow notes (… (+N more)) before listing; preserves or recomputes
#   overflow. Caps display at 20 paths when no notify note is present.
#
# Globals:
#   None
#
# Arguments:
#   $1 - JSON string array of changed file paths
#
# Outputs:
#   Section markdown to stdout (empty when no files)
#
# Returns:
#   0 on success
#
#######################################
function render_changes_section {
    local files_json="${1:-[]}"
    local paths_json note=""
    local path shown=0
    local n

    if ! jq -e 'type == "array" and length > 0' <<< "${files_json}" > /dev/null 2>&1; then
        return 0
    fi

    note="$(jq -r '.[] | select(type == "string" and test("^… \\(\\+[0-9]+ more\\)$"))' <<< "${files_json}" | head -1 || true)"
    paths_json="$(jq '[.[] | select(type == "string" and (test("^… \\(\\+[0-9]+ more\\)$") | not))]' <<< "${files_json}")"

    if ! jq -e 'length > 0' <<< "${paths_json}" > /dev/null 2>&1; then
        return 0
    fi

    n="$(jq -r 'length' <<< "${paths_json}")"
    printf '%s\n' "## Changes"
    shown=0
    while IFS= read -r path; do
        [[ -z ${path} ]] && continue
        if [[ ${shown} -lt 20 ]]; then
            printf '%s\n' "- \`${path}\`"
            shown=$((shown + 1))
        fi
    done < <(jq -r '.[]' <<< "${paths_json}")

    if [[ -n ${note} ]]; then
        printf '%s\n' "- ${note}"
    elif [[ ${n} -gt 20 ]]; then
        printf '%s\n' "- … (+$((n - 20)) more)"
    fi
    printf '\n'
}

#######################################
# render_failure_context: Render ## Failure context section
#
# Description:
#   Enumerate detect failures with workflow, run URL, job, type, and reason.
#   Lists up to FAILURES_MAX entries then an overflow line.
#
# Globals:
#   FAILURES_MAX - Maximum failure entries to list (default 5)
#
# Arguments:
#   $1 - Detect result JSON
#
# Outputs:
#   Section markdown to stdout (empty when no failures)
#
# Returns:
#   0 on success
#
#######################################
function render_failure_context {
    local detect_json="${1:-}"
    local count i max shown
    local workflow_name run_url job_name failure_type reason

    if [[ -z ${detect_json} ]] || ! jq -e '(.failures | type) == "array" and (.failures | length) > 0' <<< "${detect_json}" > /dev/null 2>&1; then
        return 0
    fi

    count="$(jq -r '.failures | length' <<< "${detect_json}")"
    max="${FAILURES_MAX}"
    printf '%s\n' "## Failure context"
    shown=0
    i=0
    while [[ ${i} -lt ${count} ]]; do
        if [[ ${shown} -ge ${max} ]]; then
            printf '%s\n' "… and $((count - shown)) more"
            break
        fi
        workflow_name="$(jq -r --argjson i "${i}" '.failures[$i].workflow_name // empty' <<< "${detect_json}")"
        run_url="$(jq -r --argjson i "${i}" '.failures[$i].run_url // empty' <<< "${detect_json}")"
        job_name="$(jq -r --argjson i "${i}" '.failures[$i].job_name // empty' <<< "${detect_json}")"
        failure_type="$(jq -r --argjson i "${i}" '.failures[$i].failure_type // empty' <<< "${detect_json}")"
        reason="$(jq -r --argjson i "${i}" '.failures[$i].reason // empty' <<< "${detect_json}")"
        reason="$(truncate_text "$(redact_sensitive_text "${reason}")" 500)"
        [[ -n ${workflow_name} ]] && printf '%s\n' "- Workflow: \`${workflow_name}\`"
        [[ -n ${run_url} ]] && printf '%s\n' "- Run: ${run_url}"
        [[ -n ${job_name} ]] && printf '%s\n' "- Job: \`${job_name}\`"
        [[ -n ${failure_type} ]] && printf '%s\n' "- Type: \`${failure_type}\`"
        [[ -n ${reason} ]] && printf '%s\n' "- Reason: ${reason}"
        printf '\n'
        shown=$((shown + 1))
        i=$((i + 1))
    done
}

#######################################
# escape_markdown_table_cell: Escape pipe and newline for table cells
#
# Globals:
#   None
#
# Arguments:
#   $1 - Raw cell text
#
# Outputs:
#   Escaped text to stdout
#
# Returns:
#   0 on success
#
#######################################
function escape_markdown_table_cell {
    local text="$1"
    text="${text//$'\r'/}"
    text="${text//$'\n'/ }"
    text="${text//|/\\|}"
    printf '%s' "${text}"
}

#######################################
# render_run_metadata: Render ## Run Metadata table
#
# Description:
#   Emit Level, Target, and Skip reason as a Field | Value table when any
#   field is set.
#
# Globals:
#   None
#
# Arguments:
#   $1 - Level (e.g. L2)
#   $2 - Target key (e.g. integration:main)
#   $3 - Skip reason
#
# Outputs:
#   Section markdown to stdout (empty when all fields blank)
#
# Returns:
#   0 on success
#
#######################################
function render_run_metadata {
    local level="${1:-}"
    local target_key="${2:-}"
    local skip_reason="${3:-}"

    if [[ -z ${level}${target_key}${skip_reason} ]]; then
        return 0
    fi
    printf '%s\n' "## Run Metadata"
    printf '%s\n' "| Field | Value |"
    printf '%s\n' "| ----- | ----- |"
    [[ -n ${level} ]] && printf '%s\n' "| Level | $(escape_markdown_table_cell "${level}") |"
    [[ -n ${target_key} ]] && printf '%s\n' "| Target | \`$(escape_markdown_table_cell "${target_key}")\` |"
    [[ -n ${skip_reason} ]] && printf '%s\n' "| Skip reason | $(escape_markdown_table_cell "${skip_reason}") |"
    printf '\n'
}

#######################################
# render_automation_disclaimer: Render loop automation footer line
#
# Description:
#   Emit the standard disclaimer appended to every loop-created PR body.
#
# Globals:
#   None
#
# Arguments:
#   None
#
# Outputs:
#   Disclaimer markdown to stdout
#
# Returns:
#   0 on success
#
#######################################
function render_automation_disclaimer {
    printf '%s\n\n' $'---\n*This PR was created by a loop automation. Review before merging.*'
}

#######################################
# render_pr_body: Compose full PR body from environment
#
# Description:
#   Assemble prefix, Overview, Failure context, Summary, Changes, Run
#   Metadata, and disclaimer in that order. Missing optional sections are skipped.
#
# Globals:
#   AGENT_REPORT_OVERVIEW - Agent overview body text
#   AGENT_REPORT_SUMMARY - Agent summary body text
#   AGENT_REPORT_VERIFICATION - Agent verification body text
#   CHANGED_FILES_JSON - JSON string array of changed paths
#   DETECT_RESULT_JSON - Detect JSON with failures array
#   LEVEL - Run metadata level
#   PR_BODY_PREFIX - Caller static prefix
#   SKIP_REASON - Run metadata skip reason
#   TARGET_KEY - Run metadata target key
#
# Arguments:
#   None
#
# Outputs:
#   Full PR body markdown to stdout
#
# Returns:
#   0 on success
#
#######################################
function render_pr_body {
    local section
    local prefix="${PR_BODY_PREFIX}"

    if [[ -n ${prefix} ]]; then
        # Trim trailing whitespace from prefix.
        prefix="${prefix%"${prefix##*[![:space:]]}"}"
        printf '%s\n\n' "${prefix}"
    fi

    section="$(render_agent_overview_section "${AGENT_REPORT_OVERVIEW}")"
    [[ -n ${section} ]] && printf '%s\n' "${section}"

    section="$(render_failure_context "${DETECT_RESULT_JSON}")"
    [[ -n ${section} ]] && printf '%s\n' "${section}"

    section="$(render_agent_summary_section "${AGENT_REPORT_SUMMARY}")"
    [[ -n ${section} ]] && printf '%s\n' "${section}"

    section="$(render_agent_verification_section "${AGENT_REPORT_VERIFICATION}")"
    [[ -n ${section} ]] && printf '%s\n' "${section}"

    if ! agent_summary_has_detailed_changes "${AGENT_REPORT_SUMMARY}"; then
        section="$(render_changes_section "${CHANGED_FILES_JSON}")"
        [[ -n ${section} ]] && printf '%s\n' "${section}"
    fi

    render_run_metadata "${LEVEL}" "${TARGET_KEY}" "${SKIP_REASON}"
    render_automation_disclaimer
}

#######################################
# truncate_text: Truncate text to max length
#
# Description:
#   Return the input unchanged when within max; otherwise cut to max chars.
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
# main: Print composed PR body
#
# Description:
#   Entry point when this file is executed (not sourced).
#
# Globals:
#   None (delegates to render_pr_body)
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
    render_pr_body
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
