#!/usr/bin/env bats

# Tests for .github/actions/lib/loop/check_loop_write_contract.sh
#
# Use cases:
# - L1 accepts delivery none or issue_comment with every edit field empty
# - L1 rejects any non-empty edit field, finalize_script, and any other delivery
# - L2 and L3 accept pr_create, pr_push, none, issue_comment and pr_review
# - L2 and L3 require finalize_script for issue_comment and pr_review
# - finalize_label_allowlist is allowed only with issue_comment or pr_review
# - L2 and L3 require agent_edit_target fix or report
# - L2 and L3 require a non-empty agent_edit_allowlist and accept ** as unrestricted
# - L2 and L3 accept any agent_edit_denylist including empty
# - L2 and L3 require agent_unchanged_verdict APPROVE or REJECT
# - empty or unknown level is rejected at every call

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

VALIDATE_LIB="$(bats_workspace_root)/.github/actions/lib/loop/check_loop_write_contract.sh"

setup() {
    # shellcheck disable=SC1090
    source "${VALIDATE_LIB}"
}

@test "validate accepts L1 delivery none and issue_comment with empty edit fields" {
    local checked=0 delivery
    for delivery in none issue_comment; do
        run check_loop_write_contract_all "L1" "${delivery}" "" "" "" "" "" ""
        [ "$status" -eq 0 ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 2 ]
}

@test "validate accepts L2 and L3 agent_edit_allowlist double star" {
    local checked=0 level
    for level in L2 L3; do
        run check_loop_write_contract_all "${level}" "none" "fix" "**" "" "APPROVE" "" ""
        [ "$status" -eq 0 ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 2 ]
}

@test "validate accepts L2 and L3 agent_edit_denylist empty" {
    local checked=0 level
    for level in L2 L3; do
        run check_loop_write_contract_all "${level}" "none" "fix" "src/**" "" "APPROVE" "" ""
        [ "$status" -eq 0 ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 2 ]
}

@test "validate accepts L2 and L3 agent_edit_denylist set" {
    local checked=0 level
    for level in L2 L3; do
        run check_loop_write_contract_all "${level}" "none" "fix" "src/**" ".github/**" "APPROVE" "" ""
        [ "$status" -eq 0 ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 2 ]
}

@test "validate accepts L2 and L3 agent_edit_target fix and report" {
    local checked=0 level target
    for level in L2 L3; do
        for target in fix report; do
            run check_loop_write_contract_all "${level}" "none" "${target}" "src/**" "" "APPROVE" "" ""
            [ "$status" -eq 0 ]
            checked=$((checked + 1))
        done
    done
    [ "${checked}" -eq 4 ]
}

@test "validate accepts L2 and L3 agent_unchanged_verdict APPROVE and REJECT" {
    local checked=0 level verdict
    for level in L2 L3; do
        for verdict in APPROVE REJECT; do
            run check_loop_write_contract_all "${level}" "none" "fix" "src/**" "" "${verdict}" "" ""
            [ "$status" -eq 0 ]
            checked=$((checked + 1))
        done
    done
    [ "${checked}" -eq 4 ]
}

@test "validate accepts L2 and L3 delivery none pr_create and pr_push" {
    local checked=0 level delivery
    for level in L2 L3; do
        for delivery in none pr_create pr_push; do
            run check_loop_write_contract_all "${level}" "${delivery}" "fix" "src/**" "" "APPROVE" "" ""
            [ "$status" -eq 0 ]
            checked=$((checked + 1))
        done
    done
    [ "${checked}" -eq 6 ]
}

@test "validate accepts L2 and L3 issue_comment and pr_review with finalize_script" {
    local checked=0 level delivery
    for level in L2 L3; do
        for delivery in issue_comment pr_review; do
            run check_loop_write_contract_all "${level}" "${delivery}" "report" "src/**" "" "APPROVE" "render.sh" ""
            [ "$status" -eq 0 ]
            checked=$((checked + 1))
        done
    done
    [ "${checked}" -eq 4 ]
}

@test "validate rejects L2 and L3 issue_comment and pr_review without finalize_script" {
    local checked=0 level delivery
    for level in L2 L3; do
        for delivery in issue_comment pr_review; do
            run check_loop_write_contract_all "${level}" "${delivery}" "report" "src/**" "" "APPROVE" "" ""
            [ "$status" -eq 1 ]
            [ "$output" = "::error::finalize_script is required for delivery ${delivery}" ]
            checked=$((checked + 1))
        done
    done
    [ "${checked}" -eq 4 ]
}

