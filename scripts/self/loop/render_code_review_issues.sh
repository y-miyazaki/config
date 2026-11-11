#!/bin/bash
#######################################
# Description:
#   loop finalize_script for the code-review loop: read the maker's findings.json from the
#   agent branch, re-verify every finding's evidence against the changed lines of the loop
#   range, and write the surviving findings as issues.json for Deliver Message.
#
# Usage:
#   VERDICT=APPROVE EXECUTE_BRANCH=<branch> TARGET_JSON=<json> LOOP_MESSAGE_DIR=<dir> \
#     bash scripts/self/loop/render_code_review_issues.sh
#
# Design Rules:
#   - Repository-only script (code-review is Claude Code's built-in skill, not a package skill)
#   - Act only when VERDICT is APPROVE; any other verdict writes nothing and exits 0, so
#     Write State still records rejected and the circuit breaker works
#   - An agent branch that is missing on origin writes nothing and exits 0 (Deliver Message
#     then fails on the missing issues.json)
#   - Fail closed for APPROVE: a missing or unreachable target_json.from.since / from.ref, a
#     findings.json that is not an array, or a malformed finding exits 1 and writes nothing
#   - The range comes from TARGET_JSON (set by detect), never from the checkout or state file
#   - A finding is kept only when its evidence lines overlap lines added or changed by
#     git diff since..ref in that file; the others are dropped and counted in the step summary
#   - A finding whose title (256) or body (60000, with the evidence line) is too long is dropped
#   - evidence.path must be a regular file at from.ref; a directory such as "." would match every
#     changed line of the range, so such a finding is dropped
#   - A stale issues.json in LOOP_MESSAGE_DIR is removed on APPROVE, so only verified findings
#     can reach Deliver Message
#   - issues.json is built in a temp file and moved into place (no partial file on failure)
#
# Output:
#   ${LOOP_MESSAGE_DIR}/issues.json = [{"title","body","fingerprint"}]; log lines on stdout;
#   dropped findings appended to GITHUB_STEP_SUMMARY
#
# Dependencies:
#   - bash, git, jq; cwd is the repository checkout with an origin remote
#
# Environment:
#   VERDICT            Checker verdict; only APPROVE renders
#   EXECUTE_BRANCH     Agent branch holding .loop-code-review/findings.json
#   TARGET_JSON        Loop target JSON with from.since and from.ref
#   LOOP_MESSAGE_DIR   Directory that receives issues.json (required)
#   GITHUB_STEP_SUMMARY Step summary file (optional)
#######################################

set -euo pipefail

umask 027
export LC_ALL=C.UTF-8

readonly REPORT_PATH=".loop-code-review/findings.json"
readonly MAX_TITLE=256
readonly MAX_BODY=60000

#######################################
# changed_ranges: Print the added or changed line ranges of one file in since..ref
#
# Globals:
#   None
#
# Arguments:
#   $1 - since commit
#   $2 - ref commit
#   $3 - Repository-relative path
#
# Outputs:
#   One "<start> <end>" line per hunk with new lines (pure deletions are skipped)
#
# Returns:
#   0 on success; non-zero when git diff fails
#
#######################################
function changed_ranges {
    local since="$1"
    local ref="$2"
    local path="$3"
    local header start count

    GIT_LITERAL_PATHSPECS=1 git diff --unified=0 --no-renames --no-color "${since}" "${ref}" -- "${path}" \
        | while IFS= read -r header; do
            [[ ${header} =~ ^@@\ -[0-9]+(,[0-9]+)?\ \+([0-9]+)(,([0-9]+))?\ @@ ]] || continue
            start="${BASH_REMATCH[2]}"
            count="${BASH_REMATCH[4]:-1}"
            if [[ ${count} -gt 0 ]]; then
                printf '%s %s\n' "${start}" "$((start + count - 1))"
            fi
        done
}

#######################################
# evidence_overlaps: Check whether evidence lines overlap any changed range
#
# Globals:
#   None
#
# Arguments:
#   $1 - Newline-separated "<start> <end>" ranges
#   $2 - Evidence start line
#   $3 - Evidence end line
#
# Outputs:
#   None
#
# Returns:
#   0 when the evidence overlaps a range; 1 otherwise
#
#######################################
function evidence_overlaps {
    local ranges="$1"
    local ev_start="$2"
    local ev_end="$3"
    local start end

    while read -r start end; do
        [[ -n ${start} ]] || continue
        if [[ ${ev_start} -le ${end} && ${ev_end} -ge ${start} ]]; then
            return 0
        fi
    done <<< "${ranges}"
    return 1
}

