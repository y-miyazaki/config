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
# - Action-local only; not part of scripts/lib skill sync
#######################################

#######################################
# build_entity_target_prompt: Assemble implementer prompt for an entity target
#
# Globals:
#   None
#
# Arguments:
#   $1 - Skill name
#   $2 - Prompt instructions
#   $3 - Level (e.g. L1)
#   $4 - Delivery (e.g. none)
#   $5 - Detect result JSON string
#
# Outputs:
#   Prompt text on stdout
#
# Returns:
#   0 on success
#
#######################################
function build_entity_target_prompt {
    local skill_name="$1"
    local prompt_instructions="$2"
    local level="$3"
    local delivery="$4"
    local detect_result="$5"

    {
        echo "Run the ${skill_name} skill."
        echo ""
        echo "## Change Detection Result"
        echo "${detect_result}"
        if [[ -n ${prompt_instructions} ]]; then
            echo ""
            echo "## Instructions"
            echo "${prompt_instructions}"
        fi
        echo ""
        echo "## Constraints"
        echo "- level: ${level}"
        echo "- delivery: ${delivery}"
        echo "- may_edit: false"
        echo "- Do not modify repository files unless an explicit allowlist says so."
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
#   $3 - skill_name
#   $4 - prompt_instructions
#   $5 - level
#   $6 - delivery
#
# Outputs:
#   JSON array on stdout (empty when skip=true)
#
# Returns:
#   0 on success, 1 on invalid input
#
#######################################
function build_entity_target_matrix {
    local detect_path="$1"
    local loop_name="$2"
    local skill_name="$3"
    local prompt_instructions="$4"
    local level="$5"
    local delivery="$6"

    local detect_json skip event_name event_action comment_id
    local handoff_key verifier_context prompt_text target_json matrix_json
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

    event_name="$(jq -r '.result.event_name // "issues"' <<< "${detect_json}")"
    event_action="$(jq -r '.result.event_action // ""' <<< "${detect_json}")"
    comment_id="$(jq -r '.result.comment_id // empty' <<< "${detect_json}")"
    verifier_context="$(jq -r '.verifier_context // ""' <<< "${detect_json}")"
    default_branch="${GITHUB_REF_NAME:-main}"
    default_ref="${GITHUB_SHA:-}"

    prompt_text="$(build_entity_target_prompt \
        "${skill_name}" \
        "${prompt_instructions}" \
        "${level}" \
        "${delivery}" \
        "${detect_json}")"

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
            --argjson result_entity "$(jq -c '.result.entity // {}' <<< "${detect_json}")" \
            '
            {
              key: $key,
              entity: (
                if ($result_entity | type) == "object" and ($result_entity | length) > 0 then
                  $result_entity
                else
                  {handoff_key: $handoff_key}
                end
              ),
              event: (
                {name: $event_name, action: $event_action}
                + (if $comment_id == "" then {} else {comment_id: ($comment_id|tonumber? // $comment_id)} end)
              ),
              from: {ref: $from_ref},
              to: {branch: $to_branch},
              finalize: "none",
              loop_name: $loop_name
            }
            '
    )"

    matrix_json="$(
        jq -nc \
            --arg handoff_key "${handoff_key}" \
            --arg prompt "${prompt_text}" \
            --arg verifier_context "${verifier_context}" \
            --argjson target_json "${target_json}" \
            --argjson result "$(jq -c '.result // {}' <<< "${detect_json}")" \
            '{
              handoff_key: $handoff_key,
              prompt: $prompt,
              target_json: $target_json,
              verifier_context: $verifier_context,
              result: $result
            } | [.]'
    )" || return 1

    printf '%s\n' "${matrix_json}"
}
