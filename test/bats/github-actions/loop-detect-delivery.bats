#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

bats_require_minimum_version 1.5.0

# Tests for one-value delivery handling in .github/actions/loop-detect
#
# Use cases:
# - action.yml declares the renamed inputs and no removed inputs (may_edit, git_landing_*, loop_*)
# - action.yml maps every renamed input to its uppercase environment variable
# - action.yml has no default for delivery or level and exposes the pr_auto_merge output
# - validate_detect_inputs fails on write-contract, delivery value, and detect-config errors
# - validate_candidate_targets rejects target kinds the delivery does not allow
# - write_detect_outputs writes delivery and pr_auto_merge derived from level and delivery
# - target_json builders emit no finalize key

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

DETECT_LIB="$(bats_workspace_root)/.github/actions/loop-detect/lib/detect.sh"
ACTION_YML="$(bats_workspace_root)/.github/actions/loop-detect/action.yml"

# action_input_block prints the lines of one top-level input block in action.yml.
action_input_block() {
    awk -v name="$1" '
        /^inputs:/ { in_inputs = 1; next }
        /^[a-z]/ { in_inputs = 0 }
        in_inputs && /^  [a-z_]+:$/ { in_block = ($0 == "  " name ":"); next }
        in_inputs && in_block { print }
    ' "${ACTION_YML}"
}

setup() {
    # shellcheck disable=SC1090
    source "${DETECT_LIB}"
    LEVEL="L2"
    DELIVERY="pr_create"
    AGENT_EDIT_TARGET="fix"
    AGENT_EDIT_ALLOWLIST="**"
    AGENT_EDIT_DENYLIST=""
    AGENT_UNCHANGED_VERDICT="REJECT"
    DETECT_PR_ENABLED="false"
    DETECT_BRANCH_MATCH="main"
    GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/github_output"
    : > "${GITHUB_OUTPUT}"
}

@test "action.yml declares exactly the renamed inputs" {
    local expected actual
    expected="agent_edit_allowlist
agent_edit_denylist
agent_edit_target
agent_maker_instructions
agent_maker_skill_name
agent_unchanged_verdict
budget_file
budget_max_runs_per_day
budget_max_tokens_per_day
delivery
detect_branch_match
detect_branch_match_mode
detect_max_targets
detect_pr_bot_allowlist
detect_pr_denylist
detect_pr_enabled
detect_pr_number
detect_priority
detect_script
finalize_label_allowlist
finalize_script
github_token
level
loop_name
run_log_file
state_branch
state_file"
    actual="$(awk '/^inputs:/ { f = 1; next } /^[a-z]/ { f = 0 } f && /^  [a-z_]+:$/ { sub(/^  /, ""); sub(/:$/, ""); print }' "${ACTION_YML}")"
    [ "${actual}" = "${expected}" ]
}

@test "action.yml exposes pr_auto_merge from the detect step" {
    local value_line
    value_line="$(printf '    value: %s{{ steps.detect.outputs.pr_auto_merge }}' '$')"
    run grep -Fx "${value_line}" "${ACTION_YML}"
    [ "$status" -eq 0 ]
    run grep -Fx '  pr_auto_merge:' "${ACTION_YML}"
    [ "$status" -eq 0 ]
}

@test "action.yml has no default for delivery or level" {
    local name block checked=0
    for name in delivery level; do
        block="$(action_input_block "${name}")"
        [ -n "${block}" ]
        [[ ${block} != *"default:"* ]]
        [[ ${block} == *"required: true"* ]]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 2 ]
}

@test "action.yml maps every renamed input to its uppercase environment variable" {
    local name upper checked=0
    for name in agent_edit_allowlist agent_edit_denylist agent_edit_target agent_unchanged_verdict \
        delivery detect_branch_match detect_branch_match_mode detect_max_targets detect_pr_bot_allowlist \
        detect_pr_denylist detect_pr_enabled detect_pr_number detect_priority \
        finalize_label_allowlist finalize_script level state_branch; do
        upper="$(tr '[:lower:]' '[:upper:]' <<< "${name}")"
        run grep -Fx "        ${upper}: \${{ inputs.${name} }}" "${ACTION_YML}"
        [ "$status" -eq 0 ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 17 ]
}

@test "build_integration_target_json emits no finalize key" {
    run build_integration_target_json "integration:main" "main" "abc123"
    [ "$status" -eq 0 ]
    [ "$output" = '{"mode":"integration","key":"integration:main","from":{"branch":"main","ref":"abc123"},"to":{"branch":"main"}}' ]
}

@test "build_pull_request_target_json emits no finalize key" {
    run build_pull_request_target_json "pull_request:42" "feature/x" "abc123" 42 "main"
    [ "$status" -eq 0 ]
    [ "$output" = '{"mode":"pull_request","key":"pull_request:42","from":{"branch":"feature/x","ref":"abc123"},"to":{"branch":"feature/x","pr_number":42},"base":{"branch":"main"}}' ]
}

