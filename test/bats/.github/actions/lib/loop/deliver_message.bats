#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/lib/loop/deliver_message.sh
#
# Use cases:
# - deliver_loop_message does nothing (outcome unchanged) without a message or with a blank one
# - deliver_loop_message posts one Issue comment with the marker first and Meta/footer once
# - deliver_loop_message posts a COMMENT review and retries once on HTTP 422 with fallback_body
# - deliver_loop_message reads the number from target_json and checks its kind against delivery
# - deliver_loop_message applies allowlisted labels before posting (one POST, encoded DELETEs)
# - deliver_loop_message fails the step and records deliver_message on gh failures, redacted
# - deliver_loop_message records the failure and removes temp files when run under set -e

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
# LABEL_DELETE), GH_MOCK_<KIND>_RC is a space-separated list of exit codes for the 1st, 2nd,
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
    run deliver_loop_message
    [ "$status" -eq 0 ]
    [ "$(gh_calls)" -eq 3 ]
    [[ "$(sed -n 1p "${BATS_TEST_TMPDIR}/gh.log")" == "api -X POST repos/o/r/issues/12/labels --input "* ]]
    [[ "$(sed -n 2p "${BATS_TEST_TMPDIR}/gh.log")" == "api -X DELETE repos/o/r/issues/12/labels/bug"* ]]
    [[ "$(sed -n 3p "${BATS_TEST_TMPDIR}/gh.log")" == "issue comment 12 "* ]]
}

@test "does not duplicate a marker the text already has" {
    printf '%s\nAlready marked.\n' "${MARKER}" > "${LOOP_MESSAGE_DIR}/message.md"
    run deliver_loop_message
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
    run deliver_loop_message
    [ "$status" -eq 1 ]
    [ "$(gh_calls)" -eq 1 ]
    [ "$(jq -r '.failure_stage' "${LOOP_FAILURE_FILE}")" = "deliver_message" ]

    rm -f "${BATS_TEST_TMPDIR}"/gh.* "${LOOP_FAILURE_FILE}"
    write_review "$(review_fixture)"
    export GH_MOCK_REVIEW_ERR="gh: Bad Gateway (HTTP 502)"
    run deliver_loop_message
    [ "$status" -eq 1 ]
    [ "$(gh_calls)" -eq 1 ]
    [ "$(jq -r '.failure_stage' "${LOOP_FAILURE_FILE}")" = "deliver_message" ]
}

@test "does nothing and writes outcome unchanged when message.md is absent or blank" {
    printf '{"add":["bug"],"remove":[]}' > "${LOOP_MESSAGE_DIR}/message_labels.json"
    run deliver_loop_message
    [ "$status" -eq 0 ]
    [ "$(gh_calls)" -eq 0 ]
    grep -qx 'outcome=unchanged' "${GITHUB_OUTPUT}"

    : > "${GITHUB_OUTPUT}"
    printf '  \n\n\t\n' > "${LOOP_MESSAGE_DIR}/message.md"
    export OUTCOME="watch"
    run deliver_loop_message
    [ "$status" -eq 0 ]
    [ "$(gh_calls)" -eq 0 ]
    grep -qx 'outcome=unchanged' "${GITHUB_OUTPUT}"
}

@test "does nothing when message_labels.json is invalid" {
    printf 'Triage text\n' > "${LOOP_MESSAGE_DIR}/message.md"
    printf '{"add":"bug"}' > "${LOOP_MESSAGE_DIR}/message_labels.json"
    run deliver_loop_message
    [ "$status" -eq 0 ]
    [[ $output == *"::warning::"* ]]
    [ "$(gh_calls)" -eq 0 ]
    grep -qx 'outcome=unchanged' "${GITHUB_OUTPUT}"
}

