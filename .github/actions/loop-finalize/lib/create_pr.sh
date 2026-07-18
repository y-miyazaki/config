#!/bin/bash
#######################################
# Description:
#   Create a GitHub pull request for loop-finalize open_pr strategy.
#   Resolves large JSON via handoff or inline env, composes the PR body,
#   and invokes gh pr create without passing oversized payloads on argv.
#
# Usage:
#   BRANCH=... GH_TOKEN=... GITHUB_REPOSITORY=... PR_BASE_BRANCH=... PR_TITLE=... \
#   NOTIFY_CONTEXT_JSON=... [LOOP_HANDOFF_DIR=... HANDOFF_KEY=... DETECT_RESULT_JSON=...] \
#   bash lib/create_pr.sh
#
# Design Rules:
#   - Caller supplies paths only via mktemp; no fixed payload filenames
#   - JSON file paths are passed to create_pr_body.sh as CLI arguments
#   - Writes url/number to GITHUB_OUTPUT when set
#
# Output:
#   Prints PR URL on stdout; optional GITHUB_OUTPUT keys url, number
#
# Dependencies:
#   - bash, gh, jq, handoff.sh, create_pr_body.sh
#######################################

set -euo pipefail

umask 027
export LC_ALL=C.UTF-8

#######################################
# Global variables
#######################################
BRANCH="${BRANCH:-}"
DETECT_RESULT_JSON="${DETECT_RESULT_JSON:-}"
GH_TOKEN="${GH_TOKEN:-}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"
HANDOFF_KEY="${HANDOFF_KEY:-}"
LABELS="${LABELS:-}"
LEVEL="${LEVEL:-}"
LOOP_HANDOFF_DIR="${LOOP_HANDOFF_DIR:-}"
NOTIFY_CONTEXT_JSON="${NOTIFY_CONTEXT_JSON:-}"
PR_BASE_BRANCH="${PR_BASE_BRANCH:-}"
PR_BODY="${PR_BODY:-}"
PR_TITLE="${PR_TITLE:-}"
SKIP_REASON="${SKIP_REASON:-}"
TARGET_JSON="${TARGET_JSON:-}"

#######################################
# main: Resolve payloads, compose body, create PR
#######################################
function main {
    local script_dir loop_detect_lib work_dir
    local detect_json_path notify_json_path body_path
    local -a body_args gh_args
    local composed url number

    : "${BRANCH:?BRANCH is required}"
    : "${GH_TOKEN:?GH_TOKEN is required}"
    : "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
    : "${PR_BASE_BRANCH:?PR_BASE_BRANCH is required}"
    : "${PR_TITLE:?PR_TITLE is required}"

    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    loop_detect_lib="$(cd "${script_dir}/../../loop-detect/lib" && pwd)"
    # shellcheck source=../../loop-detect/lib/handoff.sh
    # shellcheck disable=SC1091
    source "${loop_detect_lib}/handoff.sh"

    work_dir="$(mktemp -d)"
    # Capture path at trap-set time; local work_dir is out of scope on EXIT.
    # shellcheck disable=SC2064
    trap "rm -rf '${work_dir}'" EXIT

    detect_json_path="$(mktemp "${work_dir}/tmp.XXXXXX")"
    notify_json_path="$(mktemp "${work_dir}/tmp.XXXXXX")"
    body_path="$(mktemp "${work_dir}/tmp.XXXXXX")"

    loop_handoff_resolve_detect_result_json > "${detect_json_path}"
    printf '%s' "${NOTIFY_CONTEXT_JSON}" > "${notify_json_path}"

    body_args=(
        --detect-json-file "${detect_json_path}"
        --notify-json-file "${notify_json_path}"
    )

    export PR_BODY LEVEL SKIP_REASON TARGET_JSON
    composed="$(bash "${script_dir}/create_pr_body.sh" "${body_args[@]}")"

    gh_args=(
        --repo "${GITHUB_REPOSITORY}"
        --base "${PR_BASE_BRANCH}"
        --head "${BRANCH}"
        --title "${PR_TITLE}"
    )
    if [[ -n ${composed} ]]; then
        printf '%s' "${composed}" > "${body_path}"
        gh_args+=(--body-file "${body_path}")
    fi
    if [[ -n ${LABELS} ]]; then
        gh_args+=(--label "${LABELS}")
    fi

    url="$(gh pr create "${gh_args[@]}")"
    number="$(gh pr view "${url}" --json number --jq '.number')"
    printf '%s\n' "${url}"

    if [[ -n ${GITHUB_OUTPUT} ]]; then
        {
            echo "url=${url}"
            echo "number=${number}"
        } >> "${GITHUB_OUTPUT}"
    fi
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
