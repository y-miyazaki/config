#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/lib/loop/deliver_message.sh
#
# Use cases:
# - deliver_message_send does nothing (outcome unchanged) without a message or with a blank one
# - deliver_message_send posts one Issue comment with the marker first and Meta/footer once
# - deliver_message_send links tracked repository paths in the Issue comment and the review body
# - deliver_message_send posts a COMMENT review and retries once on HTTP 422 with fallback_body
# - deliver_message_send reads the number from target_json and checks its kind against delivery
# - deliver_message_send applies allowlisted labels before posting (one POST, encoded DELETEs)
# - deliver_message_send fails the step and records deliver_message on gh failures, redacted
# - deliver_message_send records the failure and removes temp files when run under set -e
# - issue_fingerprint_hash is the first 16 hex digits of sha256(loop_name, newline, fingerprint)
# - deliver_issue_create creates nothing for [] and fails closed on an invalid or missing issues.json
# - deliver_issue_create drops duplicates (open and closed, within the run) before applying the limit
# - deliver_issue_create records the findings cut by the limit in the step summary
# - deliver_issue_create labels with the whole allowlist, puts the marker first and Meta last
# - deliver_issue_create lists existing issues with every allowlist label and state=all
# - deliver_issue_create creates missing allowlist labels before the first issue, only when there is something to create
# - message labels to add are created when missing before they are added; a failed create stops the delivery
# - deliver_issue_create fails closed when a label cannot be created and accepts an already existing label
# - deliver_issue_create drops a finding whose finished body would exceed the GitHub limit
# - deliver_issue_create escapes regex characters in the loop name when matching markers
# - select_new_issue_findings writes one "<index><TAB><hash>" line per finding to keep and nothing for filed ones
# - validate_issue_create_input rejects a missing file, a malformed array, and a non-numeric limit
# - deliver_issue_create lives in deliver_issue_create.sh and is loaded by deliver_message.sh; these tests cover it through deliver_message_send
# - sanitize_issue_body defuses HTML comments and mentions; the marker cannot be forged
# - deliver_issue_create stops at the first failed create and reports the issues already created

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/lib/loop/created_by.sh"
    bats_source_rel ".github/actions/lib/loop/loop_meta.sh"
    bats_source_rel ".github/actions/lib/loop/failure_record.sh"
    bats_source_rel ".github/actions/lib/loop/deliver_message.sh"
    export DELIVERY="issue_comment"
    export LOOP_MESSAGE_DIR="${BATS_TEST_TMPDIR}/msg"
    export LOOP_NAME="github-issue-triage"
    export TARGET_JSON='{"key":"entity:issue:12","entity":{"handoff_key":"entity:issue:12","kind":"issue"}}'
    export FINALIZE_LABEL_ALLOWLIST=$'bug\ntriage:ready'
    export OUTCOME="issue_commented"
    export VERDICT=""
    export AGENT_ENGINE="claude"
    export USAGE_JSON='{"total_input_tokens":58,"total_output_tokens":15000,"models":["claude-opus-5"]}'
    export RUN_URL="https://x/run/1"
    export GITHUB_REPOSITORY="o/r"
    export GH_TOKEN="dummy"
    export LOOP_FAILURE_FILE="${BATS_TEST_TMPDIR}/failure.json"
    export GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/github_output"
    MARKER="<!-- github-issue-triage:v1 -->"
    mkdir -p "${LOOP_MESSAGE_DIR}"
    : > "${GITHUB_OUTPUT}"
    mock_gh
}

teardown() {
    rm -f "${BATS_TEST_TMPDIR}"/gh.* "${GITHUB_OUTPUT}" "${LOOP_FAILURE_FILE}"
}

# Install a gh mock. Each call is one line in gh.log; --body-file and --input contents are
# saved as gh.body.<call> / gh.input.<call>. Per call kind (COMMENT, REVIEW, LABEL_POST,
# LABEL_DELETE, LABEL_CREATE), GH_MOCK_<KIND>_RC is a space-separated list of exit codes for the 1st, 2nd,
# ... call of that kind (default 0), and GH_MOCK_<KIND>_ERR is printed on stderr on failure.
mock_gh() {
    local mock_bin="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${mock_bin}"
    cat > "${mock_bin}/gh" << 'EOF2'
#!/bin/bash
log="${BATS_TEST_TMPDIR}/gh.log"
printf '%s\n' "$*" >> "${log}"
call="$(wc -l < "${log}" | tr -d ' ')"
case "$*" in
    "issue comment "*) kind=COMMENT ;;
    "issue create "*) kind=CREATE ;;
    "label create "*) kind=LABEL_CREATE ;;
    "api --paginate "*) kind=LIST ;;
    *"-X POST "*"/pulls/"*"/reviews"*) kind=REVIEW ;;
    *"-X POST "*"/labels"*) kind=LABEL_POST ;;
    *"-X DELETE "*"/labels/"*) kind=LABEL_DELETE ;;
    *) kind=OTHER ;;
esac
while [[ $# -gt 0 ]]; do
    case "$1" in
        --body-file) cat "$2" > "${BATS_TEST_TMPDIR}/gh.body.${call}" ;;
        --input) cat "$2" > "${BATS_TEST_TMPDIR}/gh.input.${call}" ;;
    esac
    shift
