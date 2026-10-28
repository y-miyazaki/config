#!/bin/bash
#######################################
# Description:
#   Prune loop state targets by 30-day retention rules.
#   Spec: docs/superpowers/specs/2026-07-17-loop-state-targets-retention-design.md
#
# Usage:
#   source lib/prune_targets.sh
#   prune_targets_by_retention /path/to/state.json
#   # or: prune_targets_json "$(cat state.json)" > out.json
#
# Design Rules:
#   - Never delete non-pull_request keys (watch / integration:*)
#   - Delete pull_request:* when terminal + aged + no pending
#   - Cooldown watch reject fields after 30 days
#   - Fail-safe: missing/invalid last_run → keep entry
#   - Terminal outcomes are read through normalize_outcome, so persisted old names
#     (pr-closed) are treated exactly like the new names (pr_closed)
#
# Dependencies:
#   - bash, jq, lib/loop/outcome.sh
#######################################

# Error handling: exit on error, unset variable, or failed pipeline
set -euo pipefail

# Secure defaults
umask 027
export LC_ALL=C.UTF-8

# shellcheck source=../../lib/loop/outcome.sh
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib/loop" && pwd)/outcome.sh"

#######################################
# prune_targets_cutoff_date: UTC YYYY-MM-DD for 30-day window
#
# Globals:
#   None
#
# Arguments:
#   None
#
# Outputs:
#   Cutoff date to stdout
#
# Returns:
#   0 on success
#
#######################################
function prune_targets_cutoff_date {
    date -u -d '30 days ago' +%Y-%m-%d 2> /dev/null || date -u -v-30d +%Y-%m-%d
}

#######################################
# prune_targets_outcome_map: Map each persisted target outcome to its current name
#
# Globals:
#   None
#
# Arguments:
#   $1 - State JSON string with a .targets object
#
# Outputs:
#   JSON object {"<persisted outcome>": "<normalize_outcome result>"} to stdout
#
# Returns:
#   0 on success
#
#######################################
function prune_targets_outcome_map {
    local state_json="$1"
    local outcome map='{}'

    while IFS= read -r outcome; do
        map="$(jq -c --arg k "${outcome}" --arg v "$(normalize_outcome "${outcome}")" '. + {($k): $v}' <<< "${map}")"
    done < <(jq -r '[.targets[] | objects | .outcome | strings] | unique | .[]' <<< "${state_json}")
    printf '%s' "${map}"
}

#######################################
# prune_targets_json: Apply retention to state JSON on stdin/arg
#
# Globals:
#   None
#
# Arguments:
#   $1 - Optional state JSON string (default: read stdin when empty and sourced carefully)
#        Prefer passing JSON as $1.
#
# Outputs:
#   Pruned state JSON to stdout
#
# Returns:
#   0 on success
#
#######################################
function prune_targets_json {
    local state_json="${1:-}"
    local cutoff outcome_map

    if [[ -z ${state_json} ]]; then
        printf '%s' '{"targets":{}}'
        return 0
    fi
    if ! jq -e . > /dev/null 2>&1 <<< "${state_json}"; then
        printf '%s' "${state_json}"
        return 0
    fi
    if ! jq -e '(.targets | type) == "object"' > /dev/null 2>&1 <<< "${state_json}"; then
        printf '%s' "${state_json}"
        return 0
    fi

    cutoff="$(prune_targets_cutoff_date)"
    outcome_map="$(prune_targets_outcome_map "${state_json}")"

    jq -c --arg cutoff "${cutoff}" --argjson outcome_map "${outcome_map}" '
      def terminal:
        ((.outcome | strings | $outcome_map[.]) // null) as $o
        | $o == "rejected" or $o == "pr_closed";
      def aged:
        ((.last_run // "") | length) >= 10
        and ((.last_run[0:10]) < $cutoff);
      def has_pending:
        (.pending | type) == "object";

      .targets |= with_entries(
        if (.value | has_pending) then
          .
        elif (.key | startswith("pull_request:")) then
          if (.value | terminal) and (.value | aged) then
            empty
          else
            .
          end
        else
          # Watch / integration keys: never delete; cooldown reject fields
          if (.value | terminal) and (.value | aged) then
            .value |= (
              del(.last_reject_reason, .open_rejections)
              | .consecutive_failures = 0
            )
          else
            .
          end
        end
      )
    ' <<< "${state_json}"
}

#######################################
# prune_targets_by_retention: Prune targets in a state file in place
#
# Globals:
#   None
#
# Arguments:
#   $1 - Path to state JSON file
#
# Outputs:
#   None
#
# Returns:
#   0 always (fail-safe); file updated when prune changes content
#######################################
function prune_targets_by_retention {
    local state_file="${1:?state_file required}"
    local raw raw_norm pruned

    [[ -f ${state_file} ]] || return 0
    raw="$(cat "${state_file}")"
    raw_norm="$(jq -c . <<< "${raw}" 2> /dev/null || printf '%s' "${raw}")"
    pruned="$(prune_targets_json "${raw}")" || return 0
    if [[ ${pruned} != "${raw_norm}" ]]; then
        printf '%s\n' "${pruned}" > "${state_file}"
    fi
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    if [[ $# -lt 1 ]]; then
        echo "Usage: $0 <state.json>" >&2
        exit 1
    fi
    prune_targets_by_retention "$1"
fi