#######################################
# main: Re-verify findings and write issues.json when VERDICT is APPROVE
#
# Globals:
#   VERDICT, EXECUTE_BRANCH, TARGET_JSON, LOOP_MESSAGE_DIR, GITHUB_STEP_SUMMARY
#
# Arguments:
#   None
#
# Outputs:
#   ${LOOP_MESSAGE_DIR}/issues.json; log lines on stdout; errors on stderr
#
# Returns:
#   0 on success, a non-APPROVE verdict, or a missing agent branch; 1 on a fail-closed check
#
#######################################
function main {
    local branch="${EXECUTE_BRANCH:-}"
    local message_dir="${LOOP_MESSAGE_DIR:-}"
    local since ref report count i finding path ev_start ev_end title body fingerprint ranges
    local kept="[]" dropped=0 reason out_file
    local -a reasons=()

    if [[ ${VERDICT:-} != "APPROVE" ]]; then
        echo "render_code_review_issues: VERDICT=${VERDICT:-} (not APPROVE); nothing to render"
        return 0
    fi
    if [[ -z ${message_dir} ]]; then
        echo "::error::render_code_review_issues: LOOP_MESSAGE_DIR is not set" >&2
        return 1
    fi
    rm -f "${message_dir}/issues.json"
    if [[ ! ${branch} =~ ^[A-Za-z0-9/_.-]+$ || ${branch} == *..* ]]; then
        echo "::warning::render_code_review_issues: EXECUTE_BRANCH is missing or invalid; nothing to render"
        return 0
    fi
    if ! git fetch --no-tags --quiet origin "+refs/heads/${branch}:refs/remotes/origin/${branch}" > /dev/null 2>&1; then
        echo "::warning::render_code_review_issues: agent branch ${branch} is not on origin; nothing to render"
        return 0
    fi

    since="$(jq -r '.from.since // empty | strings' <<< "${TARGET_JSON:-}" 2> /dev/null || true)"
    ref="$(jq -r '.from.ref // empty | strings' <<< "${TARGET_JSON:-}" 2> /dev/null || true)"
    if [[ -z ${since} || -z ${ref} ]]; then
        echo "::error::render_code_review_issues: target_json.from.since and from.ref are required" >&2
        return 1
    fi
    if ! git cat-file -e "${since}^{commit}" 2> /dev/null || ! git cat-file -e "${ref}^{commit}" 2> /dev/null; then
        echo "::error::render_code_review_issues: from.since or from.ref is not a commit in this checkout" >&2
        return 1
    fi

    if ! report="$(git show "origin/${branch}:${REPORT_PATH}" 2> /dev/null)"; then
        echo "::error::render_code_review_issues: ${REPORT_PATH} is missing on ${branch}" >&2
        return 1
    fi
    if ! jq -e '
        type == "array" and all(
            type == "object"
            and (.title | type == "string" and length > 0)
            and (.body | type == "string")
            and (.fingerprint | type == "string" and length > 0)
            and (.evidence | type == "object")
            and (.evidence.path | type == "string" and length > 0)
            and (.evidence.start_line | type == "number" and . >= 1 and . == floor)
            and (.evidence.end_line | type == "number" and . >= 1 and . == floor)
            and (.evidence.start_line <= .evidence.end_line)
        )' <<< "${report}" > /dev/null 2>&1; then
        echo "::error::render_code_review_issues: ${REPORT_PATH} is not an array of well-formed findings" >&2
        return 1
    fi
    while IFS= read -r path; do
        if [[ ${path} == /* || ${path} == *$'\n'* || /${path}/ == */../* ]]; then
            echo "::error::render_code_review_issues: unsafe evidence path in ${REPORT_PATH}" >&2
            return 1
        fi
    done < <(jq -r '.[].evidence.path' <<< "${report}")

    count="$(jq -r 'length' <<< "${report}")"
    for ((i = 0; i < count; i++)); do
        finding="$(jq -c --argjson i "${i}" '.[$i]' <<< "${report}")"
        title="$(jq -r '.title' <<< "${finding}")"
        body="$(jq -r '.body' <<< "${finding}")"
        fingerprint="$(jq -r '.fingerprint' <<< "${finding}")"
        path="$(jq -r '.evidence.path' <<< "${finding}")"
        ev_start="$(jq -r '.evidence.start_line' <<< "${finding}")"
        ev_end="$(jq -r '.evidence.end_line' <<< "${finding}")"
        body+=$'\n\n'"Evidence: \`${path}\` lines ${ev_start}-${ev_end} (range \`${since:0:12}..${ref:0:12}\`)"

        if [[ ${#title} -gt ${MAX_TITLE} || ${#body} -gt ${MAX_BODY} ]]; then
            dropped=$((dropped + 1))
            reasons+=("- ${title:0:80}: title or body over the length limit")
            continue
        fi
        if [[ "$(git cat-file -t "${ref}:${path}" 2> /dev/null || true)" != "blob" ]]; then
            dropped=$((dropped + 1))
            reasons+=("- ${title:0:80}: evidence path ${path} is not a file at the range head")
            continue
        fi
        ranges="$(changed_ranges "${since}" "${ref}" "${path}")" || {
            echo "::error::render_code_review_issues: git diff failed for ${path}" >&2
            return 1
        }
        if ! evidence_overlaps "${ranges}" "${ev_start}" "${ev_end}"; then
            dropped=$((dropped + 1))
            reasons+=("- ${title:0:80}: evidence ${path}:${ev_start}-${ev_end} does not overlap the changed lines of the range")
            continue
        fi
        kept="$(jq -c --arg t "${title}" --arg b "${body}" --arg f "${fingerprint}" \
            '. + [{title: $t, body: $b, fingerprint: $f}]' <<< "${kept}")"
    done

    if [[ ${dropped} -gt 0 && -n ${GITHUB_STEP_SUMMARY:-} ]]; then
        {
            printf 'code-review: dropped %s of %s findings after the evidence check\n' "${dropped}" "${count}"
            printf '%s\n' "${reasons[@]}"
        } >> "${GITHUB_STEP_SUMMARY}"
    fi
    echo "render_code_review_issues: findings=${count} kept=$(jq -r 'length' <<< "${kept}") dropped=${dropped}"

    mkdir -p "${message_dir}"
    out_file="$(mktemp)"
    printf '%s' "${kept}" > "${out_file}"
    mv "${out_file}" "${message_dir}/issues.json"
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
