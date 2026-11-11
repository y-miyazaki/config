#!/bin/bash
#######################################
# Description:
#   Scheduled-intake lister for the github-issue-triage loop: pick up to TRIAGE_LIST_LIMIT open
#   Issues created by the code-review loop that still need triage, and write them to GITHUB_OUTPUT
#   for a matrix job.
#
# Usage:
#   GITHUB_REPOSITORY=<owner/repo> GH_TOKEN=<token> GITHUB_OUTPUT=<file> \
#     bash scripts/self/loop/list_triage_issues.sh
#
# Design Rules:
#   - Repository-only script; Issues are read with the REST API (gh api), not gh issue list
#   - Reads at most TRIAGE_SCAN_LIMIT (200) Issues from the API, before any exclusion
#   - Candidate: open, not a pull request, label loop:code-review, no triage:* label, author
#     user.type == Bot, body (null counts as empty) contains the "<!-- code-review:fp:" marker
#   - Handled (excluded): the latest comment holding the triage marker has no newer comment from a
#     non-Bot author; no marker comment means not handled
#   - The comments API is called at most once per Issue, and only for Issues that pass the cheap
#     filters (labels, author, marker, run-log failure count)
#   - Failure count = run-log rows of this loop and Issue (target_key entity:issue:<N>) inside the
#     last TRIAGE_FAIL_WINDOW_DAYS days with outcome error or rejected; >= TRIAGE_FAIL_MAX excludes
#   - Order after all exclusions: last attempt (max run_id with outcome != skipped) ascending, Issues
#     with no attempt first, ties keep the API order (oldest created first); then TRIAGE_LIST_LIMIT
#   - A missing or unreadable run-log, non-JSON lines and rows without target_key never stop the run
#   - Issue titles and bodies are only passed to jq with --arg / --argjson
#   - Any failing gh api call exits 1; an empty result is never produced by a failure
#
# Output:
#   GITHUB_OUTPUT: issues=<compact JSON array of Issue numbers in selection order, e.g. [7,12,3]>, count=<n>;
#   "::notice" on stdout when nothing is selected
#
# Dependencies:
#   - bash, gh, jq, date (GNU)
#
# Environment:
#   GITHUB_REPOSITORY         owner/repo (required)
#   GH_TOKEN                  Token for gh api
#   GITHUB_OUTPUT             Output file (required)
#   RUN_LOG_FILE              Run-log path (default .loop/loop-run-log.md)
#   LOOP_NAME                 Loop name in the run-log and the comment marker (default github-issue-triage)
#   TRIAGE_LIST_LIMIT         Max Issues selected (default 3)
#   TRIAGE_SCAN_LIMIT         Max Issues read from the API (default 200)
#   TRIAGE_FAIL_WINDOW_DAYS   Failure window in days (default 7)
#   TRIAGE_FAIL_MAX           Failures in the window that exclude an Issue (default 3)
#   TRIAGE_NOW                ISO 8601 UTC "now" override for tests (default current time)
#######################################

set -euo pipefail

umask 027
export LC_ALL=C.UTF-8

#######################################
# fetch_open_issues: Print the open loop:code-review Issues, oldest first, capped at the scan limit
#
# Globals:
#   GITHUB_REPOSITORY, TRIAGE_SCAN_LIMIT
#
# Arguments:
#   None
#
# Outputs:
#   One JSON array on stdout; errors on stderr
#
# Returns:
#   0 on success; non-zero when gh api or jq fails
#
#######################################
function fetch_open_issues {
    gh api --paginate "repos/${GITHUB_REPOSITORY}/issues?labels=loop%3Acode-review&state=open&sort=created&direction=asc&per_page=100" \
        | jq -sc --argjson n "${TRIAGE_SCAN_LIMIT}" '[.[][]] | .[:$n]'
}

