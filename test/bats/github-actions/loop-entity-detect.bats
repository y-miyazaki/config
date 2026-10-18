#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

bats_require_minimum_version 1.5.0

# Tests for .github/actions/loop-entity-detect/{action.yml,lib/detect.sh,lib/outputs.sh}
#
# Use cases:
# - action.yml declares the renamed inputs and no removed inputs (may_edit, write_target, dispatch_hook_*)
# - action.yml has no default for delivery or level, maps inputs to env, and exposes pr_auto_merge
# - resolve_detect_script_path pins relative and absolute detect scripts
# - shrink_entity_matrix_for_output trims verifier_context and adds no handoff_key
# - write_entity_detect_outputs writes delivery and pr_auto_merge derived from level and delivery
# - main fails without outputs on empty level/delivery or another write-contract error
# - main fails when skip is false and result.entity.kind is missing or invalid
# - main fails when the entity target kind is not allowed by delivery
# - main skips when daily budget is exceeded
# - main builds target matrix, handoff payload, and pr_auto_merge from a successful entity detect

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

ENTITY_DETECT_LIB="$(bats_workspace_root)/.github/actions/loop-entity-detect/lib/detect.sh"
ENTITY_DETECT_INIT="$(bats_workspace_root)/.github/actions/loop-entity-detect/lib/_init.sh"
ACTION_YML="$(bats_workspace_root)/.github/actions/loop-entity-detect/action.yml"

# action_input_block prints the lines of one top-level input block in action.yml.
action_input_block() {
    awk -v name="$1" '
        /^inputs:/ { in_inputs = 1; next }
        /^[a-z]/ { in_inputs = 0 }
        in_inputs && /^  [a-z_]+:$/ { in_block = ($0 == "  " name ":"); next }
        in_inputs && in_block { print }
    ' "${ACTION_YML}"
}

entity_detect_write_mock_script() {
    local path="$1"
    local payload="$2"
    printf '%s\n' "${payload}" > "${path}.json"
    printf '#!/bin/bash\ncat "%s"\n' "${path}.json" > "${path}"
    chmod +x "${path}"
}

# github_output_matrix prints the target_matrix value written to GITHUB_OUTPUT.
github_output_matrix() {
    awk '/^target_matrix<</ { f = 1; next } f && /^TARGET_MATRIX_/ { f = 0 } f { print }' "${GITHUB_OUTPUT}"
}

# run_main runs detect.sh as a subprocess with a valid L1 entity configuration plus overrides.
run_main() {
    run --separate-stderr env \
        DETECT_SCRIPT="${BATS_TEST_TMPDIR}/detect.sh" \
        LOOP_NAME="github-issue-triage" \
        AGENT_MAKER_SKILL_NAME="github-issue-triage" \
        BUDGET_FILE="${BATS_TEST_TMPDIR}/budget.json" \
        RUN_LOG_FILE="${BATS_TEST_TMPDIR}/run-log.md" \
        LEVEL="L1" \
        DELIVERY="none" \
        "$@" \
        bash "${ENTITY_DETECT_LIB}"
}

setup() {
    # shellcheck disable=SC1090,SC1091
    source "${ENTITY_DETECT_INIT}"
    # shellcheck disable=SC1090,SC1091
    source "${ENTITY_DETECT_LIB}"
    GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/github_output"
    : > "${GITHUB_OUTPUT}"
    export GITHUB_OUTPUT
    export RUNNER_TEMP="${BATS_TEST_TMPDIR}/runner"
    mkdir -p "${RUNNER_TEMP}"
    printf '%s\n' '{}' > "${BATS_TEST_TMPDIR}/budget.json"
    : > "${BATS_TEST_TMPDIR}/run-log.md"
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
detect_hook_script
detect_script
finalize_label_allowlist
finalize_script
github_token
level
loop_name
run_log_file
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
        delivery detect_hook_script finalize_label_allowlist finalize_script level; do
        upper="$(tr '[:lower:]' '[:upper:]' <<< "${name}")"
        run grep -Fx "        ${upper}: \${{ inputs.${name} }}" "${ACTION_YML}"
        [ "$status" -eq 0 ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 9 ]
    run grep -E 'DISPATCH_HOOK|MAY_EDIT|WRITE_TARGET' "${ACTION_YML}"
    [ "$status" -eq 1 ]
}