@test "validate accepts finalize_label_allowlist only with issue_comment or pr_review" {
    local checked=0 delivery
    run check_loop_write_contract_all "L1" "issue_comment" "" "" "" "" "" $'bug\nfeature'
    [ "$status" -eq 0 ]
    run check_loop_write_contract_all "L2" "pr_review" "report" "src/**" "" "APPROVE" "render.sh" "bug"
    [ "$status" -eq 0 ]
    run check_loop_write_contract_all "L1" "none" "" "" "" "" "" "bug"
    [ "$status" -eq 1 ]
    [ "$output" = "::error::finalize_label_allowlist requires delivery issue_comment, issue_create or pr_review (got: none)" ]
    for delivery in pr_create pr_push none; do
        run check_loop_write_contract_all "L2" "${delivery}" "fix" "src/**" "" "APPROVE" "" "bug"
        [ "$status" -eq 1 ]
        [ "$output" = "::error::finalize_label_allowlist requires delivery issue_comment, issue_create or pr_review (got: ${delivery})" ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 3 ]
}

@test "validate rejects L1 finalize_script" {
    local checked=0 delivery
    for delivery in none issue_comment; do
        run check_loop_write_contract_all "L1" "${delivery}" "" "" "" "" "x.sh" ""
        [ "$status" -eq 1 ]
        [ "$output" = "::error::finalize_script is not allowed at L1" ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 2 ]
}

@test "validate rejects L1 delivery pr_create pr_push pr_review issue_create" {
    local checked=0 delivery
    for delivery in "" pr_create pr_push pr_review issue_create log issue notion open_pr; do
        run check_loop_write_contract_all "L1" "${delivery}" "" "" "" "" "" ""
        [ "$status" -eq 1 ]
        [ "$output" = "::error::delivery must be none or issue_comment at L1 (got: ${delivery:-empty})" ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 9 ]
}

@test "validate rejects L1 non-empty agent_edit_allowlist" {
    run check_loop_write_contract_all "L1" "none" "" "src/**" "" "" "" ""
    [ "$status" -eq 1 ]
    [[ $output == *"agent_edit_allowlist"* ]]
}

@test "validate rejects L1 non-empty agent_edit_denylist" {
    run check_loop_write_contract_all "L1" "none" "" "" ".github/**" "" "" ""
    [ "$status" -eq 1 ]
    [[ $output == *"agent_edit_denylist"* ]]
}

@test "validate rejects L1 non-empty agent_edit_target" {
    run check_loop_write_contract_all "L1" "none" "fix" "" "" "" "" ""
    [ "$status" -eq 1 ]
    [[ $output == *"agent_edit_target"* ]]
}

@test "validate rejects L1 non-empty agent_unchanged_verdict" {
    run check_loop_write_contract_all "L1" "none" "" "" "" "APPROVE" "" ""
    [ "$status" -eq 1 ]
    [[ $output == *"agent_unchanged_verdict"* ]]
}

@test "validate rejects L2 and L3 delivery unimplemented or unknown" {
    local checked=0 level delivery
    for level in L2 L3; do
        for delivery in "" log issue notion open_pr slack; do
            run check_loop_write_contract_all "${level}" "${delivery}" "fix" "src/**" "" "APPROVE" "" ""
            [ "$status" -eq 1 ]
            [[ $output == *"delivery"* ]]
            checked=$((checked + 1))
        done
    done
    [ "${checked}" -eq 12 ]
}

@test "validate rejects L2 and L3 empty agent_edit_allowlist" {
    local checked=0 level
    for level in L2 L3; do
        run check_loop_write_contract_all "${level}" "none" "fix" "" "" "APPROVE" "" ""
        [ "$status" -eq 1 ]
        [[ $output == *"agent_edit_allowlist is required"* ]]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 2 ]
}

@test "validate rejects L2 and L3 empty agent_edit_target" {
    local checked=0 level
    for level in L2 L3; do
        run check_loop_write_contract_all "${level}" "none" "" "src/**" "" "APPROVE" "" ""
        [ "$status" -eq 1 ]
        [[ $output == *"agent_edit_target is required"* ]]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 2 ]
}

@test "validate rejects L2 and L3 empty agent_unchanged_verdict" {
    local checked=0 level
    for level in L2 L3; do
        run check_loop_write_contract_all "${level}" "none" "fix" "src/**" "" "" "" ""
        [ "$status" -eq 1 ]
        [[ $output == *"agent_unchanged_verdict is required"* ]]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 2 ]
}