done
count_file="${BATS_TEST_TMPDIR}/gh.count.${kind}"
count=$(($(cat "${count_file}" 2> /dev/null || echo 0) + 1))
echo "${count}" > "${count_file}"
rc_var="GH_MOCK_${kind}_RC"
err_var="GH_MOCK_${kind}_ERR"
read -r -a rcs <<< "${!rc_var:-0}"
rc="${rcs[$((count - 1))]:-0}"
if [[ ${rc} != 0 ]]; then
    printf '%s\n' "${!err_var:-gh: error}" >&2
fi
if [[ ${kind} == LIST && ${rc} == 0 && -n ${GH_MOCK_LIST_OUT:-} ]]; then
    printf '%s\n' "${GH_MOCK_LIST_OUT}"
fi
if [[ ${kind} == CREATE && ${rc} == 0 ]]; then
    printf 'https://github.com/o/r/issues/%s\n' "$((100 + count))"
fi
exit "${rc}"
EOF2
    chmod +x "${mock_bin}/gh"
    PATH="${mock_bin}:${PATH}"
}

gh_log() {
    cat "${BATS_TEST_TMPDIR}/gh.log" 2> /dev/null || true
}

gh_calls() {
    if [[ -f "${BATS_TEST_TMPDIR}/gh.log" ]]; then
        wc -l < "${BATS_TEST_TMPDIR}/gh.log" | tr -d ' '
    else
        echo 0
    fi
}

write_review() {
    printf '%s' "$1" > "${LOOP_MESSAGE_DIR}/review.json"
}

use_pr_review() {
    export DELIVERY="pr_review"
    export LOOP_NAME="github-pr-review"
    export OUTCOME="pr_reviewed"
    export TARGET_JSON='{"key":"entity:pr:7","entity":{"handoff_key":"entity:pr:7","kind":"pr"}}'
    MARKER="<!-- github-pr-review:v1 -->"
}

review_fixture() {
    printf '%s' '{"body":"Review summary","commit_id":"abc123","comments":[{"path":"a.sh","line":3,"side":"RIGHT","body":"fix"}],"fallback_body":"Review summary\n\n- a.sh:3 fix"}'
}

count_of() {
    local haystack="$1" needle="$2"
    awk -v n="${needle}" 'BEGIN { c = 0 } { s = $0; while ((i = index(s, n)) > 0) { c++; s = substr(s, i + length(n)) } } END { print c }' <<< "${haystack}"
}

@test "applies labels before posting" {
    printf 'text\n' > "${LOOP_MESSAGE_DIR}/message.md"
    printf '{"add":["triage:ready"],"remove":["bug"]}' > "${LOOP_MESSAGE_DIR}/message_labels.json"
    run deliver_message_send
    [ "$status" -eq 0 ]
    [ "$(gh_calls)" -eq 4 ]
    [[ "$(sed -n 1p "${BATS_TEST_TMPDIR}/gh.log")" == "label create triage:ready "* ]]
    [[ "$(sed -n 2p "${BATS_TEST_TMPDIR}/gh.log")" == "api -X POST repos/o/r/issues/12/labels --input "* ]]
    [[ "$(sed -n 3p "${BATS_TEST_TMPDIR}/gh.log")" == "api -X DELETE repos/o/r/issues/12/labels/bug"* ]]
    [[ "$(sed -n 4p "${BATS_TEST_TMPDIR}/gh.log")" == "issue comment 12 "* ]]
}

@test "creates a missing label before adding it and never for removals" {
    printf 'text\n' > "${LOOP_MESSAGE_DIR}/message.md"
    printf '{"add":["triage:ready"],"remove":["bug"]}' > "${LOOP_MESSAGE_DIR}/message_labels.json"
    run deliver_message_send
    [ "$status" -eq 0 ]
    [[ "$(sed -n 1p "${BATS_TEST_TMPDIR}/gh.log")" == "label create triage:ready --repo o/r "* ]]
    [[ "$(sed -n 2p "${BATS_TEST_TMPDIR}/gh.log")" == "api -X POST repos/o/r/issues/12/labels "* ]]
    [ "$(cat "${BATS_TEST_TMPDIR}/gh.count.LABEL_CREATE")" -eq 1 ]
}

@test "fails without adding labels or posting when a label cannot be created" {
    printf 'text\n' > "${LOOP_MESSAGE_DIR}/message.md"
    printf '{"add":["triage:ready"]}' > "${LOOP_MESSAGE_DIR}/message_labels.json"
    export GH_MOCK_LABEL_CREATE_RC="1"
    export GH_MOCK_LABEL_CREATE_ERR="HTTP 403: nope"
    run deliver_message_send
    [ "$status" -eq 1 ]
    [ "$(gh_calls)" -eq 1 ]
    grep -q 'triage:ready' "${LOOP_FAILURE_FILE}"
}

