#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-notify-pr/lib/notify.sh

# Use cases:
# - build_comment_body includes agent overview and summary from notify json
# - build_comment_body includes agent appendix when present
# - build_comment_body includes fix context from notify json
# - build_comment_body includes marker and outcome
# - build_comment_body includes L2 next step when bot fix PR created
# - build_comment_body includes L3 auto-merge note when enabled
# - build_comment_body shows Reason row for reject reason
# - build_comment_body shows Reason even when changed files exist
# - build_comment_body redacts secrets in reject reason
# - build_comment_body uses watch message when outcome is watch
# - resolve_actor uses login when gh api user succeeds
# - resolve_actor falls back when gh api user fails with error JSON on stdout
# - redact_sensitive_text redacts bearer tokens
# - truncate_text truncates to max
# - validate_required_inputs fails when LOOP_NAME is empty
# - validate_required_inputs passes when required fields are set

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/loop-notify-pr/lib/notify.sh"
    GITHUB_OUTPUT="$(mktemp)"
    GITHUB_SERVER_URL="https://github.com"
    LOOP_NAME="ci-sweeper"
    LOOP_RUN_ID="99"
    OUTCOME="pr-created"
    PR_NUMBER="42"
    REPOSITORY="owner/repo"
    TOKEN="test-token"
    ATTEMPTS="1"
    MAX_ATTEMPTS="3"
    COMMIT_SHA="abcdefghijk"
    VERDICT="APPROVE"
    REJECT_REASON=""
    LEVEL="L2"
    AUTO_MERGE="false"
    FIX_PR_NUMBER="406"
    FIX_PR_URL="https://github.com/owner/repo/pull/406"
    TARGET_JSON='{"to":{"branch":"feature/x","pr_number":42},"workflow_name":"ci-test","workflow_run_id":"123"}'
    NOTIFY_CONTEXT_JSON='{"changed_files":["docs/a.md"],"diff_stat":" 1 file changed, 2 insertions(+)","fix_summary":"Address CI failure in lint (ci-test)","agent_summary":"","baseline_ref":"abc"}'
}

teardown() {
    rm -f "${GITHUB_OUTPUT:-}"
}

@test "build_comment_body includes agent overview and summary from notify json" {
    NOTIFY_CONTEXT_JSON='{"changed_files":["docs/a.md"],"diff_stat":" 1 file changed","fix_summary":"Address CI failure in lint (ci-test)","agent_report_overview":"CI failed on MD001; fixed heading in docs/foo.md.","agent_report_summary":"### Fixes Applied\n\n| Workflow / Job | Root cause | Fix |\n| --- | --- | --- |\n| ci / lint | MD001 | heading fix |","agent_summary":"","baseline_ref":"abc"}'
    run build_comment_body "loop-bot"
    [ "$status" -eq 0 ]
    [[ $output == *"### Overview"* ]]
    [[ $output == *"MD001"* ]]
    [[ $output == *"### Summary"* ]]
    [[ $output == *"### Fixes Applied"* ]]
    [[ $output == *"### Changes"* ]]
    [[ $output == *"docs/a.md"* ]]
    [[ $output != *"### Fix context"* ]]
    [[ $output != *"Address CI failure in lint"* ]]
}

@test "build_comment_body includes agent appendix when present" {
    NOTIFY_CONTEXT_JSON='{"changed_files":[],"diff_stat":"","fix_summary":"Address CI failure in lint (ci)","agent_summary":"Patched the flake.","baseline_ref":"abc"}'
    run build_comment_body "loop-bot"
    [ "$status" -eq 0 ]
    [[ $output == *"### Agent summary (appendix)"* ]]
    [[ $output == *"Patched the flake."* ]]
}

@test "build_comment_body includes fix context from notify json" {
    run build_comment_body "loop-bot"
    [ "$status" -eq 0 ]
    [[ $output == *"Address CI failure in lint (ci-test)"* ]]
    [[ $output == *"docs/a.md"* ]]
    [[ $output == *"1 file changed"* ]]
}

@test "build_comment_body includes marker and outcome" {
    run build_comment_body "loop-bot"
    [ "$status" -eq 0 ]
    [[ $output == *"<!-- loop-notify-pr:v1:ci-sweeper -->"* ]]
    [[ $output == *"## Loop notification: ci-sweeper"* ]]
    [[ $output == *"| Outcome | \`pr-created\` |"* ]]
    [[ $output == *"| Bot fix PR | [#406]"* ]]
    [[ $output == *"| Actor | \`loop-bot\` |"* ]]
    [[ $output == *"| Branch | \`feature/x\` |"* ]]
    [[ $output == *"abcdefghijk"* ]]
    [[ $output == *"https://github.com/owner/repo/commit/abcdefghijk"* ]]
    [[ $output == *"actions/runs/99"* ]]
}

