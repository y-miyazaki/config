#!/bin/bash
#######################################
# Description: Artifact-oriented job handoff for loop detect → execute
#
# Usage: source "${LIB_DIR}/handoff.sh"
#
# Output:
# - None (library file; writes bundle files under a handoff directory)
#
# Design Rules:
# - Large per-target payloads live under payloads/<sanitized-key>.json
# - target_matrix job output carries handoff_key only (no inlined result)
# - Execute/finalize jobs download the artifact and resolve by handoff_key
#######################################

#######################################
# Global variables
#######################################
LOOP_HANDOFF_VERSION=1

#######################################
# loop_handoff_init_bundle: Create an empty handoff bundle directory
#
# Globals:
#   None
#
# Arguments:
#   $1 - Handoff bundle directory
#
# Outputs:
#   Echoes handoff directory on stdout
#
# Returns:
#   0 on success
#
#######################################
function loop_handoff_init_bundle {
    local handoff_dir="$1"

    rm -rf "${handoff_dir}"
    mkdir -p "${handoff_dir}/payloads"
    printf '%s' "${handoff_dir}"
}

#######################################
# loop_handoff_payload_path: Resolve payload file path for a target key
#
# Globals:
#   None
#
# Arguments:
#   $1 - Handoff bundle directory
#   $2 - Target key
#
# Outputs:
#   Absolute or relative payload path on stdout
#
# Returns:
#   0 on success
#
#######################################
function loop_handoff_payload_path {
    local handoff_dir="$1"
    local target_key="$2"
    printf '%s/payloads/%s.json' "${handoff_dir}" "$(loop_handoff_sanitize_key "${target_key}")"
}

#######################################
# loop_handoff_read_detect_result: Read detect result JSON from a payload
#
# Globals:
#   None
#
# Arguments:
#   $1 - Handoff bundle directory
#   $2 - Target key
#
# Outputs:
#   Detect result JSON to stdout; non-zero when payload is missing
#
# Returns:
#   0 on success
#
#######################################
function loop_handoff_read_detect_result {
    local handoff_dir="$1"
    local target_key="$2"
    local payload

    payload="$(loop_handoff_read_payload "${handoff_dir}" "${target_key}")" || return 1
    jq -c '.result // {}' <<< "${payload}"
}

#######################################
# loop_handoff_read_payload: Read raw payload JSON for a target key
#
# Globals:
#   None
#
# Arguments:
#   $1 - Handoff bundle directory
#   $2 - Target key
#
# Outputs:
#   Payload JSON to stdout; non-zero when missing or invalid
#
# Returns:
#   0 on success
#
#######################################
function loop_handoff_read_payload {
    local handoff_dir="$1"
    local target_key="$2"
    local payload_file

    payload_file="$(loop_handoff_payload_path "${handoff_dir}" "${target_key}")"
    if [[ ! -f ${payload_file} ]]; then
        return 1
    fi
    if ! jq -e . "${payload_file}" > /dev/null 2>&1; then
        return 1
    fi
    cat "${payload_file}"
}

#######################################
# loop_handoff_read_verifier_context: Read verifier markdown from a payload
#
# Globals:
#   None
#
# Arguments:
#   $1 - Handoff bundle directory
#   $2 - Target key
#
# Outputs:
#   Verifier context markdown on stdout (may be empty)
#
# Returns:
#   0 on success
#
#######################################
function loop_handoff_read_verifier_context {
    local handoff_dir="$1"
    local target_key="$2"
    local payload

    payload="$(loop_handoff_read_payload "${handoff_dir}" "${target_key}")" || return 1
    jq -r '.verifier_context // ""' <<< "${payload}"
}

