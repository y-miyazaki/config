#!/bin/bash
#######################################
# Description: Per-target items helpers for loop-detect (result.items)
#
# Usage: source "${LIB_DIR}/items.sh"
#
# Output:
# - None (library file)
#
# Design Rules:
# - Pure helpers; values reach jq only through --arg / --argjson
# - order_items_by_last_run depends on read_target_state (state.sh)
#######################################

#######################################
# extract_items: Print the compact items array from a detect result
#
# Globals:
#   None
#
# Arguments:
#   $1 - Detect result JSON
#
# Outputs:
#   Compact JSON array on stdout; nothing when items is absent;
#   ::error:: on stderr for invalid or duplicate keys
#
# Returns:
#   0 on success, 1 on invalid or duplicate keys
#
#######################################
function extract_items {
    local detect_result="$1"
    local items_json key

    if ! jq -e 'type == "object" and .items != null' <<< "${detect_result}" > /dev/null 2>&1; then
        return 0
    fi
    if ! items_json="$(jq -ce '.items | if type == "array" then . else error("items must be an array") end' <<< "${detect_result}" 2> /dev/null)"; then
        echo "::error::loop-detect: items must be an array" >&2
        return 1
    fi

    if ! jq -e 'all(.[]; type == "object")' <<< "${items_json}" > /dev/null 2>&1; then
        echo "::error::loop-detect: every item must be an object" >&2
        return 1
    fi

    # Non-string keys and keys containing a newline become "" so that the
    # line-oriented loop below cannot be fooled; "" fails validate_item_key.
    while IFS= read -r key; do
        if ! validate_item_key "${key}"; then
            echo "::error::loop-detect: invalid item key '${key}'" >&2
            return 1
        fi
    done < <(jq -r '.[] | .key | if type == "string" and (contains("\n") | not) then . else "" end' <<< "${items_json}")

    local duplicate
    duplicate="$(jq -r '[.[].key] | group_by(.) | map(select(length > 1) | .[0]) | first // empty' <<< "${items_json}")"
    if [[ -n ${duplicate} ]]; then
        echo "::error::loop-detect: duplicate item key '${duplicate}'" >&2
        return 1
    fi

    printf '%s\n' "${items_json}"
}

#######################################
# item_result_json: Build the per-item detect result for one item
#
# Globals:
#   None
#
# Arguments:
#   $1 - Item JSON (key, optional context)
#
# Outputs:
#   {"status":"ok","skip":false,"result":{<context>,"key":"<key>"}} on stdout;
#   ::error:: on stderr when context is present but not an object
#
# Returns:
#   0 on success, 1 when context is not an object
#
#######################################
function item_result_json {
    local item_json="$1"

    if ! jq -e '(.context // {}) | type == "object"' <<< "${item_json}" > /dev/null 2>&1; then
        echo "::error::loop-detect: item context must be an object" >&2
        return 1
    fi
    jq -c '{status: "ok", skip: false, result: ((.context // {}) + {key: .key})}' <<< "${item_json}"
}

#######################################
# item_target_key: Print the state target key for an item
#
# Globals:
#   None
#
# Arguments:
#   $1 - Integration branch
#   $2 - Item key
#
# Outputs:
#   integration:<branch>#<key> on stdout
#
# Returns:
#   0 on success
#
#######################################
function item_target_key {
    printf 'integration:%s#%s\n' "$1" "$2"
}

#######################################
# order_items_by_last_run: Sort items by target state last_run, oldest first
# last_run is compared as a raw ISO-8601 UTC string (lexicographic order).
# read_target_state may migrate and write the state file in place.
#
# Globals:
#   None (reads and may migrate the state file via read_target_state)
#
# Arguments:
#   $1 - State file path
#   $2 - Integration branch
#   $3 - Items JSON array
#
# Outputs:
#   Compact JSON array on stdout; items without state first, ties keep input order
#
# Returns:
#   0 on success
#
#######################################
function order_items_by_last_run {
    local state_file="$1"
    local branch="$2"
    local items_json="$3"
    local key target_state last_run
    local annotated='[]'

    while IFS= read -r key; do
        target_state="$(read_target_state "${state_file}" "$(item_target_key "${branch}" "${key}")" "${branch}")"
        last_run="$(jq -r '.last_run // ""' <<< "${target_state}")"
        annotated="$(jq -c --arg key "${key}" --arg last_run "${last_run}" '. + [{key: $key, last_run: $last_run}]' <<< "${annotated}")"
    done < <(jq -r '.[].key' <<< "${items_json}")

    jq -c --argjson annotated "${annotated}" '
        [to_entries[] | . as $e | {item: $e.value, last_run: $annotated[$e.key].last_run}]
        | sort_by(.last_run)
        | map(.item)
    ' <<< "${items_json}"
}

#######################################
# validate_item_key: Check an item key against the key rules
#
# Globals:
#   None
#
# Arguments:
#   $1 - Item key
#
# Outputs:
#   None
#
# Returns:
#   0 when valid, 1 otherwise
#
#######################################
function validate_item_key {
    local key="$1"
    local LC_ALL=C

    [[ -n ${key} && ${#key} -le 64 ]] || return 1
    [[ ${key} =~ ^[A-Za-z0-9._-]+(:[A-Za-z0-9._-]+)*$ ]] || return 1
    [[ ${key} != *..* && ${key} != .* && ${key} != *. ]] || return 1
    return 0
}
