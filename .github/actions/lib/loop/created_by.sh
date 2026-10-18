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
    local model tokens line=""

    model="$(usage_model_label "${usage_json}")"
    tokens="$(usage_tokens_label "${usage_json}")"

    if [[ -z ${engine}${model}${tokens} ]]; then
        return 0
    fi

    line="Created By"
    [[ -n ${engine} ]] && line+=" ${engine}"
    [[ -n ${model} ]] && line+=" ${model}"
    [[ -n ${tokens} ]] && line+=" In/Out: ${tokens}"

    printf '%s\n' "${line}"
}

#######################################
# usage_model_label: Resolve a display label for the models a run used
#
# Globals:
#   None
#
# Arguments:
#   $1 - usage_json string (optional)
#
# Outputs:
#   Model label on stdout (single model, role=model pairs, or comma list);
#   empty when no model is known
#
# Returns:
#   0 on success
#
# Usage:
#   label="$(usage_model_label "${USAGE_JSON}")"
#
#######################################
function usage_model_label {
    local usage_json="${1:-}"

    if [[ -z ${usage_json} ]] || ! jq -e . > /dev/null 2>&1 <<< "${usage_json}"; then
        return 0
    fi

    # A maker/checker run reports two models, so build_usage_json omits the
    # single-valued .model and emits .models plus per-session roles instead.
    # Reading only .model therefore dropped the model from the footer on
    # every mixed run. Prefer role labels, then the models array.
    jq -r '
            if (.model // "") != "" then .model
            elif ((.sessions // []) | map(select((.role // "") != "" and (.model // "") != ""))) != [] then
              ((.sessions // [])
               | map(select((.role // "") != "" and (.model // "") != ""))
               | group_by(.role)
               | map({role: .[0].role, model: .[0].model})
               # Execution order, not alphabetical: maker runs, then checker.
               | sort_by((if .role == "maker" then 0 elif .role == "checker" then 1 else 2 end), .role)
               | map("\(.role)=\(.model)")
               | join(" "))
            elif ((.models // []) | length) > 0 then ((.models // []) | join(", "))
            else empty end
    ' <<< "${usage_json}" 2> /dev/null || true
}

#######################################
# usage_tokens_label: Resolve the In/Out token label for a run
#
# Globals:
#   None
#
# Arguments:
#   $1 - usage_json string (optional)
#
# Outputs:
#   Compacted "{in}/{out}" label on stdout; empty when neither side is known
#
# Returns:
#   0 on success
#
# Usage:
#   tokens="$(usage_tokens_label "${USAGE_JSON}")"
#
#######################################
function usage_tokens_label {
    local usage_json="${1:-}"
    local input="" output="" in_fmt="" out_fmt=""

    if [[ -n ${usage_json} ]] && jq -e . > /dev/null 2>&1 <<< "${usage_json}"; then
        input="$(jq -r '.total_input_tokens // .input_tokens // empty' <<< "${usage_json}" 2> /dev/null || true)"
        output="$(jq -r '.total_output_tokens // .output_tokens // empty' <<< "${usage_json}" 2> /dev/null || true)"
    fi

    if [[ ! ${input} =~ ^[0-9]+$ ]] && [[ ! ${output} =~ ^[0-9]+$ ]]; then
        return 0
    fi

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

    printf '%s/%s' "${in_fmt}" "${out_fmt}"
}

#######################################
# usage_cache_label: Resolve the prompt-cache label for a run
#
# Description:
#   In/Out totals exclude cache traffic, so a cached run shows a tiny In figure.
#   This label reports the cache counts next to it instead of folding them in.
#
# Globals:
#   None
#
# Arguments:
#   $1 - usage_json string (optional)
#
# Outputs:
#   "read {n}, write {n}" on stdout; empty when no cache traffic was measured
#
# Returns:
#   0 on success
#
# Usage:
#   cache="$(usage_cache_label "${USAGE_JSON}")"
#
#######################################
function usage_cache_label {
    local usage_json="${1:-}"
    local read="" write=""

    if [[ -z ${usage_json} ]] || ! jq -e . > /dev/null 2>&1 <<< "${usage_json}"; then
        return 0
    fi
    read="$(jq -r '.cache_read_tokens // 0' <<< "${usage_json}" 2> /dev/null || true)"
    write="$(jq -r '.cache_write_tokens // 0' <<< "${usage_json}" 2> /dev/null || true)"
    [[ ${read} =~ ^[0-9]+$ ]] || read=0
    [[ ${write} =~ ^[0-9]+$ ]] || write=0
    if ((read == 0 && write == 0)); then
        return 0
    fi
    printf 'read %s, write %s' "$(format_compact_tokens "${read}")" "$(format_compact_tokens "${write}")"
}

#######################################
# usage_rounds_label: Resolve the maker/checker round counts for a run
#
# Description:
#   Counts maker and checker sessions. A checker session that did not end the run
#   with APPROVE is a rejection, so rejected = checkers, minus one when the final
#   verdict is APPROVE.
#
# Globals:
#   None
#
# Arguments:
#   $1 - usage_json string (optional)
#   $2 - Final verdict APPROVE/REJECT (optional)
#
# Outputs:
#   "maker {n}, checker {n}, rejected {n}" on stdout; empty when no maker or
#   checker session was recorded
#
# Returns:
#   0 on success
#
# Usage:
#   rounds="$(usage_rounds_label "${USAGE_JSON}" "${VERDICT}")"
#
#######################################
function usage_rounds_label {
    local usage_json="${1:-}"
    local verdict="${2:-}"
    local makers checkers rejected

    if [[ -z ${usage_json} ]] || ! jq -e . > /dev/null 2>&1 <<< "${usage_json}"; then
        return 0
    fi
    makers="$(jq -r '[(.sessions // [])[] | select(.role == "maker")] | length' <<< "${usage_json}" 2> /dev/null || echo 0)"
    checkers="$(jq -r '[(.sessions // [])[] | select(.role == "checker")] | length' <<< "${usage_json}" 2> /dev/null || echo 0)"
    if ((makers == 0 && checkers == 0)); then
        return 0
    fi
    rejected="${checkers}"
    if [[ ${verdict} == "APPROVE" && ${checkers} -gt 0 ]]; then
        rejected=$((checkers - 1))
    fi
    printf 'maker %s, checker %s, rejected %s' "${makers}" "${checkers}" "${rejected}"
}
