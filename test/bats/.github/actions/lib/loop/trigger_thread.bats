#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/lib/loop/trigger_thread.sh
#
# Use cases:
# - build_done_reply_body leads with the agent report before any metadata
# - build_done_reply_body promotes the reason to the lead when no report exists
# - build_done_reply_body lists changed files and diff stat under the lead
# - build_done_reply_body caps a long changed-files list
# - build_done_reply_body collapses outcome verdict commit and run into details
# - build_done_reply_body omits empty optional fields
# - build_done_reply_body marks a REJECT verdict with the failure icon
# - build_done_reply_body marks a no-changes outcome with the neutral icon
# - build_done_reply_body blockquotes every line of a multi-line reason
# - ack_trigger_comment no-ops without comment id
# - ack_trigger_comment posts eyes on issue_comment
# - ack_trigger_comment posts eyes on pull_request_review_comment
# - ack_trigger_comment skips dispatch events
# - ack_gathered_comments ACKs each comment by source
# - ack_gathered_comments falls back to trigger when empty
# - reply_trigger_comment posts review comment replies
# - reply_trigger_comment posts issue comment follow-up

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/lib/loop/created_by.sh"
    bats_source_rel ".github/actions/lib/loop/loop_meta.sh"
    bats_source_rel ".github/actions/lib/loop/trigger_thread.sh"
    PATH_BACKUP="${PATH}"
    MOCK_BIN="$(mktemp -d)"
    export PATH="${MOCK_BIN}:${PATH}"
    REPOSITORY="owner/repo"
    PR_NUMBER="42"
    TRIGGER_COMMENT_ID=""
    GITHUB_EVENT_NAME=""
}

teardown() {
    export PATH="${PATH_BACKUP:-$PATH}"
    rm -rf "${MOCK_BIN:-}"
}

install_gh_mock() {
    local mode="$1"
    cat > "${MOCK_BIN}/gh" << MOCK
#!/bin/bash
echo "\$*" >> "${MOCK_BIN}/gh.log"
if [[ "\${1:-}" == "api" ]]; then
  exit ${mode}
fi
exit 0
MOCK
    chmod +x "${MOCK_BIN}/gh"
}

@test "ack_trigger_comment no-ops without comment id" {
    install_gh_mock 0
    GITHUB_EVENT_NAME="issue_comment"
    TRIGGER_COMMENT_ID=""
    run ack_trigger_comment
    [ "$status" -eq 0 ]
    [ ! -f "${MOCK_BIN}/gh.log" ]
}

@test "ack_trigger_comment posts eyes on issue_comment" {
    install_gh_mock 0
    GITHUB_EVENT_NAME="issue_comment"
    TRIGGER_COMMENT_ID="99"
    run ack_trigger_comment
    [ "$status" -eq 0 ]
    grep -q "issues/comments/99/reactions" "${MOCK_BIN}/gh.log"
    grep -q "content=eyes" "${MOCK_BIN}/gh.log"
}

@test "ack_trigger_comment posts eyes on pull_request_review_comment" {
    install_gh_mock 0
    GITHUB_EVENT_NAME="pull_request_review_comment"
    TRIGGER_COMMENT_ID="77"
    run ack_trigger_comment
    [ "$status" -eq 0 ]
    grep -q "pulls/comments/77/reactions" "${MOCK_BIN}/gh.log"
}

@test "ack_trigger_comment skips dispatch events" {
    install_gh_mock 0
    GITHUB_EVENT_NAME="workflow_dispatch"
    TRIGGER_COMMENT_ID="99"
    run ack_trigger_comment
    [ "$status" -eq 0 ]
    [ ! -f "${MOCK_BIN}/gh.log" ]
}

@test "build_done_reply_body leads with the agent report before any metadata" {
    local lead_line details_line
    run build_done_reply_body "push" "APPROVE" "checker ok" "abcdef012345" "https://github.com/o/r/commit/abcdef012345" "https://github.com/o/r/actions/runs/1" "Added the durable-functions callout." "" ""
    [ "$status" -eq 0 ]
    lead_line="$(grep -n "Added the durable-functions callout." <<< "${output}" | head -1 | cut -d: -f1)"
    details_line="$(grep -n "<details>" <<< "${output}" | head -1 | cut -d: -f1)"
    [ -n "${lead_line}" ]
    [ -n "${details_line}" ]
    [ "${lead_line}" -lt "${details_line}" ]
    [[ $output == *"not auto-resolved"* ]]
}

@test "build_done_reply_body promotes the reason to the lead when no report exists" {
    local lead_line details_line
    run build_done_reply_body "rejected" "REJECT" "No file changes produced" "" "" "https://github.com/o/r/actions/runs/2" "" "" ""
    [ "$status" -eq 0 ]
    lead_line="$(grep -n "No file changes produced" <<< "${output}" | head -1 | cut -d: -f1)"
    details_line="$(grep -n "<details>" <<< "${output}" | head -1 | cut -d: -f1)"
    [ "${lead_line}" -lt "${details_line}" ]
    # Promoted reason is not repeated inside the collapsed block.
    [ "$(grep -c "No file changes produced" <<< "${output}")" -eq 1 ]
}

