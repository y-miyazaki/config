#!/bin/bash
#######################################
# Description:
#   Deliver delivery issue_create: open one GitHub Issue per new finding in issues.json.
#   Sourced by deliver_message.sh, which dispatches here and owns deliver_message_fail.
#
# Usage:
#   source deliver_issue_create.sh   (from deliver_message.sh)
#   deliver_issue_create
#
# Output:
#   None (library file, sourced by other scripts)
#
# Design Rules:
#   - issues.json is validated fail closed (array of {title, body, fingerprint})
#   - Duplicates (open and closed Issues carrying every allowlist label, and repeats within
#     the run) are dropped BEFORE the limit is applied, so a backlog of already-filed
#     findings never crowds out new ones
#   - Findings cut by the limit are listed in the step summary and not carried over
#   - A finding whose finished body (marker, sanitized text, Meta) would pass GitHub's
#     65536-character limit is dropped and listed in the step summary, not failed: a
#     failure would block the cursor and repeat every run
#   - Creation stops at the first failure; the label set always comes from the caller
#     allowlist, never the agent
#   - Missing allowlist labels are created only when at least one Issue will be filed
#
# Dependencies:
#   - bash, gh, jq, sha256sum
#   - ensure_labels.sh, loop_meta.sh, and deliver_message_fail from deliver_message.sh
#######################################

#######################################
# deliver_issue_create_fingerprint_hash: Hash a finding fingerprint for the Issue marker
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
#   hash="$(deliver_issue_create_fingerprint_hash code-review "a.sh:f:null")"
#
#######################################
function deliver_issue_create_fingerprint_hash {
    local loop_name="$1"
    local fingerprint="$2"

    printf '%s\n%s' "${loop_name}" "${fingerprint}" | sha256sum | cut -c1-16
}

#######################################
# deliver_issue_create_sanitize_body: Defuse text an agent could use to forge markers or notify people
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
#   body="$(deliver_issue_create_sanitize_body code-review "${raw_body}")"
#
#######################################
function deliver_issue_create_sanitize_body {
    local zwsp=$'\xe2\x80\x8b'
    local body="$2"

    body="${body//<!--/&lt;!--}"
    sed -E "s/@([A-Za-z0-9_])/@${zwsp}\\1/g" <<< "${body}"
}

#######################################
# deliver_issue_create_summary: Append one line to the step summary when it is available
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
function deliver_issue_create_summary {
    if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
        printf '%s\n' "$1" >> "${GITHUB_STEP_SUMMARY}"
    fi
    return 0
}

#######################################
# deliver_issue_create_mark_unchanged: Report that nothing was filed and set outcome=unchanged
#
# Globals:
#   GITHUB_OUTPUT - Receives outcome=unchanged when set
#
# Arguments:
#   $1 - Notice text
#
# Outputs:
#   Notice annotation on stdout
#
# Returns:
#   0 always
#
#######################################
function deliver_issue_create_mark_unchanged {
    echo "::notice title=loop-deliver::$1"
    if [[ -n ${GITHUB_OUTPUT:-} ]]; then
        echo "outcome=unchanged" >> "${GITHUB_OUTPUT}"
    fi
    return 0
}

#######################################
# deliver_issue_create_validate_input: Check issues.json and the Issue limit (fail closed)
#
# Globals:
#   None
#
# Arguments:
#   $1 - issues.json path
#   $2 - Maximum Issues per run
#
# Outputs:
#   None (failures are recorded through deliver_message_fail)
#
# Returns:
#   0 when valid; 1 on failure (recorded)
#
#######################################
function deliver_issue_create_validate_input {
    local file="$1"
    local limit="$2"

    if [[ ! -f ${file} ]]; then
        deliver_message_fail "issues.json is missing"
        return 1
    fi
    if ! jq -e '
        type == "array" and all(
            type == "object"
            and (.title | type == "string" and length > 0 and length <= 256)
            and (.body | type == "string" and length <= 60000)
            and (.fingerprint | type == "string" and length > 0)
        )' "${file}" > /dev/null 2>&1; then
        deliver_message_fail "issues.json is invalid (need an array of {title (1-256 chars), body (<= 60000 chars), fingerprint})"
        return 1
    fi
    if ! [[ ${limit} =~ ^[1-9][0-9]*$ ]]; then
        deliver_message_fail "finalize_issue_limit must be a positive integer (got: ${limit})"
        return 1
    fi
    return 0
}

