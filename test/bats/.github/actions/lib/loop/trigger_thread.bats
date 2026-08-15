#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/lib/loop/trigger_thread.sh
#
# Use cases:
# - build_done_reply_body includes outcome verdict commit and run link
# - build_done_reply_body omits empty optional fields
# - ack_trigger_comment no-ops without comment id
# - ack_trigger_comment posts eyes on issue_comment
# - ack_trigger_comment posts eyes on pull_request_review_comment
# - ack_trigger_comment skips dispatch events
# - reply_trigger_comment posts review comment replies
# - reply_trigger_comment posts issue comment follow-up

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
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

@test "build_done_reply_body includes outcome verdict commit and run link" {
    run build_done_reply_body "push" "APPROVE" "ok" "abcdef012345" "https://github.com/o/r/commit/abcdef012345" "https://github.com/o/r/actions/runs/1" "Fixed lint."
    [ "$status" -eq 0 ]
    [[ $output == *"### Loop done"* ]]
    [[ $output == *"- Outcome: \`push\`"* ]]
    [[ $output == *"- Verdict: \`APPROVE\`"* ]]
    [[ $output == *"- Reason: ok"* ]]
    [[ $output == *"abcdef0"* ]]
    [[ $output == *"actions/runs/1"* ]]
    [[ $output == *"Fixed lint."* ]]
    [[ $output == *"not auto-resolved"* ]]
}

@test "build_done_reply_body omits empty optional fields" {
    run build_done_reply_body "no-changes" "" "" "" "" "" ""
    [ "$status" -eq 0 ]
    [[ $output == *"- Outcome: \`no-changes\`"* ]]
    [[ $output != *"- Verdict:"* ]]
    [[ $output != *"- Commit:"* ]]
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
