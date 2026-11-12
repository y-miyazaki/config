#!/bin/bash
#######################################
# Description:
#   Plain-text helpers shared by loop notify and PR body renderers.
#
# Usage:
#   source text.sh
#   text_truncate TEXT MAX
#
# Output:
#   None (library file, sourced by other scripts)
#
# Design Rules:
#   - Pure functions: no I/O besides stdout
#######################################

#######################################
# text_truncate: Truncate text to max length
#
# Globals:
#   None
#
# Arguments:
#   $1 - Input text
#   $2 - Maximum length
#
# Outputs:
#   Truncated text to stdout
#
# Returns:
#   0 on success
#
#######################################
function text_truncate {
    local text="$1"
    local max="$2"
    if [[ ${#text} -le ${max} ]]; then
        printf '%s' "${text}"
    else
        printf '%s' "${text:0:max}"
    fi
}
