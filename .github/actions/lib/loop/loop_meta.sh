#!/bin/bash
#######################################
# Description:
#   Render the one canonical loop meta block shared by every Loop Engineering
#   surface: PR bodies, PR comments, trigger-thread replies, and the Issue
#   comment an entity (L1) agent posts. One renderer keeps the shape identical
#   wherever a loop speaks.
#
# Usage:
#   source created_by.sh
#   source loop_meta.sh   (sources outcome.sh itself)
#   loop_meta_reset
#   loop_meta_row "Level" "L2"
#   build_loop_meta_block OUTCOME VERDICT REASON ENGINE USAGE_JSON RUN_URL
#
# Output:
#   None (library file, sourced by other scripts)
#
# Design Rules:
#   - Meta is collapsed (summary text: Meta) and goes last; the change description stays the lead
#   - One `| Key | Value |` table: keys are backticked snake_case, values are plain text
#   - Engine, model, and token rows are always carried when the run reports them
#   - Caller-specific rows are added with loop_meta_row before rendering
#   - Emits nothing when no row, reason, or usage field is known
#######################################

_LOOP_META_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./outcome.sh
# shellcheck disable=SC1091
source "${_LOOP_META_DIR}/outcome.sh"

# Marker identifying an already-rendered meta block (idempotency for appenders)
LOOP_META_MARKER="<!-- loop-meta:v1 -->"
# Accumulated "| `key` | value |" rows for the next render
LOOP_META_ROWS=()

#######################################
# build_loop_meta_block: Render the collapsed loop meta block
#
# Globals:
#   LOOP_META_MARKER - Idempotency marker emitted as the first line
#   LOOP_META_ROWS - Caller rows rendered above the engine/model/token rows
#
# Arguments:
#   $1 - Outcome enum (optional)
#   $2 - Verdict APPROVE/REJECT (optional)
#   $3 - Verdict reason (optional)
#   $4 - Engine slug (optional)
#   $5 - usage_json string (optional)
#   $6 - Loop run URL (optional)
#
# Outputs:
#   Markdown block on stdout, or empty when nothing is known
#
# Returns:
#   0 on success
#
# Usage:
#   block="$(build_loop_meta_block "${OUTCOME}" "${VERDICT}" "${REASON}" \
#       "${ENGINE}" "${USAGE_JSON}" "${run_url}")"
#
#######################################
function build_loop_meta_block {
    local outcome="${1:-}"
    local verdict="${2:-}"
    local reason="${3:-}"
    local engine="${4:-}"
    local usage_json="${5:-}"
    local run_url="${6:-}"
    local model tokens reason_line
    local -a rows=()

    if [[ ${#LOOP_META_ROWS[@]} -gt 0 ]]; then
        rows=("${LOOP_META_ROWS[@]}")
    fi

    if [[ -n ${verdict} ]]; then
        rows+=("| \`verdict\` | ${verdict} |")
    fi

    model=""
    tokens=""
    if declare -F usage_model_label > /dev/null 2>&1; then
        model="$(usage_model_label "${usage_json}")"
    fi
    if declare -F usage_tokens_label > /dev/null 2>&1; then
        tokens="$(usage_tokens_label "${usage_json}")"
    fi

    [[ -n ${engine} ]] && rows+=("| \`engine\` | ${engine} |")
    [[ -n ${model} ]] && rows+=("| \`model\` | ${model} |")
    [[ -n ${tokens} ]] && rows+=("| \`tokens\` | In/Out ${tokens} |")
    if [[ -n ${run_url} && ${run_url} != "-" ]]; then
        rows+=("| \`run\` | [View run](${run_url}) |")
    fi

    if [[ ${#rows[@]} -eq 0 && -z ${reason} ]]; then
        return 0
    fi

    # outcome leads the table; it is not counted when deciding whether anything is known
    if [[ -n ${outcome} ]]; then
        rows=("| \`outcome\` | ${outcome} |" "${rows[@]}")
    fi

    {
        printf '%s\n' "${LOOP_META_MARKER}"
        printf '<details>\n'
        printf '<summary>Meta</summary>\n\n'
        if [[ ${#rows[@]} -gt 0 ]]; then
            printf '%s\n' "| Key | Value |"
            printf '%s\n' "| --- | --- |"
            printf '%s\n' "${rows[@]}"
            printf '\n'
        fi
        if [[ -n ${reason} ]]; then
            printf '**Why this verdict**\n\n'
            # Quote every line so multi-line checker reasons stay one block
            # instead of collapsing into a run-on paragraph.
            while IFS= read -r reason_line; do
                printf '> %s\n' "${reason_line}"
            done <<< "${reason}"
            printf '\n'
        fi
        printf '</details>\n'
    }
}

#######################################
# loop_meta_reset: Clear accumulated caller rows
#
# Globals:
#   LOOP_META_ROWS - Reset to empty
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
# Usage:
#   loop_meta_reset
#
#######################################
function loop_meta_reset {
    LOOP_META_ROWS=()
}

#######################################
# loop_meta_row: Queue one caller row for the next meta block
#
# Globals:
#   LOOP_META_ROWS - Appended to
#
# Arguments:
#   $1 - Field label (rendered as a backticked snake_case key: "Skip reason" -> `skip_reason`)
#   $2 - Plain-text value cell (callers escape pipes; links are allowed for run and commit)
#
# Outputs:
#   None
#
# Returns:
#   0 on success; skips silently when label or value is empty
#
# Usage:
#   loop_meta_row "Level" "L2"
#
#######################################
function loop_meta_row {
    local label="${1:-}"
    local value="${2:-}"
    local key

    if [[ -z ${label} || -z ${value} ]]; then
        return 0
    fi

    key="$(tr '[:upper:] ' '[:lower:]_' <<< "${label}")"
    LOOP_META_ROWS+=("| \`${key}\` | ${value} |")
}
