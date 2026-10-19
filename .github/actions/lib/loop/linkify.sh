#!/bin/bash
#######################################
# Description:
#   Link repository file paths in a loop message before it is posted. Agents write
#   the paths they cite as plain text or code spans, which GitHub does not make
#   clickable. This turns a path into a blob link only when the file exists at the
#   ref, so example paths and unknown tokens stay as written.
#
# Usage:
#   source linkify.sh
#   text="$(linkify_repo_text "${text}" "${ref}")"
#
# The matching itself lives in linkify.py (also used by render_pr_body.sh).
#
# Design Rules:
#   - A path is linked only when it is tracked at the ref (git ls-tree); a bare file
#     name (no directory) is linked only when exactly one tracked file has that name
#   - Existing markdown links, bare URLs, HTML comments, fenced code blocks, and
#     code spans that hold anything but a single path are left alone
#   - A `#L12` / `#L12-L20` or `:12` / `:12-20` suffix becomes a line anchor
#   - A no-op when the repository, the ref, or the tracked file list is unavailable
#   - The function never fails; on any error the original text is printed
#
# Output:
#   None (library file, sourced by other scripts)
#######################################

_LINKIFY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#######################################
# linkify_repo_text: Link tracked repository paths in message text
#
# Globals:
#   GITHUB_REPOSITORY - owner/repo
#   GITHUB_SERVER_URL - GitHub host (default https://github.com)
#
# Arguments:
#   $1 - Message text
#   $2 - Full commit SHA (or ref) to read paths from and to link at
#
# Outputs:
#   Text with tracked paths replaced by markdown links, on stdout
#
# Returns:
#   0 always
#
# Usage:
#   text="$(linkify_repo_text "${text}" "$(git rev-parse HEAD)")"
#
#######################################
function linkify_repo_text {
    local text="${1:-}"
    local ref="${2:-}"
    local files

    if [[ -z ${text} || -z ${ref} || -z ${GITHUB_REPOSITORY:-} ]] \
        || ! files="$(git ls-tree -r --name-only "${ref}" 2> /dev/null)" || [[ -z ${files} ]]; then
        printf '%s' "${text}"
        return 0
    fi

    BASE="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY}" REF="${ref}" PATHS="${files}" PLAIN=1 BARE=1 \
        python3 -I "${_LINKIFY_DIR}/linkify.py" <<< "${text}" 2> /dev/null || printf '%s' "${text}"
}
