#!/bin/bash
#######################################
# Description: Build and publish the loop-handoff artifact name
#
# Usage: bash handoff_name.sh   (env: GITHUB_RUN_ID, HANDOFF_ARTIFACT_SUFFIX, GITHUB_OUTPUT)
#        source handoff_name.sh
#
# This library provides:
# - build_handoff_artifact_name — run id + suffix → loop-handoff-<run_id><suffix>
#
# Design Rules:
# - Suffix must match ^[A-Za-z0-9._-]*$ (empty keeps loop-handoff-<run_id>)
# - Single source of truth: the upload step reads the step output
# - Action-local only; not part of scripts/lib skill sync
#######################################

set -euo pipefail

#######################################
# build_handoff_artifact_name: Print the handoff artifact name
#
# Arguments:
#   $1 - Run id
#   $2 - Suffix (optional; letters, digits, dot, underscore, hyphen)
#
# Returns:
#   0 on success; 1 on missing run id or invalid suffix
#######################################
function build_handoff_artifact_name {
    # Pin the C locale so the character class is ASCII-only (not locale collation)
    local LC_ALL=C
    local run_id="${1:-}"
    local suffix="${2:-}"
    if [[ -z ${run_id} ]]; then
        echo "::error::run id is required for the handoff artifact name" >&2
        return 1
    fi
    if [[ ! ${suffix} =~ ^[A-Za-z0-9._-]*$ ]] || [[ ${suffix} == *$'\n'* ]]; then
        echo "::error::handoff_artifact_suffix must match ^[A-Za-z0-9._-]*\$" >&2
        return 1
    fi
    printf 'loop-handoff-%s%s\n' "${run_id}" "${suffix}"
}

#######################################
# main: Write artifact_name to GITHUB_OUTPUT
#######################################
function main {
    local name
    name="$(build_handoff_artifact_name "${GITHUB_RUN_ID:-}" "${HANDOFF_ARTIFACT_SUFFIX:-}")" || return 1
    echo "artifact_name=${name}" >> "${GITHUB_OUTPUT}"
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