@test "does not duplicate a marker the text already has" {
    printf '%s\nAlready marked.\n' "${MARKER}" > "${LOOP_MESSAGE_DIR}/message.md"
    run deliver_message_send
    [ "$status" -eq 0 ]
    body="$(cat "${BATS_TEST_TMPDIR}/gh.body.1")"
    [ "$(count_of "${body}" "${MARKER}")" -eq 1 ]
    [[ ${body} == "${MARKER}"$'\n'"Already marked."* ]]
}

@test "does not retry on 422 without comments, or on other HTTP errors" {
    use_pr_review
    write_review '{"body":"Review summary","commit_id":"abc123","comments":[],"fallback_body":"Review summary"}'
    export GH_MOCK_REVIEW_RC="1 0"
    export GH_MOCK_REVIEW_ERR="gh: Unprocessable Entity (HTTP 422)"
    run deliver_message_send
    [ "$status" -eq 1 ]
    [ "$(gh_calls)" -eq 1 ]
    [ "$(jq -r '.failure_stage' "${LOOP_FAILURE_FILE}")" = "deliver_message" ]

    rm -f "${BATS_TEST_TMPDIR}"/gh.* "${LOOP_FAILURE_FILE}"
    write_review "$(review_fixture)"
    export GH_MOCK_REVIEW_ERR="gh: Bad Gateway (HTTP 502)"
    run deliver_message_send
    [ "$status" -eq 1 ]
    [ "$(gh_calls)" -eq 1 ]
    [ "$(jq -r '.failure_stage' "${LOOP_FAILURE_FILE}")" = "deliver_message" ]
}

@test "does nothing and writes outcome unchanged when message.md is absent or blank" {
    printf '{"add":["bug"],"remove":[]}' > "${LOOP_MESSAGE_DIR}/message_labels.json"
    run deliver_message_send
    [ "$status" -eq 0 ]
    [ "$(gh_calls)" -eq 0 ]
    grep -qx 'outcome=unchanged' "${GITHUB_OUTPUT}"

    : > "${GITHUB_OUTPUT}"
    printf '  \n\n\t\n' > "${LOOP_MESSAGE_DIR}/message.md"
    export OUTCOME="watch"
    run deliver_message_send
    [ "$status" -eq 0 ]
    [ "$(gh_calls)" -eq 0 ]
    grep -qx 'outcome=unchanged' "${GITHUB_OUTPUT}"
}

@test "does nothing when message_labels.json is invalid" {
    printf 'Triage text\n' > "${LOOP_MESSAGE_DIR}/message.md"
    printf '{"add":"bug"}' > "${LOOP_MESSAGE_DIR}/message_labels.json"
    run deliver_message_send
    [ "$status" -eq 0 ]
    [[ $output == *"::warning::"* ]]
    [ "$(gh_calls)" -eq 0 ]
    grep -qx 'outcome=unchanged' "${GITHUB_OUTPUT}"
}

@test "does nothing when review.json is absent or has an empty body" {
    use_pr_review
    run deliver_message_send
    [ "$status" -eq 0 ]
    [ "$(gh_calls)" -eq 0 ]
    grep -qx 'outcome=unchanged' "${GITHUB_OUTPUT}"

    : > "${GITHUB_OUTPUT}"
    write_review '{"body":"  \n","commit_id":"abc123","comments":[],"fallback_body":"x"}'
    run deliver_message_send
    [ "$status" -eq 0 ]
    [ "$(gh_calls)" -eq 0 ]
    grep -qx 'outcome=unchanged' "${GITHUB_OUTPUT}"
}

@test "encodes label names in DELETE paths" {
    export FINALIZE_LABEL_ALLOWLIST=$'triage:needs-info\na b/c'
    printf 'text\n' > "${LOOP_MESSAGE_DIR}/message.md"
    printf '{"remove":["triage:needs-info","a b/c"]}' > "${LOOP_MESSAGE_DIR}/message_labels.json"
    run deliver_message_send
    [ "$status" -eq 0 ]
    grep -qx 'api -X DELETE repos/o/r/issues/12/labels/triage%3Aneeds-info' "${BATS_TEST_TMPDIR}/gh.log"
    grep -qx 'api -X DELETE repos/o/r/issues/12/labels/a%20b%2Fc' "${BATS_TEST_TMPDIR}/gh.log"
    [ "$(grep -c -- '-X POST' "${BATS_TEST_TMPDIR}/gh.log")" -eq 0 ]
}

