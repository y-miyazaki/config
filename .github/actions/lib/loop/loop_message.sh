#!/bin/bash
#######################################
# Description:
#   Convert the agent's message files (message.md, message_labels.json) to and from
#   the single-line message_json value that carries a delivery between jobs.
#
# Usage:
#   loop_action_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib/loop" && pwd)"
#   source "${loop_action_lib}/loop_message.sh"
#   loop_message_to_json "<dir>"
#   loop_message_from_json "<message_json>" "<dir>"
#
# Design Rules:
#   - Functions are pure: no globals are read or written
#   - The body is carried verbatim (jq --rawfile / -j), so it round-trips byte-identical
#   - message_labels.json is only read when message.md is present
#   - issues.json (delivery issue_create) travels as {"issues": [...]}; only a JSON array
#     is carried, anything else is ignored here (deliver_issue_create_run validates the shape)
#   - Invalid labels drop the whole delivery: a body without its labels would not match
#
# Output:
#   message_json on stdout (loop_message_to_json); warning/error annotations on stderr
#######################################

#######################################
# loop_message_from_json: Write message.md and message_labels.json from message_json
#
# Globals:
#   None
#
# Arguments:
#   $1 - message_json (JSON object with body and labels | empty)
#   $2 - dir to write into (created when missing)
#
# Outputs:
#   ::error:: annotation on stderr when message_json is not a JSON object
#
# Returns:
#   0 on success or empty input; 1 when message_json is not a JSON object
#
#######################################
function loop_message_from_json {
    local message_json="${1:-}"
    local dir="${2:-}"

    mkdir -p "${dir}"
    if [[ -z ${message_json} ]]; then
        return 0
    fi
    if ! jq -e 'type == "object"' > /dev/null 2>&1 <<< "${message_json}"; then
        echo "::error::message_json is not a JSON object" >&2
        return 1
    fi

    jq -j '.body // ""' <<< "${message_json}" > "${dir}/message.md"
    if jq -e '.labels != null' > /dev/null <<< "${message_json}"; then
        jq -c '.labels' <<< "${message_json}" > "${dir}/message_labels.json"
    fi
    if jq -e '.issues | type == "array"' > /dev/null 2>&1 <<< "${message_json}"; then
        jq -c '.issues' <<< "${message_json}" > "${dir}/issues.json"
    fi
}

#######################################
# loop_message_to_json: Build message_json from message.md and message_labels.json
#
# Globals:
#   None
#
# Arguments:
#   $1 - dir containing message.md and optionally message_labels.json
#
# Outputs:
#   One-line {"body": ..., "labels": ... | null, "issues"?: [...]} (or {"issues": [...]} alone)
#   on stdout; nothing when message.md is
#   missing or blank, or when message_labels.json is invalid (with a ::warning:: on stderr)
#
# Returns:
#   0 always
#
#######################################
function loop_message_to_json {
    local dir="${1:-}"
    local message_file="${dir}/message.md"
    local labels_file="${dir}/message_labels.json"
    local issues_file="${dir}/issues.json"
    local labels="null"
    local issues="null"

    if [[ -f ${issues_file} ]] && jq -e 'type == "array"' "${issues_file}" > /dev/null 2>&1; then
        issues="$(jq -c . "${issues_file}")"
    fi

    if [[ ! -f ${message_file} ]] || ! grep -q '[^[:space:]]' "${message_file}"; then
        if [[ ${issues} != "null" ]]; then
            jq -cn --argjson issues "${issues}" '{issues: $issues}'
        fi
        return 0
    fi

    if [[ -f ${labels_file} ]]; then
        if ! jq -e '
            type == "object"
            and ((.add // []) | type == "array" and all(type == "string"))
            and ((.remove // []) | type == "array" and all(type == "string"))
        ' "${labels_file}" > /dev/null 2>&1; then
            echo "::warning::message_labels.json is invalid; nothing is delivered" >&2
            return 0
        fi
        labels="$(jq -c . "${labels_file}")"
    fi

    jq -cn --rawfile body "${message_file}" --argjson labels "${labels}" --argjson issues "${issues}" \
        '{body: $body, labels: $labels} + (if $issues == null then {} else {issues: $issues} end)'
}