#######################################
# deliver_issue_create_select_new_findings: Pick the findings that still need an Issue
#
# Description:
#   Drops findings already filed (open or closed Issues with every label) or repeated within
#   the run, then cuts to the limit and drops bodies too long for GitHub. Cut and dropped
#   findings are listed in the step summary.
#
# Globals:
#   GITHUB_REPOSITORY - owner/name
#   GH_TOKEN - Token for gh
#   GITHUB_STEP_SUMMARY - Receives the cut and dropped findings
#
# Arguments:
#   $1 - issues.json path (already validated)
#   $2 - Maximum Issues per run
#   $3 - Loop name for the fingerprint marker
#   $4 - URL-encoded, comma-joined allowlist labels for the Issue lookup
#   $5 - Output file; receives one "<index in issues.json><TAB><fingerprint hash>" line per pick
#
# Outputs:
#   Notice annotation with the counts on stdout
#
# Returns:
#   0 on success (the output file may be empty); 1 when listing Issues fails (recorded)
#
#######################################
function deliver_issue_create_select_new_findings {
    local file="$1"
    local limit="$2"
    local loop_name="$3"
    local labels_csv="$4"
    local out_file="$5"
    local existing name_re hash i count title body fingerprint
    local kept=0 dropped=0 skipped_dupes=0
    local -A seen_hashes=()

    : > "${out_file}"
    count="$(jq -r 'length' "${file}")"

    # Existing Issues (open and closed) carrying every label; markers are matched locally.
    if ! existing="$(gh api --paginate "repos/${GITHUB_REPOSITORY}/issues?labels=${labels_csv}&state=all&per_page=100" \
        --jq '.[] | select(.pull_request == null) | .body // ""' 2>&1)"; then
        deliver_message_fail "Failed to list existing issues: ${existing}"
        return 1
    fi
    name_re="$(sed 's/[][\\.*^$/]/\\&/g' <<< "${loop_name}")"
    while IFS= read -r hash; do
        [[ -n ${hash} ]] && seen_hashes["${hash}"]=1
    done < <(grep -o "<!-- ${name_re}:fp:[0-9a-f]\{16\} -->" <<< "${existing}" | sed -E 's/.*:fp:([0-9a-f]{16}) -->/\1/' || true)

    # Drop duplicates first, then cut to the limit.
    for ((i = 0; i < count; i++)); do
        title="$(jq -r --argjson i "${i}" '.[$i].title' "${file}")"
        body="$(jq -r --argjson i "${i}" '.[$i].body' "${file}")"
        fingerprint="$(jq -r --argjson i "${i}" '.[$i].fingerprint' "${file}")"
        hash="$(deliver_issue_create_fingerprint_hash "${loop_name}" "${fingerprint}")"
        if [[ -n ${seen_hashes[${hash}]:-} ]]; then
            skipped_dupes=$((skipped_dupes + 1))
            continue
        fi
        seen_hashes["${hash}"]=1
        if [[ ${kept} -ge ${limit} ]]; then
            dropped=$((dropped + 1))
            deliver_issue_create_summary "- cut by finalize_issue_limit=${limit}: ${title} (fingerprint: ${fingerprint})"
            continue
        fi
        # 4096 bytes of headroom for the marker line and the Meta block; bytes over-count characters
        if [[ $(($(deliver_issue_create_sanitize_body "${loop_name}" "${body}" | wc -c) + 4096)) -gt 65536 ]]; then
            deliver_issue_create_summary "- dropped (body too long for a GitHub issue): ${title} (fingerprint: ${fingerprint})"
            continue
        fi
        printf '%s\t%s\n' "${i}" "${hash}" >> "${out_file}"
        kept=$((kept + 1))
    done
    echo "::notice title=loop-deliver::findings=${count} duplicates=${skipped_dupes} cut_by_limit=${dropped} to_create=${kept}"
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
    local file="${LOOP_MESSAGE_DIR:-}/issues.json"
    local limit="${FINALIZE_ISSUE_LIMIT:-5}"
    local loop_name="${LOOP_NAME:-}"
    local label encoded labels_csv="" err url meta_block body_file picks_file pick i hash title created=0
    local -a labels=() label_args=() picks=() created_numbers=()

    deliver_issue_create_validate_input "${file}" "${limit}" || return 1
    if [[ $(jq -r 'length' "${file}") -eq 0 ]]; then
        deliver_issue_create_mark_unchanged "No findings to file; outcome is unchanged"
        return 0
    fi

    mapfile -t labels < <(ensure_labels_parse_list "${FINALIZE_LABEL_ALLOWLIST:-}")
    if [[ ${#labels[@]} -eq 0 ]]; then
        deliver_message_fail "finalize_label_allowlist is empty; issue_create needs the labels to apply"
        return 1
    fi
    for label in "${labels[@]}"; do
        encoded="$(jq -rn --arg l "${label}" '$l | @uri')"
        labels_csv+="${labels_csv:+,}${encoded}"
        label_args+=(--label "${label}")
    done

    picks_file="$(mktemp)"
    if ! deliver_issue_create_select_new_findings "${file}" "${limit}" "${loop_name}" "${labels_csv}" "${picks_file}"; then
        rm -f "${picks_file}"
        return 1
    fi
    mapfile -t picks < "${picks_file}"
    rm -f "${picks_file}"

    # Create missing labels only when an Issue will be filed.
    if [[ ${#picks[@]} -gt 0 ]] && ! err="$(ensure_labels_repo "${labels[@]}" 2>&1)"; then
        deliver_message_fail "${err}"
        return 1
    fi

    loop_meta_reset
    meta_block="$(loop_meta_build_block "${OUTCOME:-}" "${VERDICT:-}" "" "${AGENT_ENGINE:-}" "${USAGE_JSON:-}" "${RUN_URL:-}")"
    for pick in "${picks[@]}"; do
        i="${pick%%$'\t'*}"
        hash="${pick#*$'\t'}"
        title="$(jq -r --argjson i "${i}" '.[$i].title' "${file}")"
        body_file="$(mktemp)"
        {
            printf '<!-- %s:fp:%s -->\n' "${loop_name}" "${hash}"
            printf '%s\n\n%s\n' "$(deliver_issue_create_sanitize_body "${loop_name}" "$(jq -r --argjson i "${i}" '.[$i].body' "${file}")")" "${meta_block}"
        } > "${body_file}"
        if ! url="$(gh issue create --repo "${GITHUB_REPOSITORY}" --title "${title}" --body-file "${body_file}" "${label_args[@]}" 2>&1)"; then
            err="${url}"
            rm -f "${body_file}"
            deliver_issue_create_summary "- failed creating \"${title}\" after ${created} created: ${created_numbers[*]:-none}"
            deliver_message_fail "Failed to create an issue after ${created} created (${created_numbers[*]:-none}): ${err}"
            return 1
        fi
        rm -f "${body_file}"
        created=$((created + 1))
        created_numbers+=("#${url##*/}")
        deliver_issue_create_summary "- created #${url##*/}: ${title}"
    done

    if [[ ${created} -eq 0 ]]; then
        deliver_issue_create_mark_unchanged "No new findings to file; outcome is unchanged"
        return 0
    fi
    echo "::notice title=loop-deliver::Created ${created} issue(s): ${created_numbers[*]}"
}
