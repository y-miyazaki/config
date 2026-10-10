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
#   source loop_meta.sh
#   loop_meta_reset
#   loop_meta_row "Level" "L2"
#   build_loop_meta_block OUTCOME VERDICT REASON ENGINE USAGE_JSON RUN_URL
#
# Output:
#   None (library file, sourced by other scripts)
#
# Design Rules:
#   - Meta is collapsed and goes last; the change description stays the lead
#   - Engine, model, and token rows are always carried when the run reports them
#   - Caller-specific rows are added with loop_meta_row before rendering
#   - Emits nothing when no row, reason, or usage field is known
#######################################

# Marker identifying an already-rendered meta block (idempotency for appenders)
LOOP_META_MARKER="<!-- loop-meta:v1 -->"
# Accumulated "| Field | Value |" rows for the next render
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
    local icon model tokens reason_line
    local -a rows=()

    if [[ ${#LOOP_META_ROWS[@]} -gt 0 ]]; then
        rows=("${LOOP_META_ROWS[@]}")
    fi

    if [[ -n ${verdict} ]]; then
        rows+=("| Verdict | \`${verdict}\` |")
    fi

    model=""
    tokens=""
    if declare -F usage_model_label > /dev/null 2>&1; then
        model="$(usage_model_label "${usage_json}")"
    fi
    if declare -F usage_tokens_label > /dev/null 2>&1; then
        tokens="$(usage_tokens_label "${usage_json}")"
    fi

    [[ -n ${engine} ]] && rows+=("| Engine | \`${engine}\` |")
    [[ -n ${model} ]] && rows+=("| Model | \`${model}\` |")
    [[ -n ${tokens} ]] && rows+=("| Tokens | In/Out ${tokens} |")
    if [[ -n ${run_url} && ${run_url} != "-" ]]; then
        rows+=("| Run | [View run](${run_url}) |")
    fi

    if [[ ${#rows[@]} -eq 0 && -z ${reason} ]]; then
        return 0
    fi

    icon="$(loop_meta_icon "${outcome}" "${verdict}")"

    {
        printf '%s\n' "${LOOP_META_MARKER}"
        printf '<details>\n'
        printf '<summary>%s <code>%s</code> · Loop details</summary>\n\n' \
            "${icon}" "${outcome:-unknown}"
        if [[ ${#rows[@]} -gt 0 ]]; then
            printf '%s\n' "| Field | Value |"
            printf '%s\n' "| ----- | ----- |"
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
# loop_meta_icon: Pick the status icon for an outcome/verdict pair
#
# Globals:
#   None
#
# Arguments:
#   $1 - Outcome enum (optional)
#   $2 - Verdict APPROVE/REJECT (optional)
#
# Outputs:
#   Status emoji on stdout
#
# Returns:
#   0 on success
#
# Usage:
#   icon="$(loop_meta_icon "${OUTCOME}" "${VERDICT}")"
#
#######################################
function loop_meta_icon {
    local outcome="${1:-}"
    local verdict="${2:-}"

    if [[ ${verdict} == "REJECT" || ${outcome} == "rejected" || ${outcome} == "error" ]]; then
        printf '❌'
    elif [[ -z ${outcome} || ${outcome} == "no-changes" || ${outcome} == "skipped" || ${outcome} == "watch" ]]; then
        printf 'ℹ️'
    else
        printf '✅'
    fi
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
#   $1 - Field label
#   $2 - Preformatted value cell (caller owns any backticks or links)
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

    if [[ -z ${label} || -z ${value} ]]; then
        return 0
    fi

    LOOP_META_ROWS+=("| ${label} | ${value} |")
}