@test "validate rejects L2 and L3 invalid agent_edit_target" {
    local checked=0 level
    for level in L2 L3; do
        run check_loop_write_contract_all "${level}" "none" "hybrid" "src/**" "" "APPROVE" "" ""
        [ "$status" -eq 1 ]
        [[ $output == *"agent_edit_target must be fix or report"* ]]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 2 ]
}

@test "validate rejects L2 and L3 invalid agent_unchanged_verdict" {
    local checked=0 level
    for level in L2 L3; do
        run check_loop_write_contract_all "${level}" "none" "fix" "src/**" "" "approve" "" ""
        [ "$status" -eq 1 ]
        [[ $output == *"agent_unchanged_verdict must be APPROVE or REJECT"* ]]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 2 ]
}

@test "validate rejects L4 level" {
    run check_loop_write_contract_all "L4" "none" "fix" "src/**" "" "APPROVE" "" ""
    [ "$status" -eq 1 ]
    [[ $output == *"level must be"* ]]
}

@test "validate rejects empty level" {
    run check_loop_write_contract_all "" "none" "" "" "" "" "" ""
    [ "$status" -eq 1 ]
    [[ $output == *"level is required"* ]]
}

@test "validate L2 and L3 issue_create requires finalize_script, finalize_label_allowlist and REJECT" {
    local checked=0 level
    for level in L2 L3; do
        run check_loop_write_contract_all "${level}" "issue_create" "report" ".loop-code-review/findings.json" "" "REJECT" "" "loop:code-review"
        [ "$status" -eq 1 ]
        [[ $output == *"finalize_script is required for delivery issue_create"* ]]
        run check_loop_write_contract_all "${level}" "issue_create" "report" ".loop-code-review/findings.json" "" "REJECT" "scripts/x.sh" ""
        [ "$status" -eq 1 ]
        [[ $output == *"finalize_label_allowlist is required for delivery issue_create"* ]]
        run check_loop_write_contract_all "${level}" "issue_create" "report" ".loop-code-review/findings.json" "" "APPROVE" "scripts/x.sh" "loop:code-review"
        [ "$status" -eq 1 ]
        [[ $output == *"agent_unchanged_verdict must be REJECT for delivery issue_create"* ]]
        run check_loop_write_contract_all "${level}" "issue_create" "report" ".loop-code-review/findings.json" "" "REJECT" "scripts/x.sh" "loop:code-review"
        [ "$status" -eq 0 ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 2 ]
}

@test "check_loop_write_contract_finalize_label_allowlist accepts a non-empty allowlist for issue_create" {
    run check_loop_write_contract_finalize_label_allowlist "issue_create" "loop:code-review"
    [ "$status" -eq 0 ]
    run check_loop_write_contract_finalize_label_allowlist "pr_create" "loop:code-review"
    [ "$status" -eq 1 ]
    [[ $output == *"issue_comment, issue_create or pr_review"* ]]
}

@test "check_loop_write_contract_agent_tool_denylist allows claude at L2 and L3 and rejects other engines and L1" {
    run check_loop_write_contract_agent_tool_denylist L2 claude "Agent"
    [ "$status" -eq 0 ]
    run check_loop_write_contract_agent_tool_denylist L3 claude "Agent"
    [ "$status" -eq 0 ]
    run check_loop_write_contract_agent_tool_denylist L2 codex "Agent"
    [ "$status" -eq 1 ]
    [[ $output == *"agent_tool_denylist requires agent_engine claude"* ]]
    run check_loop_write_contract_agent_tool_denylist L1 claude "Agent"
    [ "$status" -eq 1 ]
    [[ $output == *"agent_tool_denylist is not allowed at L1"* ]]
    run check_loop_write_contract_agent_tool_denylist L1 claude ""
    [ "$status" -eq 0 ]
    run check_loop_write_contract_agent_tool_denylist L2 codex ""
    [ "$status" -eq 0 ]
}

@test "check_loop_write_contract_finalize_issue_limit accepts a positive integer or empty and rejects other values for issue_create" {
    run check_loop_write_contract_finalize_issue_limit issue_create "3"
    [ "$status" -eq 0 ]
    run check_loop_write_contract_finalize_issue_limit issue_create ""
    [ "$status" -eq 0 ]
    local bad
    for bad in 0 -1 abc 1.5; do
        run check_loop_write_contract_finalize_issue_limit issue_create "${bad}"
        [ "$status" -eq 1 ]
        [[ $output == *"finalize_issue_limit must be a positive integer"* ]]
    done
    run check_loop_write_contract_finalize_issue_limit pr_create "abc"
    [ "$status" -eq 0 ]
}
