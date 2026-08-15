#!/bin/bash
#######################################
# Description:
#   Format a one-line Created By footer for loop PR bodies and comments.
#
# Usage:
#   source created_by.sh
#   render_created_by_line ENGINE USAGE_JSON
#
# Output:
#   None (library file, sourced by other scripts)
#
# Design Rules:
#   - Omit the line entirely when engine, model, and tokens are all absent
#   - Numeric K/M compaction matches statusline format_compact_tokens; statusline
#     prints em dash for empty/null input while this helper returns exit 1 (callers
#     substitute em dash only in In/Out slots)
#   - usage_json may be empty or invalid; treat as no measured usage
#######################################

#######################################
# format_compact_tokens: Compact integer token count for display
#
# Globals:
#   None
#
# Arguments:
#   $1 - Non-negative integer token count
#
# Outputs:
#   Compact label to stdout (e.g. 17, 2K, 1.2M)
#
# Returns:
#   0 on success; 1 when input is not a non-negative integer
#
#######################################
function format_compact_tokens {
    local n="${1:-}"

    if [[ -z ${n} || ${n} == "null" || ! ${n} =~ ^[0-9]+$ ]]; then
        return 1
    fi
    if ((n >= 1000000)); then
        printf '%d.%dM' $((n / 1000000)) $(((n % 1000000) / 100000))
    elif ((n >= 1000)); then
        printf '%dK' $(((n + 500) / 1000))
    else
        printf '%d' "${n}"
    fi
}

#######################################
# render_created_by_line: Emit Created By engine/model/token footer
#
# Description:
#   Prints one line: Created By {engine} {model} In/Out: {in}/{out}
#   Omits missing optional segments. Empty when nothing useful is known.
#
# Globals:
#   None
#
# Arguments:
#   $1 - Engine slug (optional)
#   $2 - usage_json string (optional; total_input_tokens, total_output_tokens, model)
#
# Outputs:
#   Footer line to stdout, or empty when all fields absent
#
# Returns:
#   0 on success
#
#######################################
function render_created_by_line {
    local engine="${1:-}"
    local usage_json="${2:-}"
    local model="" input="" output="" in_fmt="" out_fmt="" line=""

    if [[ -n ${usage_json} ]] && jq -e . > /dev/null 2>&1 <<< "${usage_json}"; then
        model="$(jq -r '.model // empty' <<< "${usage_json}" 2> /dev/null || true)"
        input="$(jq -r '.total_input_tokens // .input_tokens // empty' <<< "${usage_json}" 2> /dev/null || true)"
        output="$(jq -r '.total_output_tokens // .output_tokens // empty' <<< "${usage_json}" 2> /dev/null || true)"
    fi

    if [[ -z ${engine}${model} ]] && [[ ! ${input} =~ ^[0-9]+$ ]] && [[ ! ${output} =~ ^[0-9]+$ ]]; then
        return 0
    fi

    line="Created By"
    [[ -n ${engine} ]] && line+=" ${engine}"
    [[ -n ${model} ]] && line+=" ${model}"
    if [[ ${input} =~ ^[0-9]+$ ]] || [[ ${output} =~ ^[0-9]+$ ]]; then
        if [[ ${input} =~ ^[0-9]+$ ]]; then
            in_fmt="$(format_compact_tokens "${input}")"
        else
            in_fmt="—"
        fi
        if [[ ${output} =~ ^[0-9]+$ ]]; then
            out_fmt="$(format_compact_tokens "${output}")"
        else
            out_fmt="—"
        fi
        line+=" In/Out: ${in_fmt}/${out_fmt}"
    fi

    printf '%s\n' "${line}"
}