#######################################
# is_handled: Check whether the latest triage comment has no newer human comment
#
# Globals:
#   GITHUB_REPOSITORY, COMMENT_MARKER
#
# Arguments:
#   $1 - Issue number
#
# Outputs:
#   None; errors on stderr
#
# Returns:
#   0 when handled (exclude), 1 when not handled; exits 1 when the comments API fails
#
#######################################
function is_handled {
    local number="$1"
    local comments

    if ! comments="$(gh api --paginate "repos/${GITHUB_REPOSITORY}/issues/${number}/comments?per_page=100" | jq -sc '[.[][]]')"; then
        echo "::error::list_triage_issues: failed to read comments of issue #${number}" >&2
        exit 1
    fi
    jq -e --arg marker "${COMMENT_MARKER}" '
        ([.[] | select((.body // "") | contains($marker)) | .created_at] | max) as $m
        | $m != null and (any(.[]; (.user.type != "Bot") and (.created_at > $m)) | not)
    ' <<< "${comments}" > /dev/null
}

#######################################
# last_attempt: Print the latest non-skipped run_id of an Issue from the run-log rows
#
# Globals:
#   LOOP_NAME
#
# Arguments:
#   $1 - Run-log rows as one JSON array
#   $2 - Issue number
#
# Outputs:
#   run_id, or an empty string when there is no attempt
#
# Returns:
#   0
#
#######################################
function last_attempt {
    jq -r --arg loop "${LOOP_NAME}" --arg key "entity:issue:$2" '
        [.[] | select(.loop_name == $loop and .target_key == $key and .outcome != "skipped") | .run_id // empty] | max // ""
    ' <<< "$1"
}

#######################################
# load_run_log_rows: Print the JSON object rows of the run-log as one array
#
# Globals:
#   RUN_LOG_FILE
#
# Arguments:
#   None
#
# Outputs:
#   JSON array; [] when the file is missing, unreadable or has no JSON rows
#
# Returns:
#   0
#
#######################################
function load_run_log_rows {
    local line row rows="[]"

    if [[ -r ${RUN_LOG_FILE} ]]; then
        while IFS= read -r line || [[ -n ${line} ]]; do
            [[ ${line} != \{* ]] && continue
            row="$(jq -c 'select(type == "object")' <<< "${line}" 2> /dev/null)" || continue
            [[ -z ${row} ]] && continue
            rows="$(jq -c --argjson r "${row}" '. + [$r]' <<< "${rows}")"
        done < "${RUN_LOG_FILE}" 2> /dev/null || true
    fi
    printf '%s' "${rows}"
}

#######################################
# recent_failure_count: Print the error or rejected rows of an Issue since the cutoff
#
# Globals:
#   LOOP_NAME
#
# Arguments:
#   $1 - Run-log rows as one JSON array
#   $2 - Issue number
#   $3 - Cutoff run_id (ISO 8601 UTC)
#
# Outputs:
#   Count on stdout
#
# Returns:
#   0
#
#######################################
function recent_failure_count {
    jq -r --arg loop "${LOOP_NAME}" --arg key "entity:issue:$2" --arg cutoff "$3" '
        [.[] | select(.loop_name == $loop and .target_key == $key
            and (.outcome == "error" or .outcome == "rejected")
            and ((.run_id // "") >= $cutoff))] | length
    ' <<< "$1"
}

#######################################
# main: Select the Issues to triage and write them to GITHUB_OUTPUT
#
# Globals:
#   GITHUB_REPOSITORY, GITHUB_OUTPUT, RUN_LOG_FILE, LOOP_NAME, TRIAGE_*
#
# Arguments:
#   None
#
# Outputs:
#   issues and count in GITHUB_OUTPUT; log lines on stdout
#
# Returns:
#   0 on success (including no match); 1 when a gh api call or a required input fails
#
#######################################
function main {
    local issues candidates rows now cutoff number fails attempt selected="[]"

    : "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
    : "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
    RUN_LOG_FILE="${RUN_LOG_FILE:-.loop/loop-run-log.md}"
    LOOP_NAME="${LOOP_NAME:-github-issue-triage}"
    TRIAGE_LIST_LIMIT="${TRIAGE_LIST_LIMIT:-3}"
    TRIAGE_SCAN_LIMIT="${TRIAGE_SCAN_LIMIT:-200}"
    TRIAGE_FAIL_WINDOW_DAYS="${TRIAGE_FAIL_WINDOW_DAYS:-7}"
    TRIAGE_FAIL_MAX="${TRIAGE_FAIL_MAX:-3}"
    COMMENT_MARKER="<!-- ${LOOP_NAME}:v1 -->"

    if ! issues="$(fetch_open_issues)"; then
        echo "::error::list_triage_issues: failed to list issues" >&2
        return 1
    fi

    # Cheap filters first: not a PR, no triage:* label, Bot author, fingerprint marker in the body
    candidates="$(jq -c '
        [.[] | select(
            (has("pull_request") | not)
            and ((.user.type // "") == "Bot")
            and ((.body // "") | contains("<!-- code-review:fp:"))
            and (any(.labels[]?; .name == "loop:code-review"))
            and (any(.labels[]?; .name | startswith("triage:")) | not)
        ) | {number}]
    ' <<< "${issues}")"

    rows="$(load_run_log_rows)"
    now="${TRIAGE_NOW:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
    cutoff="$(date -u -d "${now} - ${TRIAGE_FAIL_WINDOW_DAYS} days" +%Y-%m-%dT%H:%M:%SZ)"

    while IFS= read -r number; do
        [[ -z ${number} ]] && continue
        fails="$(recent_failure_count "${rows}" "${number}" "${cutoff}")"
        if [[ ${fails} -ge ${TRIAGE_FAIL_MAX} ]]; then
            continue
        fi
        if is_handled "${number}"; then
            continue
        fi
        attempt="$(last_attempt "${rows}" "${number}")"
        selected="$(jq -c --argjson n "${number}" --arg a "${attempt}" \
            '. + [{number: $n, last_attempt: $a}]' <<< "${selected}")"
    done < <(jq -r '.[].number' <<< "${candidates}")

    # Oldest last attempt first (no attempt = ""), stable so ties keep the API order
    selected="$(jq -c --argjson n "${TRIAGE_LIST_LIMIT}" \
        'to_entries | sort_by([.value.last_attempt, .key]) | map(.value.number) | .[:$n]' <<< "${selected}")"

    {
        printf 'issues=%s\n' "${selected}"
        printf 'count=%s\n' "$(jq -r 'length' <<< "${selected}")"
    } >> "${GITHUB_OUTPUT}"
    if [[ ${selected} == "[]" ]]; then
        echo "::notice::list_triage_issues: no Issue needs triage"
    else
        echo "list_triage_issues: selected $(jq -r 'map(tostring) | join(",")' <<< "${selected}")"
    fi
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