@test "main fails on each invalid configuration without outputs" {
    entity_detect_write_mock_script "${BATS_TEST_TMPDIR}/detect.sh" '{"status":"ok","skip":false,"result":{"handoff_key":"entity:issue:1","entity":{"kind":"issue"}}}'
    local -a cases=(
        'LEVEL=|::error::level is required (L1, L2, or L3)'
        'DELIVERY=|::error::delivery must be none or issue_comment at L1 (got: empty)'
        'AGENT_EDIT_ALLOWLIST=**|::error::agent_edit_allowlist is not allowed at L1 (L1 is read-only)'
        'LEVEL=L2 AGENT_EDIT_TARGET=fix AGENT_EDIT_ALLOWLIST=** AGENT_UNCHANGED_VERDICT=REJECT DELIVERY=|::error::delivery must be issue_comment|none|pr_create|pr_push|pr_review (got: empty)'
        'LEVEL=L2 AGENT_EDIT_TARGET=fix AGENT_UNCHANGED_VERDICT=REJECT|::error::agent_edit_allowlist is required at L2 (use ** for unrestricted)'
        'LEVEL=L2 AGENT_EDIT_TARGET=fix AGENT_EDIT_ALLOWLIST=**|::error::agent_unchanged_verdict is required at L2 (APPROVE or REJECT)'
        'LEVEL=L1 DELIVERY=issue_comment FINALIZE_SCRIPT=x.sh|::error::finalize_script is not allowed at L1'
    )
    local entry expected checked=0
    local -a assignments
    for entry in "${cases[@]}"; do
        read -r -a assignments <<< "${entry%%|*}"
        expected="${entry#*|}"
        : > "${GITHUB_OUTPUT}"
        run_main "${assignments[@]}"
        [ "$status" -eq 1 ]
        [ "$stderr" = "${expected}" ]
        [ ! -s "${GITHUB_OUTPUT}" ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 7 ]
}

@test "main fails when skip is false and entity kind is missing or invalid" {
    local -a cases=(
        '{"handoff_key":"entity:issue:1"}|empty'
        '{"handoff_key":"entity:issue:1","entity":{"kind":"repo"}}|repo'
    )
    local entry got checked=0
    for entry in "${cases[@]}"; do
        got="${entry##*|}"
        entity_detect_write_mock_script "${BATS_TEST_TMPDIR}/detect.sh" "{\"status\":\"ok\",\"skip\":false,\"result\":${entry%|*}}"
        : > "${GITHUB_OUTPUT}"
        run_main
        [ "$status" -eq 1 ]
        [ "$stderr" = "build_entity_target_matrix: result.entity.kind must be issue or pr when skip=false (got: ${got})" ]
        [ ! -s "${GITHUB_OUTPUT}" ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 2 ]
}

@test "main fails when the entity target kind is not allowed by delivery" {
    entity_detect_write_mock_script "${BATS_TEST_TMPDIR}/detect.sh" '{"status":"ok","skip":false,"result":{"handoff_key":"entity:pr:5","entity":{"kind":"pr"}}}'
    run_main LEVEL=L2 DELIVERY=pr_push AGENT_EDIT_TARGET=fix AGENT_EDIT_ALLOWLIST='**' AGENT_UNCHANGED_VERDICT=REJECT
    [ "$status" -eq 1 ]
    [ "$stderr" = "::error::delivery pr_push allows only pull_request targets (got: pr)" ]
    [ ! -s "${GITHUB_OUTPUT}" ]
}

@test "main ignores a missing entity kind when skip is true" {
    entity_detect_write_mock_script "${BATS_TEST_TMPDIR}/detect.sh" '{"status":"ok","skip":true,"result":{}}'
    run_main
    [ "$status" -eq 0 ]
    run grep -Fx 'should_run=false' "${GITHUB_OUTPUT}"
    [ "$status" -eq 0 ]
    run grep -Fx 'skip_reason=detect_skip' "${GITHUB_OUTPUT}"
    [ "$status" -eq 0 ]
}

@test "main publishes target matrix for successful entity detect" {
    entity_detect_write_mock_script "${BATS_TEST_TMPDIR}/detect.sh" \
        '{"status":"ok","skip":false,"result":{"handoff_key":"entity:issue:9","entity":{"kind":"issue"},"issue_number":9,"event_name":"issues","event_action":"opened"},"verifier_context":"Issue #9"}'
    run_main AGENT_MAKER_INSTRUCTIONS="triage pls"
    [ "$status" -eq 0 ]
    run grep -Fx 'should_run=true' "${GITHUB_OUTPUT}"
    [ "$status" -eq 0 ]
    run grep -Fx 'delivery=none' "${GITHUB_OUTPUT}"
    [ "$status" -eq 0 ]
    run grep -Fx 'pr_auto_merge=false' "${GITHUB_OUTPUT}"
    [ "$status" -eq 0 ]
    run jq -c '[length, (.[0] | keys), .[0].target_json.entity, .[0].verifier_context]' <<< "$(github_output_matrix)"
    [ "$output" = '[1,["prompt","target_json","verifier_context"],{"handoff_key":"entity:issue:9","kind":"issue"},""]' ]
    run find "${RUNNER_TEMP}/loop-handoff" -type f
    [ "$status" -eq 0 ]
    [ "$(wc -l <<< "${output}")" -ge 1 ]
}