@test "validate_candidate_targets accepts pull_request targets for pr_push" {
    DELIVERY="pr_push"
    CANDIDATES_JSON=('{"target_json":{"mode":"pull_request","key":"pull_request:42"}}')
    run --separate-stderr validate_candidate_targets
    [ "$status" -eq 0 ]
    [ -z "$stderr" ]
}

@test "validate_candidate_targets rejects an integration target for pr_push" {
    DELIVERY="pr_push"
    CANDIDATES_JSON=(
        '{"target_json":{"mode":"pull_request","key":"pull_request:42"}}'
        '{"target_json":{"mode":"integration","key":"integration:main"}}'
    )
    run --separate-stderr validate_candidate_targets
    [ "$status" -eq 1 ]
    [ "$stderr" = "::error::delivery pr_push allows only pull_request targets (got: integration)" ]
}

@test "validate_detect_inputs accepts a valid L2 pr_create configuration" {
    run --separate-stderr validate_detect_inputs
    [ "$status" -eq 0 ]
    [ -z "$stderr" ]
}

@test "validate_detect_inputs fails on each invalid configuration" {
    local -a cases=(
        'LEVEL=|::error::level is required (L1, L2, or L3)'
        'DELIVERY=|::error::delivery must be issue_comment|none|pr_create|pr_push|pr_review (got: empty)'
        'DELIVERY=open_pr|::error::delivery must be issue_comment|none|pr_create|pr_push|pr_review (got: open_pr)'
        'DELIVERY=issue_create|::error::delivery issue_create is not implemented'
        'AGENT_EDIT_ALLOWLIST=|::error::agent_edit_allowlist is required at L2 (use ** for unrestricted)'
        'AGENT_UNCHANGED_VERDICT=|::error::agent_unchanged_verdict is required at L2 (APPROVE or REJECT)'
        'DETECT_BRANCH_MATCH=|::error::detect_branch_match or detect_pr_enabled true is required'
    )
    local entry assignment expected checked=0
    for entry in "${cases[@]}"; do
        assignment="${entry%%|*}"
        expected="${entry#*|}"
        run --separate-stderr bash -c "
            source '${DETECT_LIB}'
            LEVEL=L2 DELIVERY=pr_create AGENT_EDIT_TARGET=fix AGENT_EDIT_ALLOWLIST='**'
            AGENT_EDIT_DENYLIST='' AGENT_UNCHANGED_VERDICT=REJECT
            DETECT_PR_ENABLED=false DETECT_BRANCH_MATCH=main
            ${assignment}
            validate_detect_inputs
        "
        [ "$status" -eq 1 ]
        [ "$stderr" = "${expected}" ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 7 ]
}

@test "validate_detect_inputs rejects issue_comment and pr_review" {
    local d checked=0
    for d in issue_comment pr_review; do
        DELIVERY="${d}"
        FINALIZE_SCRIPT="render.sh"
        DETECT_PR_ENABLED="true"
        DETECT_BRANCH_MATCH=""
        run --separate-stderr validate_detect_inputs
        [ "$status" -eq 1 ]
        [ "$stderr" = "::error::delivery ${d} requires an entity caller (loop-entity-detect)" ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 2 ]
}

@test "validate_detect_inputs rejects pr_push with detect_branch_match or without detect_pr_enabled" {
    DELIVERY="pr_push"
    DETECT_PR_ENABLED="true"
    DETECT_BRANCH_MATCH="main"
    run --separate-stderr validate_detect_inputs
    [ "$status" -eq 1 ]
    [ "$stderr" = "::error::delivery pr_push does not allow detect_branch_match (got: main)" ]

    DETECT_PR_ENABLED="false"
    DETECT_BRANCH_MATCH=""
    run --separate-stderr validate_detect_inputs
    [ "$status" -eq 1 ]
    [ "$stderr" = "::error::delivery pr_push requires detect_pr_enabled true" ]
}

@test "write_detect_outputs writes delivery and pr_auto_merge" {
    local -a cases=(
        'L3|pr_create|true'
        'L2|pr_create|false'
        'L3|pr_push|false'
        'L3|none|false'
        'L1|none|false'
    )
    local entry expected_auto checked=0
    for entry in "${cases[@]}"; do
        IFS='|' read -r LEVEL DELIVERY expected_auto <<< "${entry}"
        : > "${GITHUB_OUTPUT}"
        write_detect_outputs "false" "no_changes" "[]"
        run grep -Fx "delivery=${DELIVERY}" "${GITHUB_OUTPUT}"
        [ "$status" -eq 0 ]
        run grep -Fx "pr_auto_merge=${expected_auto}" "${GITHUB_OUTPUT}"
        [ "$status" -eq 0 ]
        run grep -c '^pr_auto_merge=' "${GITHUB_OUTPUT}"
        [ "$output" = "1" ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 5 ]
}