@test "does nothing when review.json is absent or has an empty body" {
    use_pr_review
    run deliver_loop_message
    [ "$status" -eq 0 ]
    [ "$(gh_calls)" -eq 0 ]
    grep -qx 'outcome=unchanged' "${GITHUB_OUTPUT}"

    : > "${GITHUB_OUTPUT}"
    write_review '{"body":"  \n","commit_id":"abc123","comments":[],"fallback_body":"x"}'
    run deliver_loop_message
    [ "$status" -eq 0 ]
    [ "$(gh_calls)" -eq 0 ]
    grep -qx 'outcome=unchanged' "${GITHUB_OUTPUT}"
}

@test "encodes label names in DELETE paths" {
    export FINALIZE_LABEL_ALLOWLIST=$'triage:needs-info\na b/c'
    printf 'text\n' > "${LOOP_MESSAGE_DIR}/message.md"
    printf '{"remove":["triage:needs-info","a b/c"]}' > "${LOOP_MESSAGE_DIR}/message_labels.json"
    run deliver_loop_message
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
    run deliver_loop_message
    [ "$status" -eq 1 ]
    [ "$(gh_calls)" -eq 1 ]
    [ "$(grep -c '^issue comment' "${BATS_TEST_TMPDIR}/gh.log")" -eq 0 ]
    [ "$(jq -r '.failure_stage' "${LOOP_FAILURE_FILE}")" = "deliver_message" ]

    rm -f "${BATS_TEST_TMPDIR}"/gh.* "${LOOP_FAILURE_FILE}"
    unset GH_MOCK_LABEL_POST_RC
    printf '{"remove":["bug"]}' > "${LOOP_MESSAGE_DIR}/message_labels.json"
    export GH_MOCK_LABEL_DELETE_RC="1"
    export GH_MOCK_LABEL_DELETE_ERR="gh: Server Error (HTTP 500)"
    run deliver_loop_message
    [ "$status" -eq 1 ]
    [ "$(grep -c '^issue comment' "${BATS_TEST_TMPDIR}/gh.log")" -eq 0 ]
    [ "$(jq -r '.failure_stage' "${LOOP_FAILURE_FILE}")" = "deliver_message" ]

    rm -f "${BATS_TEST_TMPDIR}"/gh.* "${LOOP_FAILURE_FILE}" "${LOOP_MESSAGE_DIR}/message_labels.json"
    unset GH_MOCK_LABEL_DELETE_RC
    export GH_MOCK_COMMENT_RC="1"
    run deliver_loop_message
    [ "$status" -eq 1 ]
    [ "$(gh_calls)" -eq 1 ]
    [ "$(jq -r '.failure_stage' "${LOOP_FAILURE_FILE}")" = "deliver_message" ]
    [ "$(grep -c '^outcome=' "${GITHUB_OUTPUT}")" -eq 0 ]
}

@test "fails without calling gh when the handoff key kind does not match delivery" {
    printf 'text\n' > "${LOOP_MESSAGE_DIR}/message.md"
    printf '{"add":["bug"]}' > "${LOOP_MESSAGE_DIR}/message_labels.json"
    export TARGET_JSON='{"key":"entity:pr:7","entity":{"handoff_key":"entity:pr:7","kind":"pr"}}'
    run deliver_loop_message
    [ "$status" -eq 1 ]
    [ "$(gh_calls)" -eq 0 ]
    [ "$(jq -r '.failure_stage' "${LOOP_FAILURE_FILE}")" = "deliver_message" ]

    rm -f "${LOOP_FAILURE_FILE}" "${LOOP_MESSAGE_DIR}/message_labels.json"
    use_pr_review
    write_review "$(review_fixture)"
    export TARGET_JSON='{"key":"entity:issue:12","entity":{"handoff_key":"entity:issue:12","kind":"issue"}}'
    run deliver_loop_message
    [ "$status" -eq 1 ]
    [ "$(gh_calls)" -eq 0 ]
    [ "$(jq -r '.failure_stage' "${LOOP_FAILURE_FILE}")" = "deliver_message" ]
}

@test "ignores an event in review.json" {
    use_pr_review
    write_review "$(review_fixture | jq -c '. + {event: "APPROVE"}')"
    run deliver_loop_message
    [ "$status" -eq 0 ]
    [ "$(jq -r '.event' "${BATS_TEST_TMPDIR}/gh.input.1")" = "COMMENT" ]
}

