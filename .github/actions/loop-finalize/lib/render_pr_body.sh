#!/bin/bash
#######################################
# Description:
#   Compose hybrid PR body markdown from caller prefix, detect failures,
#   changed files, agent summary, and footer fields.
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
AGENT_REPORT_SUMMARY="${AGENT_REPORT_SUMMARY:-}"
CHANGED_FILES_JSON="${CHANGED_FILES_JSON:-"[]"}"
DETECT_RESULT_JSON="${DETECT_RESULT_JSON:-"{}"}"
FAILURES_MAX="${FAILURES_MAX:-5}"
LEVEL="${LEVEL:-}"
PR_BODY_PREFIX="${PR_BODY_PREFIX:-}"
SKIP_REASON="${SKIP_REASON:-}"
SUMMARY_MAX_CHARS="${SUMMARY_MAX_CHARS:-4000}"
TARGET_KEY="${TARGET_KEY:-}"

#######################################
# redact_sensitive_text: Redact common secret patterns
#
# Description:
#   Replace common credential patterns with placeholders. Keep patterns
#   aligned with loop-execute/lib/notify_context.sh.
#
# Arguments:
#   $1 - Input text
#
# Global Variables:
#   None
#
# Returns:
#   Redacted text to stdout
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
# render_agent_summary_section: Render agent ## Summary section
#
# Description:
#   Wrap pre-extracted agent summary body text under a ## Summary heading.
#   Empty input yields no output.
#
# Arguments:
#   $1 - Pre-extracted summary body text (no heading)
#
# Global Variables:
#   SUMMARY_MAX_CHARS - Maximum length after redact
#
# Returns:
#   Section markdown to stdout (empty when blank)
#
#######################################
function render_agent_summary_section {
    local text="${1:-}"

    text="$(truncate_text "$(redact_sensitive_text "${text}")" "${SUMMARY_MAX_CHARS}")"
    if [[ -z ${text} ]]; then
        return 0
    fi
    printf '%s\n' "## Summary"
    printf '%s\n' "${text}"
    printf '\n'
}

#######################################
# render_changes_section: Render ## Changes section
#
# Description:
#   List changed file paths from a JSON string array. Strips notify-style
#   overflow notes (… (+N more)) before listing; preserves or recomputes
#   overflow. Caps display at 20 paths when no notify note is present.
#
# Arguments:
#   $1 - JSON string array of changed file paths
#
# Global Variables:
#   None
#
# Returns:
#   Section markdown to stdout (empty when no files)
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
# Arguments:
#   $1 - Detect result JSON
#
# Global Variables:
#   FAILURES_MAX - Maximum failure entries to list (default 5)
#
# Returns:
#   Section markdown to stdout (empty when no failures)
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
# render_footer: Render Level/Target/Skip reason footer
#
# Description:
#   Emit the existing loop PR footer bullets when any field is set.
#
# Arguments:
#   $1 - Level (e.g. L2)
#   $2 - Target key (e.g. integration:main)
#   $3 - Skip reason
#
# Global Variables:
#   None
#
# Returns:
#   Footer markdown to stdout (empty when all fields blank)
#
#######################################
function render_footer {
    local level="${1:-}"
    local target_key="${2:-}"
    local skip_reason="${3:-}"

    if [[ -z ${level}${target_key}${skip_reason} ]]; then
        return 0
    fi
    [[ -n ${level} ]] && printf '%s\n' "- Level: ${level}"
    [[ -n ${target_key} ]] && printf '%s\n' "- Target: \`${target_key}\`"
    [[ -n ${skip_reason} ]] && printf '%s\n' "- Skip reason: ${skip_reason}"
    return 0
}

#######################################
# render_pr_body: Compose full PR body from environment
#
# Description:
#   Assemble prefix, Failure context, Changes, agent Summary, and footer
#   in that order. Missing optional sections are skipped.
#
# Arguments:
#   None
#
# Global Variables:
#   AGENT_REPORT_SUMMARY - Agent summary body text
#   CHANGED_FILES_JSON - JSON string array of changed paths
#   DETECT_RESULT_JSON - Detect JSON with failures array
#   LEVEL - Footer level
#   PR_BODY_PREFIX - Caller static prefix
#   SKIP_REASON - Footer skip reason
#   TARGET_KEY - Footer target key
#
# Returns:
#   Full PR body markdown to stdout
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

    section="$(render_failure_context "${DETECT_RESULT_JSON}")"
    [[ -n ${section} ]] && printf '%s\n' "${section}"

    section="$(render_changes_section "${CHANGED_FILES_JSON}")"
    [[ -n ${section} ]] && printf '%s\n' "${section}"

    section="$(render_agent_summary_section "${AGENT_REPORT_SUMMARY}")"
    [[ -n ${section} ]] && printf '%s\n' "${section}"

    render_footer "${LEVEL}" "${TARGET_KEY}" "${SKIP_REASON}"
}

#######################################
# truncate_text: Truncate text to max length
#
# Description:
#   Return the input unchanged when within max; otherwise cut to max chars.
#
# Arguments:
#   $1 - Input text
#   $2 - Maximum length
#
# Global Variables:
#   None
#
# Returns:
#   Truncated text to stdout
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
# Arguments:
#   None
#
# Global Variables:
#   None (delegates to render_pr_body)
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