@test "build_done_reply_body lists changed files and diff stat under the lead" {
    run build_done_reply_body "push" "APPROVE" "ok" "" "" "" "Report." "docs/a.md,docs/b.md" " 2 files changed, 8 insertions(+)"
    [ "$status" -eq 0 ]
    [[ $output == *"**Files changed**"* ]]
    [[ $output == *"- \`docs/a.md\`"* ]]
    [[ $output == *"- \`docs/b.md\`"* ]]
    [[ $output == *"2 files changed, 8 insertions(+)"* ]]
}

@test "build_done_reply_body caps a long changed-files list" {
    local files
    files="f1.md,f2.md,f3.md,f4.md,f5.md,f6.md,f7.md,f8.md,f9.md,f10.md,f11.md,f12.md"
    run build_done_reply_body "push" "APPROVE" "" "" "" "" "Report." "${files}" ""
    [ "$status" -eq 0 ]
    [[ $output == *"- \`f10.md\`"* ]]
    [[ $output != *"- \`f11.md\`"* ]]
    [[ $output == *"2 more"* ]]
}

@test "build_done_reply_body collapses outcome verdict commit and run into details" {
    run build_done_reply_body "push" "APPROVE" "checker ok" "abcdef012345" "https://github.com/o/r/commit/abcdef012345" "https://github.com/o/r/actions/runs/1" "Report." "" ""
    [ "$status" -eq 0 ]
    [[ $output == *"<summary>✅ <code>push</code> · Loop details</summary>"* ]]
    [[ $output == *"| Verdict | \`APPROVE\` |"* ]]
    [[ $output == *"abcdef0"* ]]
    [[ $output == *"actions/runs/1"* ]]
    [[ $output == *"> checker ok"* ]]
    [[ $output == *"</details>"* ]]
}

@test "build_done_reply_body omits empty optional fields" {
    run build_done_reply_body "no-changes" "" "" "" "" "" "" "" ""
    [ "$status" -eq 0 ]
    [[ $output != *"| Verdict |"* ]]
    [[ $output != *"| Commit |"* ]]
    [[ $output != *"**Files changed**"* ]]
}

@test "build_done_reply_body marks a REJECT verdict with the failure icon" {
    run build_done_reply_body "rejected" "REJECT" "No file changes produced" "" "" "https://github.com/o/r/actions/runs/2" "" "" ""
    [ "$status" -eq 0 ]
    [[ $output == *"<summary>❌ <code>rejected</code> · Loop details</summary>"* ]]
}

@test "build_done_reply_body marks a no-changes outcome with the neutral icon" {
    run build_done_reply_body "no-changes" "APPROVE" "" "" "" "" "" "" ""
    [ "$status" -eq 0 ]
    [[ $output == *"<summary>ℹ️ <code>no-changes</code> · Loop details</summary>"* ]]
}

@test "build_done_reply_body blockquotes every line of a multi-line reason" {
    run build_done_reply_body "push" "APPROVE" "$(printf 'first line\nsecond line')" "" "" "" "Report." "" ""
    [ "$status" -eq 0 ]
    [[ $output == *"> first line"* ]]
    [[ $output == *"> second line"* ]]
}

@test "reply_trigger_comment posts review comment replies" {
    install_gh_mock 0
    GITHUB_EVENT_NAME="pull_request_review_comment"
    TRIGGER_COMMENT_ID="55"
    run reply_trigger_comment "### Loop done"
    [ "$status" -eq 0 ]
    grep -q "pulls/42/comments/55/replies" "${MOCK_BIN}/gh.log"
}

@test "reply_trigger_comment posts issue comment follow-up" {
    install_gh_mock 0
    GITHUB_EVENT_NAME="issue_comment"
    TRIGGER_COMMENT_ID="55"
    run reply_trigger_comment "### Loop done"
    [ "$status" -eq 0 ]
    grep -q "issues/42/comments" "${MOCK_BIN}/gh.log"
}

@test "ack_gathered_comments ACKs each comment by source" {
    install_gh_mock 0
    ACK_COMMENTS_JSON='[{"comment_id":11,"source":"issue_comment"},{"comment_id":22,"source":"pull_request_review_comment"}]'
    run ack_gathered_comments
    [ "$status" -eq 0 ]
    grep -q "issues/comments/11/reactions" "${MOCK_BIN}/gh.log"
    grep -q "pulls/comments/22/reactions" "${MOCK_BIN}/gh.log"
}

@test "ack_gathered_comments falls back to trigger when empty" {
    install_gh_mock 0
    ACK_COMMENTS_JSON='[]'
    GITHUB_EVENT_NAME="issue_comment"
    TRIGGER_COMMENT_ID="99"
    run ack_gathered_comments
    [ "$status" -eq 0 ]
    grep -q "issues/comments/99/reactions" "${MOCK_BIN}/gh.log"
}