@test "fails the step and records deliver_message when a label call or the post fails" {
    printf 'text\n' > "${LOOP_MESSAGE_DIR}/message.md"
    printf '{"add":["bug"]}' > "${LOOP_MESSAGE_DIR}/message_labels.json"
    export GH_MOCK_LABEL_POST_RC="1"
    export GH_MOCK_LABEL_POST_ERR="gh: Forbidden (HTTP 403)"
    run deliver_message_send
    [ "$status" -eq 1 ]
    [ "$(gh_calls)" -eq 2 ]
    [ "$(grep -c '^issue comment' "${BATS_TEST_TMPDIR}/gh.log")" -eq 0 ]
    [ "$(jq -r '.failure_stage' "${LOOP_FAILURE_FILE}")" = "deliver_message" ]

    rm -f "${BATS_TEST_TMPDIR}"/gh.* "${LOOP_FAILURE_FILE}"
    unset GH_MOCK_LABEL_POST_RC
    printf '{"remove":["bug"]}' > "${LOOP_MESSAGE_DIR}/message_labels.json"
    export GH_MOCK_LABEL_DELETE_RC="1"
    export GH_MOCK_LABEL_DELETE_ERR="gh: Server Error (HTTP 500)"
    run deliver_message_send
    [ "$status" -eq 1 ]
    [ "$(grep -c '^issue comment' "${BATS_TEST_TMPDIR}/gh.log")" -eq 0 ]
    [ "$(jq -r '.failure_stage' "${LOOP_FAILURE_FILE}")" = "deliver_message" ]

    rm -f "${BATS_TEST_TMPDIR}"/gh.* "${LOOP_FAILURE_FILE}" "${LOOP_MESSAGE_DIR}/message_labels.json"
    unset GH_MOCK_LABEL_DELETE_RC
    export GH_MOCK_COMMENT_RC="1"
    run deliver_message_send
    [ "$status" -eq 1 ]
    [ "$(gh_calls)" -eq 1 ]
    [ "$(jq -r '.failure_stage' "${LOOP_FAILURE_FILE}")" = "deliver_message" ]
    [ "$(grep -c '^outcome=' "${GITHUB_OUTPUT}")" -eq 0 ]
}

@test "fails without calling gh when the handoff key kind does not match delivery" {
    printf 'text\n' > "${LOOP_MESSAGE_DIR}/message.md"
    printf '{"add":["bug"]}' > "${LOOP_MESSAGE_DIR}/message_labels.json"
    export TARGET_JSON='{"key":"entity:pr:7","entity":{"handoff_key":"entity:pr:7","kind":"pr"}}'
    run deliver_message_send
    [ "$status" -eq 1 ]
    [ "$(gh_calls)" -eq 0 ]
    [ "$(jq -r '.failure_stage' "${LOOP_FAILURE_FILE}")" = "deliver_message" ]

    rm -f "${LOOP_FAILURE_FILE}" "${LOOP_MESSAGE_DIR}/message_labels.json"
    use_pr_review
    write_review "$(review_fixture)"
    export TARGET_JSON='{"key":"entity:issue:12","entity":{"handoff_key":"entity:issue:12","kind":"issue"}}'
    run deliver_message_send
    [ "$status" -eq 1 ]
    [ "$(gh_calls)" -eq 0 ]
    [ "$(jq -r '.failure_stage' "${LOOP_FAILURE_FILE}")" = "deliver_message" ]
}

@test "ignores an event in review.json" {
    use_pr_review
    write_review "$(review_fixture | jq -c '. + {event: "APPROVE"}')"
    run deliver_message_send
    [ "$status" -eq 0 ]
    [ "$(jq -r '.event' "${BATS_TEST_TMPDIR}/gh.input.1")" = "COMMENT" ]
}

@test "ignores labels and warns when the allowlist is empty" {
    export FINALIZE_LABEL_ALLOWLIST=""
    printf 'text\n' > "${LOOP_MESSAGE_DIR}/message.md"
    printf '{"add":["bug"],"remove":["triage:ready"]}' > "${LOOP_MESSAGE_DIR}/message_labels.json"
    run deliver_message_send
    [ "$status" -eq 0 ]
    [[ $output == *"::warning::"* ]]
    [ "$(gh_calls)" -eq 1 ]
    [[ "$(gh_log)" == "issue comment 12 "* ]]
}

@test "links tracked repository paths in the Issue comment text" {
    local repo="${BATS_TEST_TMPDIR}/linkrepo"
    bats_git_fresh_repo "${repo}"
    mkdir -p "${repo}/docs"
    : > "${repo}/docs/spec.md"
    bats_git_commit "${repo}" "add spec"
    printf 'See docs/spec.md and `docs/missing.md`.\n' > "${LOOP_MESSAGE_DIR}/message.md"
    cd "${repo}"
    run deliver_message_send
    [ "$status" -eq 0 ]
    body="$(cat "${BATS_TEST_TMPDIR}/gh.body.1")"
    [[ ${body} == *"[docs/spec.md](https://github.com/o/r/blob/"*"/docs/spec.md)"* ]]
    [[ ${body} == *'`docs/missing.md`'* ]]
}

@test "posts a COMMENT review with marker and Meta in body" {
    use_pr_review
    write_review "$(review_fixture)"
    run deliver_message_send
    [ "$status" -eq 0 ]
    [ "$(gh_calls)" -eq 1 ]
    [[ "$(gh_log)" == "api -X POST repos/o/r/pulls/7/reviews --input "* ]]
    payload="${BATS_TEST_TMPDIR}/gh.input.1"
    [ "$(jq -r '.event' "${payload}")" = "COMMENT" ]
    [ "$(jq -r '.commit_id' "${payload}")" = "abc123" ]
    [ "$(jq -c '.comments' "${payload}")" = "$(review_fixture | jq -c '.comments')" ]
    [ "$(jq -r 'has("fallback_body")' "${payload}")" = "false" ]
    body="$(jq -r '.body' "${payload}")"
    [[ ${body} == "${MARKER}"$'\n'"Review summary"* ]]
    [[ ${body} == *"| outcome | pr_reviewed |"* ]]
    [ "$(count_of "${body}" "Written by Loop Engineering (LE)")" -eq 1 ]
    [ "$(grep -c '^outcome=' "${GITHUB_OUTPUT}")" -eq 0 ]
}

