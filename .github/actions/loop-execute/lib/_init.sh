#!/bin/bash
# shellcheck disable=SC1091
#######################################
# Description: All-in-one library loader for loop-execute scripts
#
# Usage: source "${SCRIPT_DIR}/lib/_init.sh"
#
# Output:
# - None (library file, sourced by other scripts)
#
# Design Rules:
# - Must be idempotent (guard against multiple loading)
# - Must source libraries in dependency order
#######################################

if [[ ${_LOOP_LIB_LOADED:-} == "true" ]]; then
    return 0
fi
_LOOP_LIB_LOADED=true

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./common.sh
source "${LIB_DIR}/common.sh"
# shellcheck source=./rejections.sh
source "${LIB_DIR}/rejections.sh"
# shellcheck source=./paths.sh
source "${LIB_DIR}/paths.sh"
# shellcheck source=./agent.sh
source "${LIB_DIR}/agent.sh"
# shellcheck source=./usage.sh
source "${LIB_DIR}/usage.sh"
# shellcheck source=./verifier.sh
source "${LIB_DIR}/verifier.sh"