@test "ignores labels and warns when the allowlist is empty" {
    export FINALIZE_LABEL_ALLOWLIST=""
    printf 'text\n' > "${LOOP_MESSAGE_DIR}/message.md"
    printf '{"add":["bug"],"remove":["triage:ready"]}' > "${LOOP_MESSAGE_DIR}/message_labels.json"
    run deliver_loop_message
    [ "$status" -eq 0 ]
    [[ $output == *"::warning::"* ]]
    [ "$(gh_calls)" -eq 1 ]
    [[ "$(gh_log)" == "issue comment 12 "* ]]
}

@test "posts a COMMENT review with marker and Meta in body" {
    use_pr_review
    write_review "$(review_fixture)"
    run deliver_loop_message
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
    run deliver_loop_message
    [ "$status" -eq 0 ]
    [ "$(grep -c -- '-X POST repos/o/r/issues/12/labels' "${BATS_TEST_TMPDIR}/gh.log")" -eq 1 ]
    [ "$(jq -c . "${BATS_TEST_TMPDIR}/gh.input.1")" = '{"labels":["bug"]}' ]
    [[ $output == *"::warning::"*"autofix"* ]]
}

@test "posts one issue comment with the marker first and Meta and footer once" {
    printf 'Triage: documentation.\n\nNext step: add autofix.\n' > "${LOOP_MESSAGE_DIR}/message.md"
    run deliver_loop_message
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
        deliver_loop_message'
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
        deliver_loop_message'
    [ "$status" -eq 1 ]
    [ "$(jq -r '.failure_stage' "${LOOP_FAILURE_FILE}")" = "deliver_message" ]
    [ -z "$(ls -A "${tmp_dir}")" ]
}

@test "redacts tokens in the recorded failure message" {
    local token="ghp_abcdefghijklmnopqrstuvwxyz0123456789"
    printf 'text\n' > "${LOOP_MESSAGE_DIR}/message.md"
    export GH_MOCK_COMMENT_RC="1"
    export GH_MOCK_COMMENT_ERR="gh: Bad credentials ${token} (HTTP 401)"
    run deliver_loop_message
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
    run deliver_loop_message
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
    run deliver_loop_message
    [ "$status" -eq 0 ]
    [ "$(gh_calls)" -eq 1 ]
    [[ "$(gh_log)" == "issue comment 12 "* ]]
    [[ $output == *"::warning::"*"autofix"* ]]
}

@test "takes the number from entity.handoff_key and falls back to key" {
    printf 'text\n' > "${LOOP_MESSAGE_DIR}/message.md"
    export TARGET_JSON='{"key":"entity:issue:99","entity":{"handoff_key":"entity:issue:12","kind":"issue"}}'
    run deliver_loop_message
    [ "$status" -eq 0 ]
    [[ "$(gh_log)" == "issue comment 12 "* ]]

    rm -f "${BATS_TEST_TMPDIR}"/gh.*
    export TARGET_JSON='{"key":"entity:issue:34"}'
    run deliver_loop_message
    [ "$status" -eq 0 ]
    [[ "$(gh_log)" == "issue comment 34 "* ]]
}

@test "treats 404 on label DELETE as success" {
    printf 'text\n' > "${LOOP_MESSAGE_DIR}/message.md"
    printf '{"remove":["bug"]}' > "${LOOP_MESSAGE_DIR}/message_labels.json"
    export GH_MOCK_LABEL_DELETE_RC="1"
    export GH_MOCK_LABEL_DELETE_ERR="gh: Label does not exist (HTTP 404)"
    run deliver_loop_message
    [ "$status" -eq 0 ]
    [ "$(gh_calls)" -eq 2 ]
    [[ "$(sed -n 2p "${BATS_TEST_TMPDIR}/gh.log")" == "issue comment 12 "* ]]
    [ ! -e "${LOOP_FAILURE_FILE}" ]
}