@test "posts allowlisted labels in one POST and warns on the rest" {
    printf 'text\n' > "${LOOP_MESSAGE_DIR}/message.md"
    printf '{"add":["bug","autofix"],"remove":null}' > "${LOOP_MESSAGE_DIR}/message_labels.json"
    run deliver_message_send
    [ "$status" -eq 0 ]
    [ "$(grep -c -- '-X POST repos/o/r/issues/12/labels' "${BATS_TEST_TMPDIR}/gh.log")" -eq 1 ]
    [ "$(jq -c . "${BATS_TEST_TMPDIR}/gh.input.2")" = '{"labels":["bug"]}' ]
    [[ $output == *"::warning::"*"autofix"* ]]
}

@test "posts one issue comment with the marker first and Meta and footer once" {
    printf 'Triage: documentation.\n\nNext step: add autofix.\n' > "${LOOP_MESSAGE_DIR}/message.md"
    run deliver_message_send
    [ "$status" -eq 0 ]
    [ "$(gh_calls)" -eq 1 ]
    [[ "$(gh_log)" == "issue comment 12 --repo o/r --body-file "* ]]
    body="$(cat "${BATS_TEST_TMPDIR}/gh.body.1")"
    [ "$(head -n 1 <<< "${body}")" = "${MARKER}" ]
    [[ ${body} == "${MARKER}"$'\n'"Triage: documentation."* ]]
    [[ ${body} == *"| outcome | issue_commented |"* ]]
    [[ ${body} == *"| engine | claude |"* ]]
    [ "$(count_of "${body}" "Written by Loop Engineering (LE)")" -eq 1 ]
    [ "$(grep -c '^outcome=' "${GITHUB_OUTPUT}")" -eq 0 ]
}

@test "records the failure and removes temp files when the post fails under set -e" {
    local tmp_dir="${BATS_TEST_TMPDIR}/tmpdir"
    mkdir -p "${tmp_dir}"
    printf 'text\n' > "${LOOP_MESSAGE_DIR}/message.md"
    export GH_MOCK_COMMENT_RC="1"
    export TMPDIR="${tmp_dir}"
    run bash -c 'set -euo pipefail
        source .github/actions/lib/loop/created_by.sh
        source .github/actions/lib/loop/loop_meta.sh
        source .github/actions/lib/loop/failure_record.sh
        source .github/actions/lib/loop/deliver_message.sh
        deliver_message_send'
    [ "$status" -eq 1 ]
    [ "$(jq -r '.failure_stage' "${LOOP_FAILURE_FILE}")" = "deliver_message" ]
    [ -z "$(ls -A "${tmp_dir}")" ]

    rm -f "${BATS_TEST_TMPDIR}"/gh.* "${LOOP_FAILURE_FILE}"
    use_pr_review
    write_review "$(review_fixture)"
    export GH_MOCK_REVIEW_RC="1"
    run bash -c 'set -euo pipefail
        source .github/actions/lib/loop/created_by.sh
        source .github/actions/lib/loop/loop_meta.sh
        source .github/actions/lib/loop/failure_record.sh
        source .github/actions/lib/loop/deliver_message.sh
        deliver_message_send'
    [ "$status" -eq 1 ]
    [ "$(jq -r '.failure_stage' "${LOOP_FAILURE_FILE}")" = "deliver_message" ]
    [ -z "$(ls -A "${tmp_dir}")" ]
}

@test "redacts tokens in the recorded failure message" {
    local token="ghp_abcdefghijklmnopqrstuvwxyz0123456789" # pragma: allowlist secret
    printf 'text\n' > "${LOOP_MESSAGE_DIR}/message.md"
    export GH_MOCK_COMMENT_RC="1"
    export GH_MOCK_COMMENT_ERR="gh: Bad credentials ${token} (HTTP 401)"
    run deliver_message_send
    [ "$status" -eq 1 ]
    [[ $output != *"${token}"* ]]
    message="$(jq -r '.failure_message' "${LOOP_FAILURE_FILE}")"
    [[ ${message} != *"${token}"* ]]
    [[ ${message} == *"[REDACTED]"* ]]
    [[ ${message} == *"HTTP 401"* ]]
}

@test "retries once with fallback_body and no comments on HTTP 422" {
    use_pr_review
    write_review "$(review_fixture)"
    export GH_MOCK_REVIEW_RC="1 0"
    export GH_MOCK_REVIEW_ERR="gh: Unprocessable Entity (HTTP 422)"
    run deliver_message_send
    [ "$status" -eq 0 ]
    [ "$(gh_calls)" -eq 2 ]
    second="${BATS_TEST_TMPDIR}/gh.input.2"
    [ "$(jq -r 'has("comments")' "${second}")" = "false" ]
    [ "$(jq -r '.event' "${second}")" = "COMMENT" ]
    [ "$(jq -r '.commit_id' "${second}")" = "abc123" ]
    body="$(jq -r '.body' "${second}")"
    [[ ${body} == "${MARKER}"$'\n'"Review summary"$'\n\n'"- a.sh:3 fix"* ]]
    [ "$(count_of "${body}" "${MARKER}")" -eq 1 ]
    [ "$(count_of "${body}" "<!-- loop-meta:v1 -->")" -eq 1 ]
    [ "$(count_of "${body}" "Written by Loop Engineering (LE)")" -eq 1 ]
    [ ! -e "${LOOP_FAILURE_FILE}" ]
}