@test "build_comment_body includes L2 next step when bot fix PR created" {
    run build_comment_body "loop-bot"
    [ "$status" -eq 0 ]
    [[ $output == *"Next step (L2)"* ]]
    [[ $output == *"Merge or close the bot fix PR"* ]]
}

@test "build_comment_body includes L3 auto-merge note when enabled" {
    LEVEL="L3"
    AUTO_MERGE="true"
    run build_comment_body "loop-bot"
    [ "$status" -eq 0 ]
    [[ $output == *"Next step (L3)"* ]]
    [[ $output == *"auto-merge"* ]]
}

@test "build_comment_body redacts secrets in reject reason" {
    OUTCOME="rejected"
    NOTIFY_CONTEXT_JSON='{"changed_files":[],"diff_stat":"","fix_summary":"","agent_summary":"","baseline_ref":""}'
    REJECT_REASON="failed with Bearer super-secret-token-value"
    run build_comment_body "loop-bot"
    [ "$status" -eq 0 ]
    [[ $output == *"| Reason |"* ]]
    [[ $output == *"Bearer [REDACTED]"* ]]
    [[ $output != *"super-secret-token-value"* ]]
}

@test "build_comment_body shows Reason even when changed files exist" {
    OUTCOME="rejected"
    VERDICT="REJECT"
    FIX_PR_NUMBER=""
    FIX_PR_URL=""
    REJECT_REASON="Diff addresses coverage threshold; deferred by verifier criteria"
    run build_comment_body "loop-bot"
    [ "$status" -eq 0 ]
    [[ $output == *"| Reason | Diff addresses coverage threshold; deferred by verifier criteria |"* ]]
    [[ $output == *"### Fix context"* ]]
    [[ $output == *"Address CI failure in lint (ci-test)"* ]]
}

@test "build_comment_body shows Reason row for reject reason" {
    OUTCOME="rejected"
    VERDICT="REJECT"
    FIX_PR_NUMBER=""
    FIX_PR_URL=""
    NOTIFY_CONTEXT_JSON='{"changed_files":[],"diff_stat":"","fix_summary":"","agent_summary":"","baseline_ref":""}'
    REJECT_REASON="No file changes produced"
    run build_comment_body "loop-bot"
    [ "$status" -eq 0 ]
    [[ $output == *"| Verdict | REJECT |"* ]]
    [[ $output == *"| Reason | No file changes produced |"* ]]
    [[ $output != *"### Fix context"* ]]
}

@test "build_comment_body uses watch message when outcome is watch" {
    OUTCOME="watch"
    NOTIFY_CONTEXT_JSON='{"changed_files":[],"diff_stat":"","fix_summary":"","agent_summary":"","baseline_ref":""}'
    run build_comment_body "loop-bot"
    [ "$status" -eq 0 ]
    [[ $output == *"classified as **watch**"* ]]
}

@test "redact_sensitive_text redacts bearer tokens" {
    run redact_sensitive_text "Authorization: Bearer abc.def.ghi"
    [ "$status" -eq 0 ]
    [[ $output == *"Authorization: [REDACTED]"* ]] || [[ $output == *"Bearer [REDACTED]"* ]]
}

@test "resolve_actor falls back when gh api user fails with error JSON on stdout" {
    local mock_bin
    mock_bin="$(mktemp -d)"
    cat > "${mock_bin}/gh" << 'EOF'
#!/usr/bin/env bash
if [[ $1 == api && $2 == user ]]; then
    printf '%s' '{"message":"Resource not accessible by integration","documentation_url":"https://docs.github.com/rest/users/users#get-the-authenticated-user","status":"403"}'
    exit 1
fi
exit 1
EOF
    chmod +x "${mock_bin}/gh"
    PATH="${mock_bin}:${PATH}"
    run resolve_actor
    rm -rf "${mock_bin}"
    [ "$status" -eq 0 ]
    [ "$output" = "github-actions" ]
    [[ $output != *"Resource not accessible"* ]]
}

@test "resolve_actor uses login when gh api user succeeds" {
    local mock_bin
    mock_bin="$(mktemp -d)"
    cat > "${mock_bin}/gh" << 'EOF'
#!/usr/bin/env bash
if [[ $1 == api && $2 == user ]]; then
    echo "loop-bot[bot]"
    exit 0
fi
exit 1
EOF
    chmod +x "${mock_bin}/gh"
    PATH="${mock_bin}:${PATH}"
    run resolve_actor
    rm -rf "${mock_bin}"
    [ "$status" -eq 0 ]
    [ "$output" = "loop-bot[bot]" ]
}

@test "truncate_text truncates to max" {
    run truncate_text "abcdefghij" 5
    [ "$status" -eq 0 ]
    [ "$output" = "abcde" ]
}

@test "validate_required_inputs fails when LOOP_NAME is empty" {
    LOOP_NAME=""
    run validate_required_inputs
    [ "$status" -ne 0 ]
}

@test "validate_required_inputs passes when required fields are set" {
    run validate_required_inputs
    [ "$status" -eq 0 ]
}
