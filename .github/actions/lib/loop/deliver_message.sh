#!/bin/bash
#######################################
# Description:
#   Deliver the message an agent or finalize_script left in LOOP_MESSAGE_DIR as the
#   one GitHub write of a loop run: an Issue comment (issue_comment) or a COMMENT
#   PR review (pr_review), with the loop marker first and Meta and the footer last.
#   Labels from message_labels.json are applied first, limited to the caller allowlist.
#   delivery issue_create instead opens one Issue per finding in issues.json
#   (deliver_issue_create), skipping findings that already have an Issue.
#
# Usage:
#   source created_by.sh
#   source loop_meta.sh
#   source failure_record.sh
#   source deliver_message.sh
#   deliver_loop_message
#
# Output:
#   None (library file, sourced by other scripts)
#
# Design Rules:
#   - Message files are untrusted: their shape is checked again; an invalid file
#     delivers nothing (like a missing one) and lowers the outcome to unchanged
#   - Missing or blank text writes nothing to GitHub (no labels either) and writes
#     outcome=unchanged; a successful post writes no outcome
#   - The target number comes from target_json, and its kind must match the delivery
#   - Labels are applied before the post, so a failed label call leaves no stale text
#   - The review event is always COMMENT; only HTTP 422 with inline comments retries,
#     once, with fallback_body and no comments
#   - gh stderr is only passed to loop_failure_record (which redacts it), never printed
#   - Every failure records failure_stage deliver_message and returns 1
#   - issue_create: issues.json is validated fail closed (array of {title, body,
#     fingerprint}); duplicates (open and closed Issues carrying every allowlist label,
#     and repeats within the run) are dropped BEFORE the limit is applied, so a backlog
#     of already-filed findings never crowds out new ones; findings cut by the limit
#     are listed in the step summary and not carried over; creation stops at the first
#     failure; the label set always comes from the caller allowlist, never the agent
#   - A finding whose finished body (marker, sanitized text, Meta) would pass GitHub's
#     65536-character limit is dropped and listed in the step summary, not failed: a
#     failure would block the cursor and repeat every run
#######################################

_DELIVER_MESSAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_LOOP_DELIVER_MESSAGE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./ensure_labels.sh disable=SC1091
source "${_LOOP_DELIVER_MESSAGE_LIB_DIR}/ensure_labels.sh"