@test "skips the POST when no requested label is allowlisted" {
    printf 'text\n' > "${LOOP_MESSAGE_DIR}/message.md"
    printf '{"add":["autofix"]}' > "${LOOP_MESSAGE_DIR}/message_labels.json"
    run deliver_message_send
    [ "$status" -eq 0 ]
    [ "$(gh_calls)" -eq 1 ]
    [[ "$(gh_log)" == "issue comment 12 "* ]]
    [[ $output == *"::warning::"*"autofix"* ]]
}

@test "takes the number from entity.handoff_key and falls back to key" {
    printf 'text\n' > "${LOOP_MESSAGE_DIR}/message.md"
    export TARGET_JSON='{"key":"entity:issue:99","entity":{"handoff_key":"entity:issue:12","kind":"issue"}}'
    run deliver_message_send
    [ "$status" -eq 0 ]
    [[ "$(gh_log)" == "issue comment 12 "* ]]

    rm -f "${BATS_TEST_TMPDIR}"/gh.*
    export TARGET_JSON='{"key":"entity:issue:34"}'
    run deliver_message_send
    [ "$status" -eq 0 ]
    [[ "$(gh_log)" == "issue comment 34 "* ]]
}

@test "treats 404 on label DELETE as success" {
    printf 'text\n' > "${LOOP_MESSAGE_DIR}/message.md"
    printf '{"remove":["bug"]}' > "${LOOP_MESSAGE_DIR}/message_labels.json"
    export GH_MOCK_LABEL_DELETE_RC="1"
    export GH_MOCK_LABEL_DELETE_ERR="gh: Label does not exist (HTTP 404)"
    run deliver_message_send
    [ "$status" -eq 0 ]
    [ "$(gh_calls)" -eq 2 ]
    [[ "$(sed -n 2p "${BATS_TEST_TMPDIR}/gh.log")" == "issue comment 12 "* ]]
    [ ! -e "${LOOP_FAILURE_FILE}" ]
}

use_issue_create() {
    export DELIVERY="issue_create"
    export LOOP_NAME="code-review"
    export OUTCOME="issue_created"
    export VERDICT="APPROVE"
    export TARGET_JSON='{"key":"integration:main","mode":"integration"}'
    export FINALIZE_LABEL_ALLOWLIST="loop:code-review"
    export FINALIZE_ISSUE_LIMIT="3"
    export GITHUB_STEP_SUMMARY="${BATS_TEST_TMPDIR}/summary.md"
    : > "${GITHUB_STEP_SUMMARY}"
    MARKER_PREFIX="<!-- code-review:fp:"
}

# write_issues JSON: write issues.json into LOOP_MESSAGE_DIR
write_issues() {
    printf '%s' "$1" > "${LOOP_MESSAGE_DIR}/issues.json"
}

# issues_for N PREFIX: JSON array of N findings with fingerprints PREFIX1..PREFIXN
issues_for() {
    jq -nc --argjson n "$1" --arg p "$2" '[range(1; $n + 1) | {title: ("title " + $p + (. | tostring)), body: ("body " + $p + (. | tostring)), fingerprint: ($p + (. | tostring))}]'
}

# marker_for FP: the issue marker for a fingerprint under loop name code-review
marker_for() {
    printf '<!-- code-review:fp:%s -->' "$(issue_fingerprint_hash code-review "$1")"
}

@test "deliver_issue_create creates nothing for an empty array and reports unchanged" {
    use_issue_create
    write_issues '[]'
    run deliver_message_send
    [ "$status" -eq 0 ]
    [ "$(gh_calls)" -eq 0 ]
    grep -qx 'outcome=unchanged' "${GITHUB_OUTPUT}"
}

@test "select_new_issue_findings writes one index and hash line per finding to keep" {
    use_issue_create
    write_issues "$(issues_for 3 n)"
    GH_MOCK_LIST_OUT="$(marker_for n2)"
    export GH_MOCK_LIST_OUT
    run select_new_issue_findings "${LOOP_MESSAGE_DIR}/issues.json" 3 code-review "loop%3Acode-review" "${BATS_TEST_TMPDIR}/picks"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "${BATS_TEST_TMPDIR}/picks")" -eq 2 ]
    [ "$(cut -f1 "${BATS_TEST_TMPDIR}/picks" | paste -sd, -)" = "0,2" ]
    [ "$(sed -n 1p "${BATS_TEST_TMPDIR}/picks" | cut -f2)" = "$(issue_fingerprint_hash code-review n1)" ]
}

