#!/bin/bash
#######################################
# Description:
#   Derive a git-ref-safe slug from a loop target key for per-target agent
#   branch names.
#
# Usage:
#   source target_slug.sh
#   target_slug TARGET_KEY
#
# Output:
#   None (library file, sourced by other scripts)
#
# Design Rules:
#   - Slug is the part of the key after the first '#' (whole key when absent)
#   - Characters outside [A-Za-z0-9._-] become '-' (so ':' becomes '-')
#   - Leading and trailing dots are stripped; '..' collapses to '.'; a '.lock'
#     ending becomes '-lock'; the readable part is cut to 32 chars
#   - '-' plus the first 8 hex of sha256 of the WHOLE key is always appended so
#     keys that normalize alike (issue:1-2 vs issue-1:2) stay distinct
#   - Result is at most 41 chars and valid as a branch name suffix
#   - Empty key prints nothing and returns 0
#######################################

#######################################
# target_slug: Print <slug>-<hash8> for a target key
#
# Globals:
#   None
#
# Arguments:
#   $1 - Target key (may be empty)
#
# Outputs:
#   STDOUT: slug with hash suffix, or nothing for an empty key
#
# Returns:
#   0 always
#######################################
function target_slug {
    local key="${1:-}"
    local hash slug

    [[ -n ${key} ]] || return 0

    hash="$(printf '%s' "${key}" | sha256sum | cut -c1-8)"
    slug="${key#*#}"
    slug="${slug//[^A-Za-z0-9._-]/-}"
    while [[ ${slug} == *..* ]]; do
        slug="${slug//../.}"
    done
    slug="${slug:0:32}"
    while [[ ${slug} == .* ]]; do
        slug="${slug#.}"
    done
    while [[ ${slug} == *. ]]; do
        slug="${slug%.}"
    done
    if [[ ${slug} == *.lock ]]; then
        slug="${slug%.lock}-lock"
    fi

    if [[ -n ${slug} ]]; then
        printf '%s-%s\n' "${slug}" "${hash}"
    else
        printf '%s\n' "${hash}"
    fi
}
