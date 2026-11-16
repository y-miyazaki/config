#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

bats_require_minimum_version 1.5.0

# Tests for .github/actions/loop-entity-detect/{action.yml,lib/detect.sh,lib/outputs.sh}
#
# Use cases:
# - action.yml declares the renamed inputs and no removed inputs (may_edit, write_target, dispatch_hook_*, the post-detect hook input)
# - action.yml has no default for delivery or level, maps inputs to env, and exposes pr_auto_merge
# - resolve_detect_script_path pins relative and absolute detect scripts
# - shrink_entity_matrix_for_output trims verifier_context and adds no handoff_key
# - write_entity_detect_outputs writes delivery and pr_auto_merge derived from level and delivery
# - main fails without outputs on empty level/delivery or another write-contract error
# - main fails when skip is false and result.entity.kind is missing or invalid
# - main fails when the entity target kind is not allowed by delivery
# - main skips when daily budget is exceeded
# - main reads the circuit breaker from origin state branch, not from the checked-out tree
# - main fails when STATE_BRANCH is missing
# - main publishes skip_reason domain:<slug> and a one-line redacted skip_detail when the detect script skips
# - action.yml exposes skip_detail
# - main skips with the admission reason when result.gate refuses the entity and proceeds when it admits
# - main applies the circuit breaker from the checked-out state file to the entity key
# - read_entity_target_state returns {} for a missing file or target and the target state otherwise
# - main builds target matrix, handoff payload, and pr_auto_merge from a successful entity detect
# - main keeps the detect JSON out of the published prompt and stores the full JSON in the handoff payload
# - main passes detect_env_json entries to the detect script only and rejects reserved or conflicting keys

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

# entity_sandbox creates a bare origin and a work clone on main holding an empty run log, so detect
# can snapshot the state file and run log from origin/main as it does in a workflow.
entity_sandbox() {
    ENTITY_BARE="${BATS_TEST_TMPDIR}/origin.git"
    ENTITY_WORK="${BATS_TEST_TMPDIR}/work"
    git init -q --bare -b main "${ENTITY_BARE}"
    git clone -q "${ENTITY_BARE}" "${ENTITY_WORK}" 2> /dev/null
    git -C "${ENTITY_WORK}" config user.email "t@example.com"
    git -C "${ENTITY_WORK}" config user.name "t"
    git -C "${ENTITY_WORK}" checkout -q -b main
    mkdir -p "${ENTITY_WORK}/.loop"
    : > "${ENTITY_WORK}/.loop/loop-run-log.md"
    git -C "${ENTITY_WORK}" add -A
    git -C "${ENTITY_WORK}" commit -q -m "init"
    git -C "${ENTITY_WORK}" push -q origin main
}

# entity_publish_file REL CONTENT commits a file to origin/main (the state branch).
entity_publish_file() {
    mkdir -p "$(dirname "${ENTITY_WORK}/$1")"
    printf '%s\n' "$2" > "${ENTITY_WORK}/$1"
    git -C "${ENTITY_WORK}" add -A
    git -C "${ENTITY_WORK}" commit -q -m "publish $1"
    git -C "${ENTITY_WORK}" push -q origin main
}

# run_main runs detect.sh as a subprocess with a valid L1 entity configuration plus overrides.
run_main() {
    run --separate-stderr env -C "${ENTITY_WORK}" \
        DETECT_SCRIPT="${BATS_TEST_TMPDIR}/detect.sh" \
        LOOP_NAME="github-issue-triage" \
        AGENT_MAKER_SKILL_NAME="github-issue-triage" \
        BUDGET_FILE="${BATS_TEST_TMPDIR}/budget.json" \
        RUN_LOG_FILE=".loop/loop-run-log.md" \
        STATE_BRANCH="main" \
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
    entity_sandbox
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
detect_env_json
detect_script
finalize_label_allowlist
finalize_script
github_token
handoff_artifact_suffix
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
        delivery finalize_label_allowlist finalize_script level; do
        upper="$(tr '[:lower:]' '[:upper:]' <<< "${name}")"
        run grep -Fx "        ${upper}: \${{ inputs.${name} }}" "${ACTION_YML}"
        [ "$status" -eq 0 ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 8 ]
    run grep -E 'DISPATCH_HOOK|MAY_EDIT|WRITE_TARGET' "${ACTION_YML}"
    [ "$status" -eq 1 ]
}