@test "validate_issue_create_input rejects a missing file, a malformed array, and a non-numeric limit" {
    use_issue_create
    run validate_issue_create_input "${LOOP_MESSAGE_DIR}/issues.json" 3
    [ "$status" -eq 1 ]
    write_issues '[{"title":"t"}]'
    run validate_issue_create_input "${LOOP_MESSAGE_DIR}/issues.json" 3
    [ "$status" -eq 1 ]
    write_issues "$(issues_for 1 n)"
    run validate_issue_create_input "${LOOP_MESSAGE_DIR}/issues.json" 0
    [ "$status" -eq 1 ]
    run validate_issue_create_input "${LOOP_MESSAGE_DIR}/issues.json" 3
    [ "$status" -eq 0 ]
}

@test "deliver_issue_create creates each allowlist label before the first issue" {
    use_issue_create
    export FINALIZE_LABEL_ALLOWLIST=$'loop:code-review\nextra label'
    write_issues "$(issues_for 1 n)"
    run deliver_message_send
    [ "$status" -eq 0 ]
    [[ "$(sed -n 2p "${BATS_TEST_TMPDIR}/gh.log")" == "label create loop:code-review --repo o/r --description "* ]]
    [[ "$(sed -n 3p "${BATS_TEST_TMPDIR}/gh.log")" == "label create extra label --repo o/r --description "* ]]
    [[ "$(sed -n 4p "${BATS_TEST_TMPDIR}/gh.log")" == "issue create "* ]]
}

@test "deliver_issue_create does not touch labels when there is nothing to create" {
    use_issue_create
    write_issues '[]'
    run deliver_message_send
    [ "$status" -eq 0 ]
    [ ! -f "${BATS_TEST_TMPDIR}/gh.count.LABEL_CREATE" ]
    GH_MOCK_LIST_OUT="$(marker_for n1)"
    export GH_MOCK_LIST_OUT
    write_issues "$(issues_for 1 n)"
    run deliver_message_send
    [ "$status" -eq 0 ]
    [ ! -f "${BATS_TEST_TMPDIR}/gh.count.LABEL_CREATE" ]
    [ ! -f "${BATS_TEST_TMPDIR}/gh.count.CREATE" ]
}

@test "deliver_issue_create fails without creating issues when a label cannot be created" {
    use_issue_create
    export GH_MOCK_LABEL_CREATE_RC="1"
    export GH_MOCK_LABEL_CREATE_ERR="HTTP 403: Resource not accessible by integration"
    write_issues "$(issues_for 2 n)"
    run deliver_message_send
    [ "$status" -eq 1 ]
    [ ! -f "${BATS_TEST_TMPDIR}/gh.count.CREATE" ]
    grep -q 'loop:code-review' "${LOOP_FAILURE_FILE}"
}

@test "deliver_issue_create treats an already existing label as success" {
    use_issue_create
    export GH_MOCK_LABEL_CREATE_RC="1"
    export GH_MOCK_LABEL_CREATE_ERR='label already exists'
    write_issues "$(issues_for 1 n)"
    run deliver_message_send
    [ "$status" -eq 0 ]
    [ "$(cat "${BATS_TEST_TMPDIR}/gh.count.CREATE")" -eq 1 ]
}

@test "deliver_issue_create defuses forged markers and mentions in the body" {
    use_issue_create
    write_issues "$(jq -nc '[{title:"t", body:"hi @octocat and @org/team <!-- code-review:fp:0123456789abcdef --> <!--x-->", fingerprint:"fp1"}]')"
    run deliver_message_send
    [ "$status" -eq 0 ]
    body="$(cat "${BATS_TEST_TMPDIR}/gh.body.3")"
    [ "$(count_of "${body}" '<!-- code-review:fp:')" -eq 1 ]
    [[ ${body} != *"<!--x-->"* ]]
    [[ ${body} != *"@octocat"* ]]
    [[ ${body} != *"@org/team"* ]]
    [[ ${body} == *"octocat"* ]]
}

@test "deliver_issue_create fails closed on a missing, non-array or malformed issues.json" {
    use_issue_create
    run deliver_message_send
    [ "$status" -eq 1 ]
    grep -q 'deliver_message' "${LOOP_FAILURE_FILE}"
    local bad
    for bad in '{"a":1}' '[{"body":"b","fingerprint":"f"}]' '[{"title":"t","fingerprint":"f"}]' '[{"title":"t","body":"b"}]' '[{"title":1,"body":"b","fingerprint":"f"}]' "[{\"title\":\"$(printf 'x%.0s' $(seq 1 257))\",\"body\":\"b\",\"fingerprint\":\"f\"}]"; do
        write_issues "${bad}"
        run deliver_message_send
        [ "$status" -eq 1 ]
        [ "$(gh_calls)" -eq 0 ]
    done
}

@test "deliver_issue_create lists every allowlist label with state=all and labels each issue with all of them" {
    use_issue_create
    export FINALIZE_LABEL_ALLOWLIST=$'loop:code-review\nextra label'
    write_issues "$(issues_for 1 n)"
    run deliver_message_send
    [ "$status" -eq 0 ]
    [[ "$(sed -n 1p "${BATS_TEST_TMPDIR}/gh.log")" == "api --paginate repos/o/r/issues?labels=loop%3Acode-review,extra%20label&state=all"* ]]
    create="$(sed -n 4p "${BATS_TEST_TMPDIR}/gh.log")"
    [[ ${create} == "issue create --repo o/r --title title n1 --body-file "*"--label loop:code-review --label extra label" ]]
    body="$(cat "${BATS_TEST_TMPDIR}/gh.body.4")"
    [ "$(sed -n 1p <<< "${body}")" = "$(marker_for n1)" ]
    [[ ${body} == *"body n1"* ]]
    [[ ${body} == *"| verdict | APPROVE |"* ]]
}