#######################################
# apply_loop_message_labels: Add and remove the allowlisted labels on an Issue or PR
#
# Globals:
#   GITHUB_REPOSITORY - owner/name
#   GH_TOKEN - Token for gh
#   LOOP_FAILURE_FILE - Failure record path
#
# Arguments:
#   $1 - Issue or PR number
#   $2 - message_labels.json path (already validated; may be missing)
#   $3 - Newline-separated label allowlist
#
# Outputs:
#   Warning annotations on stdout for labels outside the allowlist
#
# Returns:
#   0 on success (404 on DELETE counts as success); 1 on a failed gh call (recorded)
#
# Usage:
#   apply_loop_message_labels 12 "${dir}/message_labels.json" "${FINALIZE_LABEL_ALLOWLIST}"
#
#######################################
function apply_loop_message_labels {
    local number="$1"
    local labels_file="$2"
    local allowlist="${3:-}"
    local requested filtered rejected add_file err encoded
    local -a add_names=() encoded_names=()

    if [[ ! -f ${labels_file} ]]; then
        return 0
    fi
    requested="$(jq -c '{add: (.add // []), remove: (.remove // [])}' "${labels_file}")"
    if [[ $(jq -r '(.add + .remove) | length' <<< "${requested}") -eq 0 ]]; then
        return 0
    fi
    if [[ -z ${allowlist//[[:space:]]/} ]]; then
        echo "::warning::finalize_label_allowlist is empty; labels in message_labels.json are ignored"
        return 0
    fi

    filtered="$(jq -c --arg allow "${allowlist}" '
        ($allow | split("\n") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))) as $a
        | {
            add: [.add[] | select(IN($a[]))],
            remove: [.remove[] | select(IN($a[]))],
            rejected: [(.add + .remove)[] | select(IN($a[]) | not)]
        }' <<< "${requested}")"
    rejected="$(jq -c '.rejected' <<< "${filtered}")"
    if [[ ${rejected} != "[]" ]]; then
        # JSON-encoded so a label name cannot inject a workflow command
        echo "::warning::Labels not in finalize_label_allowlist are skipped: ${rejected}"
    fi

    if [[ $(jq -r '.add | length' <<< "${filtered}") -gt 0 ]]; then
        mapfile -t add_names < <(jq -r '.add[]' <<< "${filtered}")
        if ! err="$(ensure_repo_labels "${add_names[@]}" 2>&1)"; then
            fail_loop_message "${err}"
            return 1
        fi
        add_file="$(mktemp)"
        jq -c '{labels: .add}' <<< "${filtered}" > "${add_file}"
        if ! err="$(gh api -X POST "repos/${GITHUB_REPOSITORY}/issues/${number}/labels" --input "${add_file}" 2>&1 > /dev/null)"; then
            rm -f "${add_file}"
            fail_loop_message "Failed to add labels on #${number}: ${err}"
            return 1
        fi
        rm -f "${add_file}"
    fi

    # @uri per element: names never reach the shell unencoded (no newline or slash splits)
    mapfile -t encoded_names < <(jq -r '.remove[] | @uri' <<< "${filtered}")
    for encoded in "${encoded_names[@]}"; do
        if ! err="$(gh api -X DELETE "repos/${GITHUB_REPOSITORY}/issues/${number}/labels/${encoded}" 2>&1 > /dev/null)"; then
            if [[ ${err} == *"HTTP 404"* ]]; then
                continue
            fi
            fail_loop_message "Failed to remove label ${encoded} on #${number}: ${err}"
            return 1
        fi
    done
    return 0
}

#######################################
# build_loop_message_body: Put the marker first (when missing) and Meta and the footer last
#
# Globals:
#   None
#
# Arguments:
#   $1 - Message text (already trimmed)
#   $2 - Loop marker (<!-- <loop_name>:v1 -->)
#   $3 - Meta block from build_loop_meta_block
#
# Outputs:
#   The body on stdout
#
# Returns:
#   0 always
#
# Usage:
#   body="$(build_loop_message_body "${text}" "${marker}" "${meta_block}")"
#
#######################################
function build_loop_message_body {
    local text="$1"
    local marker="$2"
    local meta_block="$3"

    if [[ ${text} != "${marker}"* ]]; then
        printf '%s\n' "${marker}"
    fi
    printf '%s\n\n%s\n' "${text}" "${meta_block}"
}

#######################################
# loop_message_link_ref: Commit to read and link repository paths at
#
# Description:
#   A PR review links at the reviewed commit (commit_id in review.json) when that
#   commit is available locally; everything else links at the checked-out HEAD.
#
# Globals:
#   None
#
# Arguments:
#   $1 - LOOP_MESSAGE_DIR
#
# Outputs:
#   Full commit SHA on stdout; empty when none can be resolved
#
# Returns:
#   0 always
#
#######################################
function loop_message_link_ref {
    local dir="${1:-}"
    local commit_id=""

    if [[ -f "${dir}/review.json" ]]; then
        commit_id="$(jq -r '.commit_id // empty | strings' "${dir}/review.json" 2> /dev/null || true)"
    fi
    if [[ ${commit_id} =~ ^[0-9a-f]{40}$ ]]; then
        git cat-file -e "${commit_id}^{commit}" 2> /dev/null \
            || git fetch --no-tags --quiet --depth=1 origin "${commit_id}" > /dev/null 2>&1 || true
    fi
    if [[ ${commit_id} =~ ^[0-9a-f]{40}$ ]] && git cat-file -e "${commit_id}^{commit}" 2> /dev/null; then
        printf '%s' "${commit_id}"
        return 0
    fi
    git rev-parse HEAD 2> /dev/null || true
}

#######################################
# deliver_loop_message: Deliver message.md or review.json, with labels, as one GitHub write
#
# Globals:
#   DELIVERY - issue_comment | issue_create | pr_review (anything else does nothing)
#   LOOP_MESSAGE_DIR - Directory holding message.md / review.json / message_labels.json
#   LOOP_NAME - Loop name for the marker
#   TARGET_JSON - Target JSON with entity.handoff_key or key
#   FINALIZE_LABEL_ALLOWLIST - Newline-separated label allowlist
#   OUTCOME - Planned outcome (Meta row)
#   VERDICT - Checker verdict (Meta row)
#   AGENT_ENGINE - Engine slug (Meta row)
#   USAGE_JSON - usage_json (Meta rows)
#   RUN_URL - Loop run URL (Meta row)
#   GITHUB_REPOSITORY - owner/name
#   GH_TOKEN - Token for gh
#   LOOP_FAILURE_FILE - Failure record path
#   GITHUB_OUTPUT - Receives outcome=unchanged when nothing is delivered
#
# Arguments:
#   None
#
# Outputs:
#   Notice, warning, and error annotations on stdout
#
# Returns:
#   0 on success or when there is nothing to deliver; 1 on failure (recorded)
#
# Usage:
#   deliver_loop_message
#
#######################################
function deliver_loop_message {
    local delivery="${DELIVERY:-}"
    local dir="${LOOP_MESSAGE_DIR:-}"
    local marker="<!-- ${LOOP_NAME:-}:v1 -->"
    local labels_file="${dir}/message_labels.json"
    local text="" fallback="" number meta_block out_file rc link_ref

    case "${delivery}" in
        issue_create)
            deliver_issue_create
            return $?
            ;;
        issue_comment)
            if [[ -f "${dir}/message.md" ]]; then
                text="$(cat "${dir}/message.md")"
            fi
            ;;
        pr_review)
            if [[ -f "${dir}/review.json" ]]; then
                if ! jq -e '
                    type == "object"
                    and ((.body // "") | type == "string")
                    and ((.fallback_body // "") | type == "string")
                    and ((.commit_id // "") | type == "string")
                    and ((.comments // []) | type == "array")
                ' "${dir}/review.json" > /dev/null 2>&1; then
                    echo "::warning::review.json is invalid; nothing is delivered"
                else
                    text="$(jq -r '.body // ""' "${dir}/review.json")"
                    fallback="$(jq -r '.fallback_body // ""' "${dir}/review.json")"
                fi
            fi
            ;;
        *)
            return 0
            ;;
    esac

    # Trim surrounding whitespace so blank text delivers nothing
    text="${text#"${text%%[![:space:]]*}"}"
    text="${text%"${text##*[![:space:]]}"}"
    fallback="${fallback#"${fallback%%[![:space:]]*}"}"
    fallback="${fallback%"${fallback##*[![:space:]]}"}"

    if [[ -n ${text} ]]; then
        link_ref="$(loop_message_link_ref "${dir}")"
        text="$(python3 -I "${_DELIVER_MESSAGE_DIR}/linkify.py" --tracked --ref "${link_ref}" <<< "${text}" 2> /dev/null || printf '%s' "${text}")"
        if [[ -n ${fallback} ]]; then
            fallback="$(python3 -I "${_DELIVER_MESSAGE_DIR}/linkify.py" --tracked --ref "${link_ref}" <<< "${fallback}" 2> /dev/null || printf '%s' "${fallback}")"
        fi
    fi

    if [[ -n ${text} && -f ${labels_file} ]] && ! jq -e '
        type == "object"
        and ((.add // []) | type == "array" and all(type == "string"))
        and ((.remove // []) | type == "array" and all(type == "string"))
    ' "${labels_file}" > /dev/null 2>&1; then
        echo "::warning::message_labels.json is invalid; nothing is delivered"
        text=""
    fi

    if [[ -z ${text} ]]; then
        echo "::notice title=loop-deliver::No ${delivery} text to deliver; outcome is unchanged"
        if [[ -n ${GITHUB_OUTPUT:-} ]]; then
            echo "outcome=unchanged" >> "${GITHUB_OUTPUT}"
        fi
        return 0
    fi

    if ! number="$(loop_message_target_number "${delivery}" "${TARGET_JSON:-}")"; then
        fail_loop_message "target_json handoff key does not match delivery ${delivery}"
        return 1
    fi

    loop_meta_reset
    meta_block="$(build_loop_meta_block "${OUTCOME:-}" "${VERDICT:-}" "" "${AGENT_ENGINE:-}" "${USAGE_JSON:-}" "${RUN_URL:-}")"

    if ! apply_loop_message_labels "${number}" "${labels_file}" "${FINALIZE_LABEL_ALLOWLIST:-}"; then
        return 1
    fi

    out_file="$(mktemp)"
    if [[ ${delivery} == "issue_comment" ]]; then
        build_loop_message_body "${text}" "${marker}" "${meta_block}" > "${out_file}"
        rc=0
        post_loop_issue_comment "${number}" "${out_file}" || rc=$?
    else
        jq -c \
            --arg body "$(build_loop_message_body "${text}" "${marker}" "${meta_block}")" \
            --arg fallback "${fallback}" \
            --arg fallback_body "$(build_loop_message_body "${fallback}" "${marker}" "${meta_block}")" \
            '{
                body: $body,
                comments: (.comments // []),
                fallback_body: (if $fallback == "" then "" else $fallback_body end)
            } + (if (.commit_id // "") != "" then {commit_id: .commit_id} else {} end)' \
            "${dir}/review.json" > "${out_file}"
        rc=0
        post_loop_pr_review "${number}" "${out_file}" || rc=$?
    fi
    rm -f "${out_file}"
    return "${rc}"
}

#######################################
# fail_loop_message: Record a deliver_message failure and annotate it without gh stderr
#
# Globals:
#   LOOP_FAILURE_FILE - Failure record path (skipped when unset)
#
# Arguments:
#   $1 - Failure message (may hold gh stderr; redacted by loop_failure_record)
#
# Outputs:
#   Error annotation on stdout
#
# Returns:
#   0 always
#
# Usage:
#   fail_loop_message "Failed to post: ${err}"
#
#######################################
function fail_loop_message {
    local message="$1"

    echo "::error::Deliver Message failed (failure_stage=deliver_message; see the loop-finalize failure_message output)"
    if [[ -n ${LOOP_FAILURE_FILE:-} ]]; then
        loop_failure_record "deliver_message" "${message}" "${LOOP_FAILURE_FILE}"
    fi
}

#######################################
# loop_message_target_number: Read the Issue/PR number for a delivery from target_json
#
# Globals:
#   None
#
# Arguments:
#   $1 - delivery (issue_comment | pr_review)
#   $2 - target_json (entity.handoff_key, else key: entity:issue:<n> | entity:pr:<n>)
#
# Outputs:
#   The number on stdout
#
# Returns:
#   0 when the key is valid and its kind matches the delivery; 1 otherwise
#
# Usage:
#   number="$(loop_message_target_number issue_comment "${TARGET_JSON}")"
#
#######################################
function loop_message_target_number {
    local delivery="$1"
    local target_json="${2:-}"
    local key expected

    case "${delivery}" in
        issue_comment) expected="issue" ;;
        pr_review) expected="pr" ;;
        *) return 1 ;;
    esac
    key="$(jq -r '(.entity.handoff_key // .key) // empty | strings' <<< "${target_json}" 2> /dev/null || true)"
    if [[ ${key} =~ ^entity:(issue|pr):([1-9][0-9]*)$ && ${BASH_REMATCH[1]} == "${expected}" ]]; then
        printf '%s' "${BASH_REMATCH[2]}"
        return 0
    fi
    return 1
}

#######################################
# post_loop_issue_comment: Post one Issue comment from a body file
#
# Globals:
#   GITHUB_REPOSITORY - owner/name
#   GH_TOKEN - Token for gh
#   LOOP_FAILURE_FILE - Failure record path
#
# Arguments:
#   $1 - Issue number
#   $2 - Body file (marker, text, Meta, footer)
#
# Outputs:
#   Notice annotation on success
#
# Returns:
#   0 on success; 1 on failure (recorded)
#
# Usage:
#   post_loop_issue_comment 12 "${body_file}"
#
#######################################
function post_loop_issue_comment {
    local number="$1"
    local body_file="$2"
    local err

    if ! err="$(gh issue comment "${number}" --repo "${GITHUB_REPOSITORY}" --body-file "${body_file}" 2>&1 > /dev/null)"; then
        fail_loop_message "Failed to post the loop comment on #${number}: ${err}"
        return 1
    fi
    echo "::notice title=loop-deliver::Posted the loop comment on #${number}"
    return 0
}

#######################################
# post_loop_pr_review: Post one COMMENT review; retry once without comments on HTTP 422
#
# Globals:
#   GITHUB_REPOSITORY - owner/name
#   GH_TOKEN - Token for gh
#   LOOP_FAILURE_FILE - Failure record path
#
# Arguments:
#   $1 - PR number
#   $2 - Review file {body, commit_id?, comments, fallback_body} (bodies already carry
#        the marker, Meta, and footer; fallback_body is empty when none was given)
#
# Outputs:
#   Notice or warning annotations
#
# Returns:
#   0 on success; 1 on failure (recorded)
#
# Usage:
#   post_loop_pr_review 7 "${review_file}"
#
#######################################
function post_loop_pr_review {
    local number="$1"
    local review_file="$2"
    local payload err

    payload="$(mktemp)"
    jq -c '{body, comments, event: "COMMENT"} + (if .commit_id then {commit_id} else {} end)' \
        "${review_file}" > "${payload}"
    if err="$(gh api -X POST "repos/${GITHUB_REPOSITORY}/pulls/${number}/reviews" --input "${payload}" 2>&1 > /dev/null)"; then
        rm -f "${payload}"
        echo "::notice title=loop-deliver::Posted the COMMENT review on PR #${number}"
        return 0
    fi

    # Only a 422 (an inline position GitHub rejects) is fixed by moving the findings
    # to the body; auth, rate-limit, and server errors would fail the same way again.
    if [[ ${err} == *"HTTP 422"* ]] && jq -e '(.comments | length) > 0 and .fallback_body != ""' "${review_file}" > /dev/null; then
        echo "::warning::The review with inline comments was rejected (HTTP 422) on PR #${number}; retrying with fallback_body"
        jq -c '{body: .fallback_body, event: "COMMENT"} + (if .commit_id then {commit_id} else {} end)' \
            "${review_file}" > "${payload}"
        if err="$(gh api -X POST "repos/${GITHUB_REPOSITORY}/pulls/${number}/reviews" --input "${payload}" 2>&1 > /dev/null)"; then
            rm -f "${payload}"
            echo "::notice title=loop-deliver::Posted the COMMENT review on PR #${number} (fallback_body)"
            return 0
        fi
    fi
    rm -f "${payload}"
    fail_loop_message "Failed to post the review on PR #${number}: ${err}"
    return 1
}

#######################################
# issue_fingerprint_hash: Hash a finding fingerprint for the Issue marker
#
# Globals:
#   None
#
# Arguments:
#   $1 - Loop name
#   $2 - Fingerprint chosen by the agent
#
# Outputs:
#   First 16 hex digits of sha256(loop_name + newline + fingerprint) on stdout
#
# Returns:
#   0 always
#
# Usage:
#   hash="$(issue_fingerprint_hash code-review "a.sh:f:null")"
#
#######################################
function issue_fingerprint_hash {
    local loop_name="$1"
    local fingerprint="$2"

    printf '%s\n%s' "${loop_name}" "${fingerprint}" | sha256sum | cut -c1-16
}

#######################################
# sanitize_issue_body: Defuse text an agent could use to forge markers or notify people
#
# Description:
#   Every HTML comment opener becomes "&lt;!--" (so no marker, including the loop's own
#   fp marker, can be forged or hidden in the body) and a zero-width space follows every
#   "@" that starts a mention (so no user or team is notified).
#
# Globals:
#   None
#
# Arguments:
#   $1 - Loop name (kept for the call contract; the neutralization covers every marker)
#   $2 - Body text
#
# Outputs:
#   The sanitized body on stdout
#
# Returns:
#   0 always
#
# Usage:
#   body="$(sanitize_issue_body code-review "${raw_body}")"
#
#######################################
function sanitize_issue_body {
    local zwsp=$'\xe2\x80\x8b'
    local body="$2"

    body="${body//<!--/&lt;!--}"
    sed -E "s/@([A-Za-z0-9_])/@${zwsp}\\1/g" <<< "${body}"
}

#######################################
# issue_create_summary: Append one line to the step summary when it is available
#
# Globals:
#   GITHUB_STEP_SUMMARY - Step summary file (skipped when unset)
#
# Arguments:
#   $1 - Line to append
#
# Outputs:
#   None
#
# Returns:
#   0 always
#
#######################################
function issue_create_summary {
    if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
        printf '%s\n' "$1" >> "${GITHUB_STEP_SUMMARY}"
    fi
    return 0
}

#######################################
# deliver_issue_create: Open one Issue per new finding in issues.json
# Allowlist labels that do not exist yet are created first (needs issues: write); only when
# at least one Issue will be filed.
#
# Globals:
#   LOOP_MESSAGE_DIR - Directory holding issues.json
#   LOOP_NAME - Loop name for the fingerprint marker
#   FINALIZE_LABEL_ALLOWLIST - Newline-separated labels put on every created Issue
#   FINALIZE_ISSUE_LIMIT - Maximum Issues per run (default 5)
#   OUTCOME, VERDICT, AGENT_ENGINE, USAGE_JSON, RUN_URL - Meta rows
#   GITHUB_REPOSITORY - owner/name
#   GH_TOKEN - Token for gh
#   GITHUB_STEP_SUMMARY - Receives the cut findings and the created Issue numbers
#   GITHUB_OUTPUT - Receives outcome=unchanged when no Issue is created
#   LOOP_FAILURE_FILE - Failure record path
#
# Arguments:
#   None
#
# Outputs:
#   Notice and error annotations on stdout
#
# Returns:
#   0 on success (including nothing to create); 1 on failure (recorded)
#
# Usage:
#   deliver_issue_create
#
#######################################
function deliver_issue_create {
    local dir="${LOOP_MESSAGE_DIR:-}"
    local file="${dir}/issues.json"
    local limit="${FINALIZE_ISSUE_LIMIT:-5}"
    local loop_name="${LOOP_NAME:-}"
    local label labels_csv="" encoded existing err url meta_block body_file
    local i title body fingerprint hash count created=0 name_re
    local -A seen_hashes=()
    local -a labels=() label_args=() created_numbers=()
    local -a new_titles=() new_bodies=() new_fingerprints=() new_hashes=()

    if [[ ! -f ${file} ]]; then
        fail_loop_message "issues.json is missing"
        return 1
    fi
    if ! jq -e '
        type == "array" and all(
            type == "object"
            and (.title | type == "string" and length > 0 and length <= 256)
            and (.body | type == "string" and length <= 60000)
            and (.fingerprint | type == "string" and length > 0)
        )' "${file}" > /dev/null 2>&1; then
        fail_loop_message "issues.json is invalid (need an array of {title (1-256 chars), body (<= 60000 chars), fingerprint})"
        return 1
    fi
    if ! [[ ${limit} =~ ^[1-9][0-9]*$ ]]; then
        fail_loop_message "finalize_issue_limit must be a positive integer (got: ${limit})"
        return 1
    fi

    count="$(jq -r 'length' "${file}")"
    if [[ ${count} -eq 0 ]]; then
        echo "::notice title=loop-deliver::No findings to file; outcome is unchanged"
        if [[ -n ${GITHUB_OUTPUT:-} ]]; then
            echo "outcome=unchanged" >> "${GITHUB_OUTPUT}"
        fi
        return 0
    fi

    while IFS= read -r label; do
        label="${label#"${label%%[![:space:]]*}"}"
        label="${label%"${label##*[![:space:]]}"}"
        [[ -n ${label} ]] && labels+=("${label}")
    done <<< "${FINALIZE_LABEL_ALLOWLIST:-}"
    if [[ ${#labels[@]} -eq 0 ]]; then
        fail_loop_message "finalize_label_allowlist is empty; issue_create needs the labels to apply"
        return 1
    fi
    for label in "${labels[@]}"; do
        encoded="$(jq -rn --arg l "${label}" '$l | @uri')"
        labels_csv+="${labels_csv:+,}${encoded}"
        label_args+=(--label "${label}")
    done

    # Existing Issues (open and closed) carrying every label; markers are matched locally.
    if ! existing="$(gh api --paginate "repos/${GITHUB_REPOSITORY}/issues?labels=${labels_csv}&state=all&per_page=100" \
        --jq '.[] | select(.pull_request == null) | .body // ""' 2>&1)"; then
        fail_loop_message "Failed to list existing issues: ${existing}"
        return 1
    fi
    name_re="$(sed 's/[][\\.*^$/]/\\&/g' <<< "${loop_name}")"
    while IFS= read -r hash; do
        [[ -n ${hash} ]] && seen_hashes["${hash}"]=1
    done < <(grep -o "<!-- ${name_re}:fp:[0-9a-f]\{16\} -->" <<< "${existing}" | sed -E 's/.*:fp:([0-9a-f]{16}) -->/\1/' || true)

    # Drop duplicates first, then cut to the limit.
    local dropped=0 skipped_dupes=0
    for ((i = 0; i < count; i++)); do
        title="$(jq -r --argjson i "${i}" '.[$i].title' "${file}")"
        body="$(jq -r --argjson i "${i}" '.[$i].body' "${file}")"
        fingerprint="$(jq -r --argjson i "${i}" '.[$i].fingerprint' "${file}")"
        hash="$(issue_fingerprint_hash "${loop_name}" "${fingerprint}")"
        if [[ -n ${seen_hashes[${hash}]:-} ]]; then
            skipped_dupes=$((skipped_dupes + 1))
            continue
        fi
        seen_hashes["${hash}"]=1
        if [[ ${#new_titles[@]} -ge ${limit} ]]; then
            dropped=$((dropped + 1))
            issue_create_summary "- cut by finalize_issue_limit=${limit}: ${title} (fingerprint: ${fingerprint})"
            continue
        fi
        # 4096 bytes of headroom for the marker line and the Meta block; bytes over-count characters
        if [[ $(($(sanitize_issue_body "${loop_name}" "${body}" | wc -c) + 4096)) -gt 65536 ]]; then
            issue_create_summary "- dropped (body too long for a GitHub issue): ${title} (fingerprint: ${fingerprint})"
            continue
        fi
        new_titles+=("${title}")
        new_bodies+=("${body}")
        new_fingerprints+=("${fingerprint}")
        new_hashes+=("${hash}")
    done
    echo "::notice title=loop-deliver::findings=${count} duplicates=${skipped_dupes} cut_by_limit=${dropped} to_create=${#new_titles[@]}"

    # Create missing labels only when an Issue will be filed.
    if [[ ${#new_titles[@]} -gt 0 ]] && ! err="$(ensure_repo_labels "${labels[@]}" 2>&1)"; then
        fail_loop_message "${err}"
        return 1
    fi

    loop_meta_reset
    meta_block="$(build_loop_meta_block "${OUTCOME:-}" "${VERDICT:-}" "" "${AGENT_ENGINE:-}" "${USAGE_JSON:-}" "${RUN_URL:-}")"
    for ((i = 0; i < ${#new_titles[@]}; i++)); do
        body_file="$(mktemp)"
        {
            printf '<!-- %s:fp:%s -->\n' "${loop_name}" "${new_hashes[i]}"
            printf '%s\n\n%s\n' "$(sanitize_issue_body "${loop_name}" "${new_bodies[i]}")" "${meta_block}"
        } > "${body_file}"
        if ! url="$(gh issue create --repo "${GITHUB_REPOSITORY}" --title "${new_titles[i]}" --body-file "${body_file}" "${label_args[@]}" 2>&1)"; then
            err="${url}"
            rm -f "${body_file}"
            issue_create_summary "- failed creating \"${new_titles[i]}\" after ${created} created: ${created_numbers[*]:-none}"
            fail_loop_message "Failed to create an issue after ${created} created (${created_numbers[*]:-none}): ${err}"
            return 1
        fi
        rm -f "${body_file}"
        created=$((created + 1))
        created_numbers+=("#${url##*/}")
        issue_create_summary "- created #${url##*/}: ${new_titles[i]}"
    done

    if [[ ${created} -eq 0 ]]; then
        echo "::notice title=loop-deliver::No new findings to file; outcome is unchanged"
        if [[ -n ${GITHUB_OUTPUT:-} ]]; then
            echo "outcome=unchanged" >> "${GITHUB_OUTPUT}"
        fi
        return 0
    fi
    echo "::notice title=loop-deliver::Created ${created} issue(s): ${created_numbers[*]}"
}