@test "main publishes target matrix for L1 issue_comment on an issue entity" {
    entity_detect_write_mock_script "${BATS_TEST_TMPDIR}/detect.sh" \
        '{"status":"ok","skip":false,"result":{"handoff_key":"entity:issue:9","entity":{"kind":"issue"},"issue_number":9}}'
    run_main DELIVERY=issue_comment FINALIZE_LABEL_ALLOWLIST=$'bug\nfeature'
    [ "$status" -eq 0 ]
    run grep -Fx 'should_run=true' "${GITHUB_OUTPUT}"
    [ "$status" -eq 0 ]
    run grep -Fx 'delivery=issue_comment' "${GITHUB_OUTPUT}"
    [ "$status" -eq 0 ]
    run grep -Fx 'pr_auto_merge=false' "${GITHUB_OUTPUT}"
    [ "$status" -eq 0 ]
    run jq -c '[length, .[0].target_json.entity.kind]' <<< "$(github_output_matrix)"
    [ "$output" = '[1,"issue"]' ]
}

@test "main sets pr_auto_merge true at L3 with pr_create" {
    entity_detect_write_mock_script "${BATS_TEST_TMPDIR}/detect.sh" '{"status":"ok","skip":false,"result":{"handoff_key":"entity:issue:3","entity":{"kind":"issue"}}}'
    run_main LEVEL=L3 DELIVERY=pr_create AGENT_EDIT_TARGET=fix AGENT_EDIT_ALLOWLIST='src/**' AGENT_UNCHANGED_VERDICT=REJECT
    [ "$status" -eq 0 ]
    run grep -Fx 'pr_auto_merge=true' "${GITHUB_OUTPUT}"
    [ "$status" -eq 0 ]
    run grep -Fx 'delivery=pr_create' "${GITHUB_OUTPUT}"
    [ "$status" -eq 0 ]
    run jq -r '.[0].prompt' <<< "$(github_output_matrix)"
    [[ ${output} == *$'\nAllowed paths: src/**.\n'* ]]
}

@test "main skips when daily run budget is exceeded" {
    entity_detect_write_mock_script "${BATS_TEST_TMPDIR}/detect.sh" '{"status":"ok","skip":false,"result":{"handoff_key":"entity:issue:1","entity":{"kind":"issue"}}}'
    printf '%s\n' "{\"loop_name\":\"github-issue-triage\",\"run_id\":\"$(date -u +%Y-%m-%d)T12:00:00Z\"}" > "${BATS_TEST_TMPDIR}/run-log.md"
    run_main BUDGET_MAX_RUNS_PER_DAY="1"
    [ "$status" -eq 0 ]
    run grep -Fx 'should_run=false' "${GITHUB_OUTPUT}"
    [ "$status" -eq 0 ]
    run grep -Fx 'skip_reason=budget' "${GITHUB_OUTPUT}"
    [ "$status" -eq 0 ]
    run grep -Fx 'pr_auto_merge=false' "${GITHUB_OUTPUT}"
    [ "$status" -eq 0 ]
}

@test "resolve_detect_script_path fails when script is missing" {
    DETECT_SCRIPT="${BATS_TEST_TMPDIR}/missing-detect.sh"
    run resolve_detect_script_path
    [ "$status" -eq 1 ]
    [ "$output" = "::error::DETECT_SCRIPT not found: ${BATS_TEST_TMPDIR}/missing-detect.sh" ]
}

@test "resolve_detect_script_path resolves relative detect script" {
    entity_detect_write_mock_script "${BATS_TEST_TMPDIR}/detect.sh" '{"status":"ok","skip":true,"result":{}}'
    run bash -c "cd '${BATS_TEST_TMPDIR}' && source '${ENTITY_DETECT_LIB}' && DETECT_SCRIPT=detect.sh && resolve_detect_script_path && printf '%s' \"\${DETECT_SCRIPT}\""
    [ "$status" -eq 0 ]
    [ "$output" = "$(realpath "${BATS_TEST_TMPDIR}/detect.sh")" ]
}

@test "shrink_entity_matrix_for_output clears verifier_context without adding handoff_key" {
    local full='[{"prompt":"p","target_json":{"key":"entity:issue:1","to":{"branch":"main"}},"verifier_context":"secret","result":{"x":1}}]'
    run shrink_entity_matrix_for_output "${full}"
    [ "$status" -eq 0 ]
    [ "$output" = '[{"prompt":"p","target_json":{"key":"entity:issue:1","to":{"branch":"main"}},"verifier_context":""}]' ]
}

@test "write_entity_detect_outputs writes delivery and pr_auto_merge" {
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
        write_entity_detect_outputs "true" "" '[{"target_json":{"key":"entity:issue:2"}}]'
        run grep -Fx "delivery=${DELIVERY}" "${GITHUB_OUTPUT}"
        [ "$status" -eq 0 ]
        run grep -Fx "pr_auto_merge=${expected_auto}" "${GITHUB_OUTPUT}"
        [ "$status" -eq 0 ]
        run grep -c '^pr_auto_merge=' "${GITHUB_OUTPUT}"
        [ "$output" = "1" ]
        run grep -Fx 'should_run=true' "${GITHUB_OUTPUT}"
        [ "$status" -eq 0 ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 5 ]
}