@test "deliver_issue_create removes duplicates before applying the limit" {
    use_issue_create
    GH_MOCK_LIST_OUT="$(printf '%s\ntext\n%s\n%s\n' "$(marker_for e1)" "$(marker_for e2)" "$(marker_for e3)")"
    export GH_MOCK_LIST_OUT
    write_issues "$(jq -nc --argjson a "$(issues_for 3 e)" --argjson b "$(issues_for 2 n)" '$a + $b')"
    run deliver_message_send
    [ "$status" -eq 0 ]
    [ "$(cat "${BATS_TEST_TMPDIR}/gh.count.CREATE")" -eq 2 ]
    gh_log | grep -q 'title n1'
    gh_log | grep -q 'title n2'
    run ! grep -q 'title e1' "${BATS_TEST_TMPDIR}/gh.log"
}

@test "deliver_issue_create drops a fingerprint repeated within the run" {
    use_issue_create
    write_issues "$(jq -nc '[{title:"a",body:"b",fingerprint:"same"},{title:"c",body:"d",fingerprint:"same"}]')"
    run deliver_message_send
    [ "$status" -eq 0 ]
    [ "$(cat "${BATS_TEST_TMPDIR}/gh.count.CREATE")" -eq 1 ]
}

@test "deliver_issue_create stops at the first failed create and reports what was created" {
    use_issue_create
    export GH_MOCK_CREATE_RC="0 1"
    export GH_MOCK_CREATE_ERR="boom"
    write_issues "$(issues_for 3 n)"
    run deliver_message_send
    [ "$status" -eq 1 ]
    [ "$(cat "${BATS_TEST_TMPDIR}/gh.count.CREATE")" -eq 2 ]
    grep -q 'deliver_message' "${LOOP_FAILURE_FILE}"
    grep -q '#101' "${GITHUB_STEP_SUMMARY}"
    grep -q '#101' "${LOOP_FAILURE_FILE}"
}

@test "deliver_issue_create caps new issues at the limit and records the cut ones in the step summary" {
    use_issue_create
    write_issues "$(issues_for 5 n)"
    run deliver_message_send
    [ "$status" -eq 0 ]
    [ "$(cat "${BATS_TEST_TMPDIR}/gh.count.CREATE")" -eq 3 ]
    grep -q 'title n4' "${GITHUB_STEP_SUMMARY}"
    grep -q 'title n5' "${GITHUB_STEP_SUMMARY}"
    grep -q 'n5' "${GITHUB_STEP_SUMMARY}"
    [ "$(grep -c 'cut by finalize_issue_limit' "${GITHUB_STEP_SUMMARY}")" -eq 2 ]
}

@test "issue_fingerprint_hash is the first 16 hex digits of the sha256 of loop name, newline and fingerprint" {
    local expected
    expected="$(printf 'code-review\na.sh:f:null' | sha256sum | cut -c1-16)"
    run issue_fingerprint_hash code-review "a.sh:f:null"
    [ "$status" -eq 0 ]
    [ "$output" = "${expected}" ]
    [ "${#output}" -eq 16 ]
}

@test "deliver_issue_create fails when listing existing issues fails" {
    use_issue_create
    export GH_MOCK_LIST_RC="1"
    write_issues "$(issues_for 1 n)"
    run deliver_message_send
    [ "$status" -eq 1 ]
    [ -z "$(cat "${BATS_TEST_TMPDIR}/gh.count.CREATE" 2> /dev/null)" ]
}

@test "deliver_issue_create drops a finding whose sanitized body exceeds the GitHub limit" {
    use_issue_create
    local body
    body="$(printf '@a%.0s' $(seq 1 25000))"
    write_issues "$(jq -nc --arg b "${body}" '[{title:"big",body:$b,fingerprint:"f1"},{title:"small",body:"b",fingerprint:"f2"}]')"
    run deliver_message_send
    [ "$status" -eq 0 ]
    [ "$(cat "${BATS_TEST_TMPDIR}/gh.count.CREATE")" -eq 1 ]
    gh_log | grep -q 'title small'
    grep -q 'big' "${GITHUB_STEP_SUMMARY}"
}

@test "deliver_issue_create does not let a dot in the loop name match another loop's marker" {
    use_issue_create
    export LOOP_NAME="code.review"
    local other_hash
    other_hash="$(issue_fingerprint_hash "code.review" "n1")"
    export GH_MOCK_LIST_OUT="<!-- codexreview:fp:${other_hash} -->"
    write_issues "$(issues_for 1 n)"
    run deliver_message_send
    [ "$status" -eq 0 ]
    [ "$(cat "${BATS_TEST_TMPDIR}/gh.count.CREATE")" -eq 1 ]
}