@test "main fails on each invalid configuration without outputs" {
    entity_detect_write_mock_script "${BATS_TEST_TMPDIR}/detect.sh" '{"status":"ok","skip":false,"result":{"handoff_key":"entity:issue:1","entity":{"kind":"issue"}}}'
    local -a cases=(
        'LEVEL=|::error::level is required (L1, L2, or L3)'
        'DELIVERY=|::error::delivery must be none or issue_comment at L1 (got: empty)'
        'AGENT_EDIT_ALLOWLIST=**|::error::agent_edit_allowlist is not allowed at L1 (L1 is read-only)'
        'LEVEL=L2 AGENT_EDIT_TARGET=fix AGENT_EDIT_ALLOWLIST=** AGENT_UNCHANGED_VERDICT=REJECT DELIVERY=|::error::delivery must be issue_comment|issue_create|none|pr_create|pr_push|pr_review (got: empty)'
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
    run grep -Fx 'skip_reason=domain:detect' "${GITHUB_OUTPUT}"
    [ "$status" -eq 0 ]
    run grep -Fx 'skip_detail=' "${GITHUB_OUTPUT}"
    [ "$status" -eq 0 ]
}

@test "main publishes the detect skip_reason slug and message as skip_detail" {
    entity_detect_write_mock_script "${BATS_TEST_TMPDIR}/detect.sh" '{"status":"ok","skip":true,"skip_reason":"already_reviewed","message":"marker review exists for abc123","result":{}}'
    run_main
    [ "$status" -eq 0 ]
    run grep -Fx 'skip_reason=domain:already_reviewed' "${GITHUB_OUTPUT}"
    [ "$status" -eq 0 ]
    run grep -Fx 'skip_detail=marker review exists for abc123' "${GITHUB_OUTPUT}"
    [ "$status" -eq 0 ]
}

@test "main falls back to domain:detect when the detect skip_reason is not a slug" {
    entity_detect_write_mock_script "${BATS_TEST_TMPDIR}/detect.sh" '{"status":"ok","skip":true,"skip_reason":"Bad Reason!","message":"x","result":{}}'
    run_main
    [ "$status" -eq 0 ]
    run grep -Fx 'skip_reason=domain:detect' "${GITHUB_OUTPUT}"
    [ "$status" -eq 0 ]
}

@test "main publishes skip_detail on one line, redacted and cut to 300 characters" {
    local long
    long="$(printf 'a%.0s' {1..400})"
    entity_detect_write_mock_script "${BATS_TEST_TMPDIR}/detect.sh" \
        "{\"status\":\"ok\",\"skip\":true,\"message\":\"line one\\nline two token=abc123secret ${long}\",\"result\":{}}"
    run_main
    [ "$status" -eq 0 ]
    [ "$(grep -c '^skip_detail=' "${GITHUB_OUTPUT}")" -eq 1 ]
    run grep -F 'skip_detail=line one line two token=[REDACTED]' "${GITHUB_OUTPUT}"
    [ "$status" -eq 0 ]
    run grep -F 'abc123secret' "${GITHUB_OUTPUT}"
    [ "$status" -eq 1 ]
    [ "$(grep '^skip_detail=' "${GITHUB_OUTPUT}" | cut -d= -f2- | wc -c)" -le 302 ]
}

@test "action.yml exposes skip_detail from the detect step" {
    run grep -F 'steps.detect.outputs.skip_detail' "${ACTION_YML}"
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

@test "main keeps the detect JSON out of the published prompt and stores the full JSON in the handoff payload" {
    local matrix payload_file
    # About 200 KB of comment bodies: far beyond what a job output may carry.
    head -c 200000 /dev/zero | tr '\0' 'x' > "${BATS_TEST_TMPDIR}/big.txt"
    jq -nc --rawfile big "${BATS_TEST_TMPDIR}/big.txt" '{status:"ok",skip:false,result:{handoff_key:"entity:issue:9",entity:{kind:"issue"},issue_number:9,comments:[{body:$big}]}}' > "${BATS_TEST_TMPDIR}/detect.sh.json"
    printf '#!/bin/bash\ncat "%s/detect.sh.json"\n' "${BATS_TEST_TMPDIR}" > "${BATS_TEST_TMPDIR}/detect.sh"
    chmod +x "${BATS_TEST_TMPDIR}/detect.sh"

    run_main
    [ "$status" -eq 0 ]
    matrix="$(github_output_matrix)"
    # The published matrix carries the marker, not the JSON.
    [ "${#matrix}" -lt 20000 ]
    [[ ${matrix} == *"__LOOP_DETECT_RESULT_JSON__"* ]]
    [[ ${matrix} != *"xxxxxxxxxxxxxxxxxxxx"* ]]
    # The handoff payload holds the full detect JSON that the skills read (status, skip, result.*).
    payload_file="$(find "${RUNNER_TEMP}/loop-handoff" -type f -name '*.json' | head -1)"
    [ -n "${payload_file}" ]
    [ "$(jq -r '.result.status' "${payload_file}")" = "ok" ]
    [ "$(jq -r '.result.result.issue_number' "${payload_file}")" = "9" ]
    [ "$(jq -r '.result.result.comments[0].body | length' "${payload_file}")" = "200000" ]
}

@test "main passes detect_env_json entries to the detect script only" {
    local payload='{"status":"ok","skip":false,"result":{"handoff_key":"entity:issue:9","entity":{"kind":"issue"},"issue_number":9,"event_name":"issues","event_action":"opened"},"verifier_context":"Issue #9"}'
    printf '%s\n' "${payload}" > "${BATS_TEST_TMPDIR}/detect.sh.json"
    # shellcheck disable=SC2016 # the generated script expands ENTITY_T_VALUE when it runs
    printf '#!/bin/bash\nprintf %%s "${ENTITY_T_VALUE-unset}" > "%s/seen"\ncat "%s/detect.sh.json"\n' \
        "${BATS_TEST_TMPDIR}" "${BATS_TEST_TMPDIR}" > "${BATS_TEST_TMPDIR}/detect.sh"
    chmod +x "${BATS_TEST_TMPDIR}/detect.sh"
    run_main DETECT_ENV_JSON='{"ENTITY_T_VALUE":"seen-by-script"}'
    [ "$status" -eq 0 ]
    [ "$(cat "${BATS_TEST_TMPDIR}/seen")" = "seen-by-script" ]
    [ ! -s "${GITHUB_ENV:-/dev/null}" ]
}

@test "main rejects reserved detect_env_json keys without running the detect script" {
    entity_detect_write_mock_script "${BATS_TEST_TMPDIR}/detect.sh" '{"status":"ok","skip":true}'
    run_main DETECT_ENV_JSON='{"GIT_DIR":"/tmp"}'
    [ "$status" -eq 1 ]
    [[ $stderr == *"detect_env_json key is reserved: GIT_DIR"* ]]
    [ ! -s "${GITHUB_OUTPUT}" ]
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
    entity_publish_file ".loop/loop-run-log.md" "{\"loop_name\":\"github-issue-triage\",\"run_id\":\"$(date -u +%Y-%m-%d)T12:00:00Z\"}"
    run_main BUDGET_MAX_RUNS_PER_DAY="1"
    [ "$status" -eq 0 ]
    run grep -Fx 'should_run=false' "${GITHUB_OUTPUT}"
    [ "$status" -eq 0 ]
    run grep -Fx 'skip_reason=budget' "${GITHUB_OUTPUT}"
    [ "$status" -eq 0 ]
    run grep -Fx 'pr_auto_merge=false' "${GITHUB_OUTPUT}"
    [ "$status" -eq 0 ]
}

@test "main skips with the admission reason when result.gate refuses the entity" {
    entity_detect_write_mock_script "${BATS_TEST_TMPDIR}/detect.sh" \
        '{"status":"ok","skip":false,"result":{"handoff_key":"entity:issue:1","entity":{"kind":"issue"},"gate":{"entity":{"kind":"issue","number":1,"state":"closed"}}}}'
    run_main
    [ "$status" -eq 0 ]
    run grep -Fx 'should_run=false' "${GITHUB_OUTPUT}"
    [ "$status" -eq 0 ]
    run grep -Fx 'skip_reason=entity_closed' "${GITHUB_OUTPUT}"
    [ "$status" -eq 0 ]
    run grep -Fx 'skip_detail=entity state is closed' "${GITHUB_OUTPUT}"
    [ "$status" -eq 0 ]
}

@test "main proceeds when result.gate admits the entity" {
    entity_detect_write_mock_script "${BATS_TEST_TMPDIR}/detect.sh" \
        '{"status":"ok","skip":false,"result":{"handoff_key":"entity:issue:1","entity":{"kind":"issue"},"gate":{"entity":{"kind":"issue","number":1,"state":"open"}}}}'
    run_main
    [ "$status" -eq 0 ]
    run grep -Fx 'should_run=true' "${GITHUB_OUTPUT}"
    [ "$status" -eq 0 ]
}

@test "main applies the circuit breaker from the state file to the entity key" {
    local today
    today="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    entity_publish_file ".loop/state-test.json" "{\"targets\":{\"entity:issue:1\":{\"consecutive_failures\":3,\"last_run\":\"${today}\"}}}"
    entity_detect_write_mock_script "${BATS_TEST_TMPDIR}/detect.sh" \
        '{"status":"ok","skip":false,"result":{"handoff_key":"entity:issue:1","entity":{"kind":"issue"},"gate":{"entity":{"kind":"issue","number":1,"state":"open"}}}}'
    run_main STATE_FILE=".loop/state-test.json"
    [ "$status" -eq 0 ]
    run grep -Fx 'skip_reason=circuit_breaker' "${GITHUB_OUTPUT}"
    [ "$status" -eq 0 ]
}

@test "main reads the circuit breaker from origin state branch, not from the checked-out tree" {
    local today
    today="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    entity_publish_file ".loop/state-test.json" "{\"targets\":{\"entity:issue:1\":{\"consecutive_failures\":3,\"last_run\":\"${today}\"}}}"
    # A feature branch with a stale, clean copy of the state file is what a PR head looks like.
    git -C "${ENTITY_WORK}" checkout -q -b feature/pr-head
    printf '%s\n' '{"targets":{}}' > "${ENTITY_WORK}/.loop/state-test.json"
    git -C "${ENTITY_WORK}" commit -q -am "stale state"
    entity_detect_write_mock_script "${BATS_TEST_TMPDIR}/detect.sh" \
        '{"status":"ok","skip":false,"result":{"handoff_key":"entity:issue:1","entity":{"kind":"issue"},"gate":{"entity":{"kind":"issue","number":1,"state":"open"}}}}'
    run_main STATE_FILE=".loop/state-test.json"
    [ "$status" -eq 0 ]
    run grep -Fx 'skip_reason=circuit_breaker' "${GITHUB_OUTPUT}"
    [ "$status" -eq 0 ]
}

@test "main fails when STATE_BRANCH is missing" {
    entity_detect_write_mock_script "${BATS_TEST_TMPDIR}/detect.sh" '{"status":"ok","skip":true}'
    run_main STATE_BRANCH=""
    [ "$status" -ne 0 ]
}

@test "read_entity_target_state returns the target state or an empty object" {
    printf '%s\n' '{"targets":{"entity:issue:1":{"consecutive_failures":2}}}' > "${BATS_TEST_TMPDIR}/state.json"
    run read_entity_target_state "${BATS_TEST_TMPDIR}/state.json" "entity:issue:1"
    [ "$output" = '{"consecutive_failures":2}' ]
    run read_entity_target_state "${BATS_TEST_TMPDIR}/state.json" "entity:issue:2"
    [ "$output" = '{}' ]
    run read_entity_target_state "${BATS_TEST_TMPDIR}/missing.json" "entity:issue:1"
    [ "$output" = '{}' ]
    run read_entity_target_state "" "entity:issue:1"
    [ "$output" = '{}' ]
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
