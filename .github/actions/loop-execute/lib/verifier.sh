#!/bin/bash
#######################################
# Description: Verifier session helpers for loop-execute
#
# Usage: source "${SCRIPT_DIR}/lib/verifier.sh"
#
# Output:
# - None (library file, sourced by other scripts)
#
# Design Rules:
# - Deterministic denylist/allowlist checks run before the LLM verifier
# - Verifier output prefers fenced JSON; legacy formats are fallback only
#######################################

#######################################
# Global variables
#######################################
parsed=""
verdict=""
reason=""
files=""
issue=""
fix=""

#######################################
# extract_last_json_fence: Extract the last ```json fenced block from output
#
# Globals:
#   None
#
# Arguments:
#   $1 - Output file path
#
# Outputs:
#   JSON blob to stdout, or empty string
#
# Returns:
#   0 on success
#
#######################################
function extract_last_json_fence {
    local output_file="$1"
    awk '
        /^```json[[:space:]]*$/ { capture=1; block=""; next }
        capture && /^```[[:space:]]*$/ { blocks[++n]=block; capture=0; next }
        capture { block = block $0 "\n" }
        END { if (n > 0) printf "%s", blocks[n] }
    ' "${output_file}"
}

#######################################
# parse_verifier_output: Parse verifier agent output into structured fields
#
# Globals:
#   parsed - true when any format was recognized
#   verdict - APPROVE or REJECT
#   reason - One-line summary
#   files - Comma-separated file paths on REJECT
#   issue - Issue description on REJECT
#   fix - Required fix description on REJECT
#
# Arguments:
#   $1 - Output file path
#
# Outputs:
#   None
#
# Returns:
#   0
#
#######################################
function parse_verifier_output {
    local output_file="$1"
    local parse_file="${output_file}"
    local normalized_file=""
    local json_blob line

    parsed="false"
    verdict="REJECT"
    reason="Verifier output missing or unclear"
    files=""
    issue=""
    fix=""

    if declare -F is_cursor_stream_json_file > /dev/null 2>&1 \
        && is_cursor_stream_json_file "${output_file}"; then
        normalized_file="$(mktemp)"
        extract_cursor_stream_text "${output_file}" > "${normalized_file}"
        parse_file="${normalized_file}"
    fi

    json_blob="$(extract_last_json_fence "${parse_file}")"
    if [[ -n ${json_blob} ]] && jq -e '.verdict' > /dev/null 2>&1 <<< "${json_blob}"; then
        verdict=$(jq -r '.verdict' <<< "${json_blob}")
        reason=$(jq -r '.reason // empty' <<< "${json_blob}")
        issue=$(jq -r '.issue // empty' <<< "${json_blob}")
        fix=$(jq -r '.fix // empty' <<< "${json_blob}")
        files=$(jq -r '
            if (.files | type) == "array" then (.files | map(select(type == "string")) | join(","))
            elif (.files | type) == "string" then .files
            else empty end
        ' <<< "${json_blob}")
        parsed="true"
        if [[ -n ${normalized_file} ]]; then
            rm -f "${normalized_file}"
        fi
        return 0
    fi

    while IFS= read -r line; do
        if jq -e '.verdict' > /dev/null 2>&1 <<< "${line}"; then
            json_blob="${line}"
        fi
    done < <(tail -30 "${parse_file}")

    if [[ -n ${json_blob} ]]; then
        verdict=$(jq -r '.verdict' <<< "${json_blob}")
        reason=$(jq -r '.reason // empty' <<< "${json_blob}")
        issue=$(jq -r '.issue // empty' <<< "${json_blob}")
        fix=$(jq -r '.fix // empty' <<< "${json_blob}")
        files=$(jq -r '
            if (.files | type) == "array" then (.files | map(select(type == "string")) | join(","))
            elif (.files | type) == "string" then .files
            else empty end
        ' <<< "${json_blob}")
        parsed="true"
        if [[ -n ${normalized_file} ]]; then
            rm -f "${normalized_file}"
        fi
        return 0
    fi

    local verdict_line
    verdict_line=$(grep -E '^VERDICT:[[:space:]]*(APPROVE|REJECT)[[:space:]]*$' "${parse_file}" | tail -1 || true)
    if [[ -n ${verdict_line} ]]; then
        verdict=$(echo "${verdict_line}" | sed -E 's/^VERDICT:[[:space:]]*//')
        reason="$(parse_output_field "${parse_file}" "REASON")"
        files="$(parse_output_field "${parse_file}" "FILES")"
        issue="$(parse_output_field "${parse_file}" "ISSUE")"
        fix="$(parse_output_field "${parse_file}" "FIX")"
        [[ -n ${reason} ]] || reason="No reason provided"
        parsed="true"
        echo "::warning::Verifier used legacy line format; prefer JSON verdict block"
        if [[ -n ${normalized_file} ]]; then
            rm -f "${normalized_file}"
        fi
        return 0
    fi

    local legacy_line
    legacy_line=$(grep -E '^(APPROVE|REJECT)([[:space:]:]|$)' "${parse_file}" | tail -1 || true)
    if [[ -n ${legacy_line} ]]; then
        verdict=$(echo "${legacy_line}" | grep -oE '^(APPROVE|REJECT)' | head -1)
        reason=$(echo "${legacy_line}" | sed -E 's/^(APPROVE|REJECT):?[[:space:]]*//')
        parsed="true"
        echo "::warning::Verifier used legacy verdict format; prefer JSON verdict block"
    fi

    if [[ -n ${normalized_file} ]]; then
        rm -f "${normalized_file}"
    fi
}

#######################################
# write_verifier_output_contract: Print verifier JSON output contract
#
# Globals:
#   PROMPT_VERIFIER_OUTPUT_CONTRACT - Contract markdown
#
# Arguments:
#   None
#
# Outputs:
#   Contract markdown to stdout
#
# Returns:
#   0 on success
#
#######################################
function write_verifier_output_contract {
    printf '%s\n' "${PROMPT_VERIFIER_OUTPUT_CONTRACT}"
}

#######################################
# run_verify: Run one verifier session for the current attempt
#
# Globals:
#   BASE_BRANCH, DENYLIST, ALLOWLIST, WORKTREE_PATH
#   AGENT_VERIFIER_CRITERIA, AGENT_VERIFIER_MAX_TURNS, AGENT_VERIFIER_MODEL
#   LIB_DIR, OPEN_REJECTIONS_JSON, SKILL_NAME, VERIFIER_CONTEXT
#   PROMPT_VERIFIER_* prompt env vars
#
# Arguments:
#   $1 - Attempt directory
#   $2 - Attempt number
#   $3 - Whether this attempt created a commit (true|false)
#
# Outputs:
#   None
#
# Returns:
#   0
#
#######################################
function run_verify {
    local attempt_dir="$1"
    local attempt_num="$2"
    local attempt_committed="$3"
    local changed_files violations diff_stat attempt_diff_stat criteria
    local prompt_file output_file json_blob open_rejections_text
    local summary old_pwd="${PWD}"

    mkdir -p "${attempt_dir}"
    cd "${WORKTREE_PATH}" || return 1
    git fetch origin "${BASE_BRANCH}" --depth=1 2> /dev/null || true
    changed_files=$(git diff --name-only "origin/${BASE_BRANCH}...HEAD" -- . ':!.loop/' || true)
    if [[ -z ${changed_files} ]]; then
        printf '%s\n' "APPROVE" > "${attempt_dir}/verdict"
        printf '%s\n' "No meaningful changes outside .loop/" > "${attempt_dir}/reason"
        cd "${old_pwd}" || return 1
        return 0
    fi

    violations="$(collect_denylist_violations "${changed_files}")"
    if [[ -n ${violations} ]]; then
        local denylist_files
        denylist_files=$(printf '%b' "${violations}" | sed '/^$/d' | paste -sd, -)
        record_structured_reject "${attempt_dir}" "${attempt_num}" "${denylist_files}" \
            "Changed files match the denylist" \
            "Remove or revert denylisted paths from the branch diff" \
            "Denylist violation: ${denylist_files}"
        cd "${old_pwd}" || return 1
        return 0
    fi

    violations="$(collect_allowlist_violations "${changed_files}")"
    if [[ -n ${violations} ]]; then
        local allowlist_files
        allowlist_files=$(printf '%b' "${violations}" | sed '/^$/d' | paste -sd, -)
        record_structured_reject "${attempt_dir}" "${attempt_num}" "${allowlist_files}" \
            "Changed files are outside the allowlist" \
            "Limit changes to allowlisted paths or update the allowlist in the caller workflow" \
            "Allowlist violation: ${allowlist_files}"
        cd "${old_pwd}" || return 1
        return 0
    fi

    local agent_output_file="${attempt_dir}/agent-output.txt"
    local format_violations=""
    if [[ -f ${agent_output_file} ]] \
        && agent_report_skill_requires_format_check "${SKILL_NAME}"; then
        format_violations="$(validate_agent_report "${agent_output_file}" "${changed_files}" "${SKILL_NAME}" || true)"
        if [[ -n ${format_violations} ]]; then
            record_structured_reject "${attempt_dir}" "${attempt_num}" "${changed_files//$'\n'/,}" \
                "Agent report output format or Changes/Deferred consistency failed" \
                "Emit ## Overview, ## Summary (### Changes + ### Deferred), and ## Verification per loop PR body skill contract; reconcile with git diff before synthesis" \
                "${format_violations}"
            cd "${old_pwd}" || return 1
            return 0
        fi
    fi

    diff_stat=$(git diff --stat "origin/${BASE_BRANCH}...HEAD" -- . ':!.loop/' || true)
    attempt_diff_stat=""
    if [[ ${attempt_committed} == "true" ]] && git rev-parse HEAD~1 > /dev/null 2>&1; then
        attempt_diff_stat=$(git diff --stat HEAD~1...HEAD -- . ':!.loop/' || true)
    elif [[ ${attempt_num} -gt 1 ]]; then
        attempt_diff_stat="(no new commit in this attempt)"
    fi

    criteria="${AGENT_VERIFIER_CRITERIA}"
    if [[ -z ${criteria} ]]; then
        criteria="${PROMPT_VERIFIER_DEFAULT_CRITERIA}"
    fi
    if agent_report_skill_requires_format_check "${SKILL_NAME}"; then
        local format_criteria_file="${LIB_DIR}/agent_output_format_criteria.md"
        if [[ -f ${format_criteria_file} ]]; then
            criteria="${criteria}"$'\n\n'"$(cat "${format_criteria_file}")"
        fi
    fi

    prompt_file="${attempt_dir}/verifier-prompt.txt"
    {
        if [[ ${attempt_num} -gt 1 && "$(jq 'length' <<< "${OPEN_REJECTIONS_JSON}")" -gt 0 ]]; then
            open_rejections_text="$(format_open_rejections_for_prompt)"
            render_template "${PROMPT_VERIFIER_REGRESSION}" \
                attempt "${attempt_num}" \
                open_rejections "${open_rejections_text}" \
                attempt_delta "${attempt_diff_stat}"
            printf '\n\n'
        else
            render_template "${PROMPT_VERIFIER_INITIAL}" attempt "${attempt_num}"
            printf '\n\n'
        fi
        echo "## Task"
        echo ""
        printf '%s\n' "${PROMPT_VERIFIER_TASK}"
        echo ""
        echo "${criteria}"
        echo ""
        echo "## Input"
        echo ""
        echo "Skill: ${SKILL_NAME}"
        echo ""
        echo "### Branch Diff Stat"
        echo '```'
        echo "${diff_stat}"
        echo '```'
        echo ""
        if [[ -n ${VERIFIER_CONTEXT:-} ]]; then
            echo "### Additional Context"
            echo ""
            printf '%s\n' "${VERIFIER_CONTEXT}"
            echo ""
        fi
        echo "### Full Diff"
        echo "Review the checked-out branch for full context."
        echo ""
        write_verifier_output_contract
    } > "${prompt_file}"

    output_file="${attempt_dir}/verifier-output.txt"
    PROMPT="$(cat "${prompt_file}")"
    MAX_TURNS="${AGENT_VERIFIER_MAX_TURNS}"
    MODEL="${AGENT_VERIFIER_MODEL}"
    WORKING_DIRECTORY="${WORKTREE_PATH}"
    export PROMPT MAX_TURNS MODEL WORKING_DIRECTORY
    if ! run_agent_capture "${output_file}" "false"; then
        echo "::warning::Verifier agent exited non-zero"
    fi

    parse_verifier_output "${output_file}"
    verdict=$(printf '%s' "${verdict}" | tr '[:lower:]' '[:upper:]')
    if [[ -f ${output_file} ]]; then
        json_blob="$(extract_last_json_fence "${output_file}")"
        if [[ -n ${json_blob} ]]; then
            printf '%s\n' "${json_blob}" > "${attempt_dir}/verifier-verdict.json"
        fi
    fi
    if [[ ${parsed} != "true" ]]; then
        echo "::warning::Verifier verdict parse failed; defaulting to REJECT"
    fi
    if [[ ${verdict} != "APPROVE" ]]; then
        verdict="REJECT"
        [[ -n ${issue} ]] || issue="${reason}"
        [[ -n ${fix} ]] || fix="${reason}"
        files="$(infer_files_from_text "${issue} ${reason}" "${changed_files//$'\n'/,}")"
        summary="${reason}"
        record_structured_reject "${attempt_dir}" "${attempt_num}" "${files}" "${issue}" "${fix}" "${summary}"
    else
        printf '%s\n' "${verdict}" > "${attempt_dir}/verdict"
        printf '%s\n' "${reason}" > "${attempt_dir}/reason"
    fi
    cd "${old_pwd}" || return 1
}
