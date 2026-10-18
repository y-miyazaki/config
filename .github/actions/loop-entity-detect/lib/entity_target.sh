#!/bin/bash
#######################################
# Description: Build single-element target_matrix for entity-loop callers
#
# Usage: source "${LIB_DIR}/entity_target.sh"
#
# This library provides:
# - build_entity_target_matrix — detect JSON → slim target_matrix array
#
# Design Rules:
# - Pure Bash + jq (no gh)
# - One GitHub entity per matrix (skip → empty array)
# - skip=false requires result.handoff_key and result.entity.kind (issue | pr)
# - target_json.entity is {handoff_key} merged with result.entity; no finalize key
# - The matrix row carries the key only in target_json.key (no duplicate handoff_key)
# - Action-local only; not part of scripts/lib skill sync
#######################################

_ENTITY_TARGET_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_entity_loop_action_lib="$(cd "${_ENTITY_TARGET_LIB_DIR}/../../lib/loop" && pwd)"
if ! declare -f emit_loop_constraints > /dev/null 2>&1; then
    # shellcheck source=../../lib/loop/build_constraints.sh disable=SC1091
    source "${_entity_loop_action_lib}/build_constraints.sh"
fi

#######################################
# build_entity_target_prompt: Assemble maker prompt for an entity target
#
# Globals:
#   None
#
# Arguments:
#   $1 - Skill name
#   $2 - Prompt instructions
#   $3 - Level (L1 | L2 | L3; agent_edit_allowed is derived from it)
#   $4 - Delivery (none | pr_create | pr_push)
#   $5 - Detect result JSON string
#   $6 - agent_edit_target (fix | report; empty at L1)
#   $7 - agent_edit_allowlist csv (empty at L1; ** = unrestricted)
#
# Outputs:
#   Prompt text on stdout
#
# Returns:
#   0 on success; 1 when the constraints block cannot be emitted (invalid level or agent_edit_target)
#
#######################################
function build_entity_target_prompt {
    local agent_maker_skill_name="$1"
    local agent_maker_instructions="$2"
    local level="$3"
    local delivery="$4"
    local detect_result="$5"
    local agent_edit_target="$6"
    local agent_edit_allowlist="$7"

    {
        echo "Run the ${agent_maker_skill_name} skill."
        echo ""
        echo "## Change Detection Result"
        echo "${detect_result}"
        if [[ -n ${agent_maker_instructions} ]]; then
            echo ""
            echo "## Instructions"
            echo "${agent_maker_instructions}"
        fi
        echo ""
        echo "## Run Context"
        echo "level: ${level}"
        echo "delivery: ${delivery}"
        echo ""
        emit_loop_constraints "${level}" "${agent_edit_target}" "${agent_edit_allowlist}" "" || return 1
    }
}

#######################################
# build_entity_target_matrix: Build slim target_matrix from entity detect JSON
#
# Globals:
#   GITHUB_REF_NAME, GITHUB_SHA - Default branch/ref when detect omits them
#
# Arguments:
#   $1 - Path to detect JSON file
#   $2 - loop_name
#   $3 - agent_maker_skill_name
#   $4 - agent_maker_instructions
#   $5 - level (L1 | L2 | L3)
#   $6 - delivery (none | pr_create | pr_push)
#   $7 - agent_edit_target (fix | report; empty at L1)
#   $8 - agent_edit_allowlist csv (empty at L1; ** = unrestricted)
#
# Outputs:
#   JSON array on stdout (empty when skip=true); error message on stderr
#
# Returns:
#   0 on success; 1 on invalid input (missing handoff_key, result.entity.kind not issue|pr,
#   or a prompt that cannot be built)
#
#######################################
function build_entity_target_matrix {
    local detect_path="$1"
    local loop_name="$2"
    local agent_maker_skill_name="$3"
    local agent_maker_instructions="$4"
    local level="$5"
    local delivery="$6"
    local agent_edit_target="$7"
    local agent_edit_allowlist="$8"

    local detect_json skip event_name event_action comment_id
    local handoff_key entity_kind result_entity verifier_context prompt_text target_json matrix_json
    local default_branch default_ref

    if [[ -z ${detect_path} || ! -f ${detect_path} ]]; then
        echo "build_entity_target_matrix: detect JSON path required" >&2
        return 1
    fi
    if ! detect_json="$(jq -c . "${detect_path}" 2> /dev/null)"; then
        echo "build_entity_target_matrix: invalid detect JSON" >&2
        return 1
    fi

    skip="$(jq -r '.skip // false' <<< "${detect_json}")"
    if [[ ${skip} == "true" ]]; then
        printf '%s\n' '[]'
        return 0
    fi

    handoff_key="$(jq -r '.result.handoff_key // empty' <<< "${detect_json}")"
    if [[ -z ${handoff_key} ]]; then
        echo "build_entity_target_matrix: result.handoff_key required when skip=false" >&2
        return 1
    fi

    result_entity="$(jq -c '.result.entity | if type == "object" then . else {} end' <<< "${detect_json}")"
    entity_kind="$(jq -r '.kind // empty' <<< "${result_entity}")"
    if [[ ${entity_kind} != "issue" && ${entity_kind} != "pr" ]]; then
        echo "build_entity_target_matrix: result.entity.kind must be issue or pr when skip=false (got: ${entity_kind:-empty})" >&2
        return 1
    fi

    event_name="$(jq -r '.result.event_name // "issues"' <<< "${detect_json}")"
    event_action="$(jq -r '.result.event_action // ""' <<< "${detect_json}")"
    comment_id="$(jq -r '.result.comment_id // empty' <<< "${detect_json}")"
    verifier_context="$(jq -r '.verifier_context // ""' <<< "${detect_json}")"
    default_branch="${GITHUB_REF_NAME:-main}"
    default_ref="${GITHUB_SHA:-}"

    prompt_text="$(build_entity_target_prompt \
        "${agent_maker_skill_name}" \
        "${agent_maker_instructions}" \
        "${level}" \
        "${delivery}" \
        "${detect_json}" \
        "${agent_edit_target}" \
        "${agent_edit_allowlist}")" || return 1

    target_json="$(
        jq -nc \
            --arg key "${handoff_key}" \
            --arg handoff_key "${handoff_key}" \
            --arg event_name "${event_name}" \
            --arg event_action "${event_action}" \
            --arg comment_id "${comment_id}" \
            --arg from_ref "${default_ref}" \
            --arg to_branch "${default_branch}" \
            --arg loop_name "${loop_name}" \
            --argjson result_entity "${result_entity}" \
            '
            {
              key: $key,
              entity: ({handoff_key: $handoff_key} + $result_entity),
              event: (
                {name: $event_name, action: $event_action}
                + (if $comment_id == "" then {} else {comment_id: ($comment_id|tonumber? // $comment_id)} end)
              ),
              from: {branch: $to_branch, ref: $from_ref},
              to: {branch: $to_branch},
              loop_name: $loop_name
            }
            '
    )"

    matrix_json="$(
        jq -nc \
            --arg prompt "${prompt_text}" \
            --arg verifier_context "${verifier_context}" \
            --argjson target_json "${target_json}" \
            --argjson result "$(jq -c '.result // {}' <<< "${detect_json}")" \
            '{
              prompt: $prompt,
              target_json: $target_json,
              verifier_context: $verifier_context,
              result: $result
            } | [.]'
    )" || return 1

    printf '%s\n' "${matrix_json}"
}