#######################################
# loop_handoff_resolve_detect_result_json: Resolve detect JSON from env
#
# Globals:
#   DETECT_RESULT_JSON - Inline detect JSON from workflow input (read)
#   HANDOFF_KEY - Target key for artifact payload lookup (read)
#   LOOP_HANDOFF_DIR - Downloaded handoff bundle directory (read)
#
# Arguments:
#   None
#
# Outputs:
#   Detect result JSON on stdout
#
# Returns:
#   0 on success
#
#######################################
function loop_handoff_resolve_detect_result_json {
    local inline="${DETECT_RESULT_JSON:-"{}"}"

    if [[ -n ${inline} && ${inline} != "{}" ]] && jq -e . <<< "${inline}" > /dev/null 2>&1; then
        printf '%s' "${inline}"
        return 0
    fi

    if [[ -n ${LOOP_HANDOFF_DIR:-} && -n ${HANDOFF_KEY:-} ]]; then
        loop_handoff_read_detect_result "${LOOP_HANDOFF_DIR}" "${HANDOFF_KEY}" && return 0
    fi

    printf '%s' '{}'
}

#######################################
# loop_handoff_sanitize_key: Map target key to a safe filename stem
#
# Globals:
#   None
#
# Arguments:
#   $1 - Target key (e.g. integration:main)
#
# Outputs:
#   Sanitized stem on stdout
#
# Returns:
#   0 on success
#
#######################################
function loop_handoff_sanitize_key {
    local target_key="$1"
    printf '%s' "${target_key}" | tr ':/' '__'
}

#######################################
# loop_handoff_write_bundle: Write manifest and payloads for all candidates
#
# Globals:
#   LOOP_HANDOFF_VERSION - Manifest schema version (read)
#
# Arguments:
#   $1 - Handoff bundle directory
#   $2.. - Full candidate JSON object strings
#
# Outputs:
#   None
#
# Returns:
#   0 on success
#
#######################################
function loop_handoff_write_bundle {
    local handoff_dir="$1"
    shift
    local -a candidates=("$@")
    local candidate target_key
    local -a keys=()

    loop_handoff_init_bundle "${handoff_dir}" > /dev/null

    for candidate in "${candidates[@]}"; do
        [[ -z ${candidate} ]] && continue
        target_key="$(jq -r '.target_json.key // empty' <<< "${candidate}")"
        [[ -z ${target_key} ]] && continue
        if ! loop_handoff_write_candidate_payload "${handoff_dir}" "${candidate}"; then
            echo "::error::loop-handoff: failed to write payload for ${target_key}" >&2
            return 1
        fi
        keys+=("${target_key}")
    done

    printf '%s\n' "${keys[@]}" | jq -Rs --argjson version "${LOOP_HANDOFF_VERSION}" '
        split("\n")
        | map(select(length > 0))
        | {version: $version, keys: .}
    ' > "${handoff_dir}/manifest.json"
}

#######################################
# loop_handoff_write_candidate_payload: Write one candidate payload file
#
# Globals:
#   None
#
# Arguments:
#   $1 - Handoff bundle directory
#   $2 - Full candidate JSON object string
#
# Outputs:
#   None
#
# Returns:
#   0 on success, non-zero on invalid candidate
#
#######################################
function loop_handoff_write_candidate_payload {
    local handoff_dir="$1"
    local candidate="$2"
    local target_key payload_file result_file jq_stderr verifier_context

    if ! jq -e . <<< "${candidate}" > /dev/null 2>&1; then
        return 1
    fi

    target_key="$(jq -r '.target_json.key // empty' <<< "${candidate}")"
    if [[ -z ${target_key} ]]; then
        return 1
    fi

    payload_file="$(loop_handoff_payload_path "${handoff_dir}" "${target_key}")"
    result_file="$(mktemp)"
    jq_stderr="$(mktemp)"
    jq -c '.result // {}' <<< "${candidate}" > "${result_file}"
    verifier_context="$(jq -r '.verifier_context // ""' <<< "${candidate}")"

    jq -n \
        --arg handoff_key "${target_key}" \
        --arg verifier_context "${verifier_context}" \
        --slurpfile result "${result_file}" \
        '{handoff_key: $handoff_key, result: $result[0], verifier_context: $verifier_context}' \
        > "${payload_file}" 2> "${jq_stderr}" || {
        rm -f "${result_file}" "${jq_stderr}"
        return 1
    }

    rm -f "${result_file}" "${jq_stderr}"
    return 0
}
