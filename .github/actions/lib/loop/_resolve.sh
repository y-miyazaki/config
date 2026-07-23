#!/bin/bash
#######################################
# Description: Resolve .github/actions/lib/loop directory
#
# Usage: source "${...}/_resolve.sh"
#
# Output:
# - None (sets LOOP_ACTION_LIB_DIR when sourced)
#
# Design Rules:
# - GITHUB_ACTION_PATH is authoritative on runners (remote action pin)
# - BASH_SOURCE fallback supports Bats and local script sourcing
#######################################

if [[ -z ${LOOP_ACTION_LIB_DIR:-} ]]; then
    if [[ -n ${GITHUB_ACTION_PATH:-} ]]; then
        LOOP_ACTION_LIB_DIR="$(cd "${GITHUB_ACTION_PATH}/../lib/loop" && pwd)"
    else
        LOOP_ACTION_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    fi
fi
