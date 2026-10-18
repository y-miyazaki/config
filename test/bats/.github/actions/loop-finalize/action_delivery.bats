#!/usr/bin/env bats
# shellcheck disable=SC2154

# Tests for delivery branching in .github/actions/loop-finalize/action.yml
#
# Use cases:
# - Materialize Message and Deliver Message wire the loop message; outcome output follows the delivered outcome
# - inputs are the delivery contract (delivery, pr_auto_merge, state_branch, renamed
#   finalize_* / agent_engine / pr_labels) in alphabetical order; removed inputs are gone
# - push, PR creation, and branch deletion branch on inputs.delivery only
# - Enable Auto-Merge runs only on inputs.pr_auto_merge == 'true'
# - no step reads a finalize strategy or an old strategy value
# - Create PR resolves detect JSON from the handoff (no detect_result_json input)
# - Resolve Run Outcome always runs right before Export Failure Diagnostics and owns the outcome output
# - Write State reads the required state_branch and passes finalize_commit_paths
# - Push Agent Branch runs right after Parse Target and is the only reader of inputs.branch;
#   later steps use its validated branch output
# - a failed agent push skips the hook and delivery, forces outcome error and state mode
#   metadata, and Fail Agent Push fails the action before Resolve Run Outcome
# - landing, PR creation, and branch deletion run only after a successful agent push

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

ACTION_YML="$(bats_workspace_root)/.github/actions/loop-finalize/action.yml"

# Print the input names in file order.
action_input_names() {
    awk '
        /^inputs:$/ { in_inputs = 1; next }
        /^[a-z]/ { in_inputs = 0 }
        in_inputs && /^  [a-z_]+:$/ { sub(/^  /, ""); sub(/:$/, ""); print }
    ' "${ACTION_YML}"
}

# Print "KEY: value" lines of the env block of step $1.
step_env() {
    awk -v name="    - name: $1" '
        /^    - name: / { in_step = ($0 == name); in_env = 0; next }
        in_step && /^      env:$/ { in_env = 1; next }
        in_step && in_env && /^        [A-Za-z_][A-Za-z0-9_]*:/ { sub(/^        /, ""); print; next }
        in_step && in_env { in_env = 0 }
    ' "${ACTION_YML}"
}

# Print the if: of step $1 on one line (folded >- blocks joined with spaces).
step_if() {
    awk -v name="    - name: $1" '
        /^    - name: / {
            if (in_if) { print buf; in_if = 0; buf = "" }
            in_step = ($0 == name); next
        }
        in_step && /^      if: >-$/ { in_if = 1; next }
        in_step && /^      if: / { sub(/^      if: /, ""); print; next }
        in_step && in_if && /^        / { sub(/^ +/, ""); buf = buf (buf == "" ? "" : " ") $0; next }
        in_step && in_if { print buf; in_if = 0; buf = "" }
    ' "${ACTION_YML}"
}

# Print the body of the multi-line run: | block of step $1.
step_run() {
    awk -v name="    - name: $1" '
        /^    - name: / { in_step = ($0 == name); in_run = 0; next }
        in_step && /^      run: \|$/ { in_run = 1; next }
        in_step && in_run && /^        / { sub(/^        /, ""); print; next }
        in_step && in_run { in_run = 0 }
    ' "${ACTION_YML}"
}

@test "a recorded push failure resolves to error" {
    local cmd
    cmd="$(awk '
        /^    - name: / { in_step = ($0 == "    - name: Resolve Run Outcome"); next }
        in_step && /^      run: / { sub(/^      run: /, ""); print }
    ' "${ACTION_YML}")"
    [ -n "${cmd}" ]
    # shellcheck disable=SC1091
    source "$(bats_workspace_root)/.github/actions/lib/loop/failure_record.sh"
    loop_failure_record push "agent branch push failed" "${BATS_TEST_TMPDIR}/failure.json"
    run env GITHUB_ACTION_PATH="$(bats_workspace_root)/.github/actions/loop-finalize" \
        ACTION_STATUS=failure DELIVERED_OUTCOME=error AGENT_RESULT=success \
        LOOP_FAILURE_FILE="${BATS_TEST_TMPDIR}/failure.json" \
        GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/output" \
        bash -c "${cmd}"
    [ "${status}" -eq 0 ]
    grep -qx 'outcome=error' "${BATS_TEST_TMPDIR}/output"
    [ "$(jq -r '.failure_stage' "${BATS_TEST_TMPDIR}/failure.json")" = "push" ]
}

@test "action has no finalize strategy or old strategy values" {
    run grep -c -E 'finalize_strategy|FINALIZE_STRATEGY|open_pr|push_head|inputs\.auto_merge|inputs\.base_branch|state_push_branch|detect_result_json|domain_persistence|additional_commit_paths|inputs\.outcome_override|inputs\.engine|inputs\.labels' "${ACTION_YML}"
    [ "${output}" = "0" ]
}

@test "action inputs are the delivery contract in alphabetical order" {
    local expected
    expected="$(printf '%s\n' \
        agent_branch_prefix agent_bundle_dir agent_edit_allowlist agent_edit_denylist agent_engine \
        agent_failure_message agent_failure_stage agent_maker_skill_name agent_result branch current_sha delivery \
        finalize_commit_paths finalize_label_allowlist finalize_outcome_override \
        finalize_script github_token handoff_dir handoff_key has_changes level \
        loop_name message_json notify_context_json open_rejections pr_auto_merge pr_body pr_draft \
        pr_labels pr_title reject_reason skip_reason state_branch state_file \
        target_json usage_json verdict)"
    run action_input_names
    [ "${status}" -eq 0 ]
    [ "${output}" = "${expected}" ]
}

@test "create pr runs only for delivery pr_create" {
    run step_if "Create PR"
    [ "${output}" = "inputs.verdict == 'APPROVE' && steps.agent_push.outputs.pushed == 'true' && inputs.delivery == 'pr_create'" ]
}

@test "create pr reads detect JSON from the handoff and the PR base from the target" {
    run step_env "Create PR"
    [ "${status}" -eq 0 ]
    [[ ${output} == *$'HANDOFF_KEY: ${{ inputs.handoff_key }}'* ]]
    [[ ${output} == *$'LOOP_HANDOFF_DIR: ${{ inputs.handoff_dir }}'* ]]
    [[ ${output} == *$'PR_BASE_BRANCH: ${{ steps.target.outputs.pr_base_branch }}'* ]]
    [[ ${output} == *$'AGENT_ENGINE: ${{ inputs.agent_engine }}'* ]]
    [[ ${output} == *$'PR_LABELS: ${{ inputs.pr_labels }}'* ]]
    [[ ${output} != *"DETECT_RESULT_JSON"* ]]
}

@test "delete agent branch keys on REJECT or a delivery that never lands the branch" {
    run step_if "Delete Agent Branch"
    [ "${output}" = "always() && steps.agent_push.outputs.pushed == 'true' && (inputs.verdict == 'REJECT' || inputs.delivery == 'none' || inputs.delivery == 'issue_comment' || inputs.delivery == 'pr_review')" ]
}

@test "determine outcome and state mode receive the push failure" {
    local step
    for step in "Determine Outcome" "Resolve State Write Mode"; do
        run step_env "${step}"
        [[ ${output} == *$'PUSH_FAILED: ${{ steps.agent_push.outputs.failed }}'* ]]
    done
    run grep -c 'determine_outcome "${FINALIZE_OUTCOME_OVERRIDE}" "${AGENT_RESULT}" "${HAS_CHANGES}" "${VERDICT}" "${DELIVERY}" "${PUSH_FAILED}"' "${ACTION_YML}"
    [ "${output}" = "1" ]
    run grep -c 'resolve_state_write_mode "${VERDICT}" "${HAS_CHANGES}" "${DELIVERY}" "${PUSH_FAILED}"' "${ACTION_YML}"
    [ "${output}" = "1" ]
    local action_path
    action_path="$(bats_workspace_root)/.github/actions/loop-finalize"
    step_run "Determine Outcome" > "${BATS_TEST_TMPDIR}/outcome.sh"
    run env GITHUB_ACTION_PATH="${action_path}" GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/outcome.out" \
        AGENT_RESULT=success DELIVERY=pr_push FINALIZE_OUTCOME_OVERRIDE=watch HAS_CHANGES=true \
        PUSH_FAILED=true VERDICT=APPROVE bash "${BATS_TEST_TMPDIR}/outcome.sh"
    [ "${status}" -eq 0 ]
    grep -qx 'value=error' "${BATS_TEST_TMPDIR}/outcome.out"
    step_run "Resolve State Write Mode" > "${BATS_TEST_TMPDIR}/mode.sh"
    run env GITHUB_ACTION_PATH="${action_path}" GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/mode.out" \
        DELIVERY=pr_push HAS_CHANGES=true PUSH_FAILED=true VERDICT=APPROVE bash "${BATS_TEST_TMPDIR}/mode.sh"
    [ "${status}" -eq 0 ]
    grep -qx 'mode=metadata' "${BATS_TEST_TMPDIR}/mode.out"
    run env GITHUB_ACTION_PATH="${action_path}" GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/mode_ok.out" \
        DELIVERY=pr_push HAS_CHANGES=true PUSH_FAILED=false VERDICT=APPROVE bash "${BATS_TEST_TMPDIR}/mode.sh"
    [ "${status}" -eq 0 ]
    grep -qx 'mode=advance' "${BATS_TEST_TMPDIR}/mode_ok.out"
}

@test "deliver message env is alphabetical and uses the planned outcome" {
    run step_env "Deliver Message"
    [ "${status}" -eq 0 ]
    local expected
    expected="$(cat <<'EOF2'
AGENT_ENGINE: ${{ inputs.agent_engine }}
DELIVERY: ${{ inputs.delivery }}
FINALIZE_LABEL_ALLOWLIST: ${{ inputs.finalize_label_allowlist }}
GH_TOKEN: ${{ inputs.github_token }}
GITHUB_REPOSITORY: ${{ github.repository }}
LOOP_FAILURE_FILE: ${{ runner.temp }}/loop-finalize-failure.json
LOOP_MESSAGE_DIR: ${{ runner.temp }}/loop-message
LOOP_NAME: ${{ inputs.loop_name }}
OUTCOME: ${{ steps.outcome.outputs.value }}
RUN_URL: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
TARGET_JSON: ${{ inputs.target_json }}
USAGE_JSON: ${{ inputs.usage_json }}
VERDICT: ${{ inputs.verdict }}
EOF2
)"
    [ "${output}" = "${expected}" ]
}

@test "deliver message runs for issue_comment and pr_review after a successful, non-REJECT agent" {
    run step_if "Deliver Message"
    [ "${output}" = "(inputs.delivery == 'issue_comment' || inputs.delivery == 'pr_review') && inputs.agent_result == 'success' && inputs.verdict != 'REJECT' && steps.agent_push.outputs.failed != 'true'" ]
}

@test "fail agent push runs after delete agent branch and before resolve run outcome" {
    run step_if "Fail Agent Push"
    [ "${output}" = "always() && steps.agent_push.outputs.failed == 'true'" ]
    run bash -c "awk '/^    - name: /{sub(/^    - name: /,\"\"); print}' '${ACTION_YML}' | grep -A1 -x 'Delete Agent Branch' | paste -sd, -"
    [ "${output}" = "Delete Agent Branch,Fail Agent Push" ]
    run bash -c "awk '/^    - name: /{sub(/^    - name: /,\"\"); print}' '${ACTION_YML}' | grep -A1 -x 'Fail Agent Push' | paste -sd, -"
    [ "${output}" = "Fail Agent Push,Resolve Run Outcome" ]
    local body
    body="$(awk '
        /^    - name: / { in_step = ($0 == "    - name: Fail Agent Push"); in_run = 0; next }
        in_step && /^      run: \|$/ { in_run = 1; next }
        in_step && in_run && /^        / { sub(/^        /, ""); print; next }
        in_step && in_run { in_run = 0 }
    ' "${ACTION_YML}")"
    [[ ${body} == *"exit 1"* ]]
    run bash -c "${body}"
    [ "${status}" -eq 1 ]
    [[ ${output} == *"::error::loop-finalize: the agent branch was not pushed"* ]]
}

@test "materialize message writes message_json into LOOP_MESSAGE_DIR" {
    local script="${BATS_TEST_TMPDIR}/materialize.sh"
    awk '
        /^    - name: / { in_step = ($0 == "    - name: Materialize Message"); in_run = 0; next }
        in_step && /^      run: \|$/ { in_run = 1; next }
        in_step && in_run && /^        / { sub(/^        /, ""); print; next }
        in_step && in_run { in_run = 0 }
    ' "${ACTION_YML}" > "${script}"
    [ -s "${script}" ]
    run env GITHUB_ACTION_PATH="$(bats_workspace_root)/.github/actions/loop-finalize" \
        LOOP_MESSAGE_DIR="${BATS_TEST_TMPDIR}/msg" MESSAGE_JSON='{"body":"x","labels":null}' \
        bash "${script}"
    [ "${status}" -eq 0 ]
    [ "$(cat "${BATS_TEST_TMPDIR}/msg/message.md")" = "x" ]
}

@test "materialize message is the first step and has the message env" {
    run awk '/^    - name: /{print; exit}' "${ACTION_YML}"
    [ "${output}" = "    - name: Materialize Message" ]
    run step_env "Materialize Message"
    [ "${output}" = $'LOOP_MESSAGE_DIR: ${{ runner.temp }}/loop-message\nMESSAGE_JSON: ${{ inputs.message_json }}' ]
}

@test "outcome output comes from Resolve Run Outcome and write state keeps the delivered outcome" {
    run grep -c 'value: ${{ steps.run_outcome.outputs.outcome }}' "${ACTION_YML}"
    [ "${output}" = "1" ]
    run grep -c 'value: ${{ steps.deliver.outputs.outcome || steps.outcome.outputs.value }}' "${ACTION_YML}"
    [ "${output}" = "0" ]
    run step_env "Write State"
    [[ ${output} == *$'OUTCOME: ${{ steps.deliver.outputs.outcome || steps.outcome.outputs.value }}'* ]]
}

@test "steps run in spec order" {
    local expected
    expected="Materialize Message, Parse Target, Push Agent Branch, Resolve State File, Determine Outcome, Resolve State Write Mode, Run Finalize Hook, Deliver Message, Push to Target Branch, Create PR, Enable Auto-Merge, Write State, Delete Agent Branch, Fail Agent Push, Resolve Run Outcome, Export Failure Diagnostics"
    run bash -c "awk '/^    - name: /{sub(/^    - name: /,\"\"); print}' '${ACTION_YML}' | paste -sd, - | sed 's/,/, /g'"
    [ "${output}" = "${expected}" ]
}

@test "enable auto-merge runs only when pr_auto_merge is true" {
    run step_if "Enable Auto-Merge"
    [ "${output}" = "inputs.pr_auto_merge == 'true'" ]
}

@test "no step after push agent branch reads inputs.branch" {
    run grep -c 'inputs\.branch' "${ACTION_YML}"
    [ "${output}" = "1" ]
    run step_env "Push Agent Branch"
    [[ ${output} == *$'AGENT_BRANCH: ${{ inputs.branch }}'* ]]
    local step
    for step in "Run Finalize Hook" "Push to Target Branch" "Create PR" "Delete Agent Branch"; do
        run step_env "${step}"
        [[ ${output} == *'${{ steps.agent_push.outputs.branch }}'* ]]
    done
}

@test "outcome, state mode, and branch delete read inputs.delivery" {
    local step checked=0
    for step in "Determine Outcome" "Resolve State Write Mode" "Delete Agent Branch" "Parse Target"; do
        run step_env "${step}"
        [[ ${output} == *$'DELIVERY: ${{ inputs.delivery }}'* ]]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 4 ]
}

@test "parse target gates on the required state_branch" {
    run step_env "Parse Target"
    [[ ${output} == *$'STATE_BRANCH: ${{ inputs.state_branch }}'* ]]
}

@test "push agent branch failure gates the hook, delivery, landing and deletion" {
    local step
    for step in "Run Finalize Hook" "Deliver Message"; do
        run step_if "${step}"
        [[ ${output} == *"steps.agent_push.outputs.failed != 'true'"* ]]
    done
    for step in "Push to Target Branch" "Create PR" "Delete Agent Branch"; do
        run step_if "${step}"
        [[ ${output} == *"steps.agent_push.outputs.pushed == 'true'"* ]]
        [[ ${output} != *"inputs.has_changes"* ]]
    done
}

@test "push agent branch runs the lib script with the validated target and no if" {
    run step_if "Push Agent Branch"
    [ -z "${output}" ]
    run awk '
        /^    - name: / { in_step = ($0 == "    - name: Push Agent Branch"); next }
        in_step && /^      (id|run): / { sub(/^      /, ""); print }
    ' "${ACTION_YML}"
    [ "${output}" = $'id: agent_push\nrun: bash "${GITHUB_ACTION_PATH}/lib/push_agent_branch.sh"' ]
    local expected
    expected="$(cat <<'EOF2'
AGENT_BRANCH: ${{ inputs.branch }}
AGENT_BRANCH_PREFIX: ${{ inputs.agent_branch_prefix }}
AGENT_BUNDLE_DIR: ${{ inputs.agent_bundle_dir }}
AGENT_EDIT_ALLOWLIST: ${{ inputs.agent_edit_allowlist }}
AGENT_EDIT_DENYLIST: ${{ inputs.agent_edit_denylist }}
AGENT_MAKER_SKILL_NAME: ${{ inputs.agent_maker_skill_name }}
AGENT_RESULT: ${{ inputs.agent_result }}
BASE_BRANCH: ${{ steps.target.outputs.base_branch }}
GITHUB_TOKEN: ${{ inputs.github_token }}
HAS_CHANGES: ${{ inputs.has_changes }}
LOOP_FAILURE_FILE: ${{ runner.temp }}/loop-finalize-failure.json
STATE_BRANCH: ${{ inputs.state_branch }}
TARGET_JSON: ${{ inputs.target_json }}
TO_BRANCH: ${{ steps.target.outputs.to_branch }}
EOF2
)"
    run step_env "Push Agent Branch"
    [ "${output}" = "${expected}" ]
}

@test "push to target branch runs only for delivery pr_push" {
    run step_if "Push to Target Branch"
    [ "${output}" = "inputs.verdict == 'APPROVE' && steps.agent_push.outputs.pushed == 'true' && inputs.delivery == 'pr_push'" ]
}

@test "write state reads state_branch and finalize_commit_paths" {
    run step_env "Write State"
    [ "${status}" -eq 0 ]
    [[ ${output} == *$'FINALIZE_COMMIT_PATHS: ${{ inputs.finalize_commit_paths }}'* ]]
    [[ ${output} == *$'STATE_BRANCH: ${{ inputs.state_branch }}'* ]]
    [[ ${output} != *"BASE_BRANCH"* ]]
    [[ ${output} != *"STATE_PUSH_BRANCH"* ]]
}

@test "every failure record step uses the same LOOP_FAILURE_FILE" {
    local step count=0
    for step in "Push Agent Branch" "Deliver Message" "Create PR" "Resolve Run Outcome" "Export Failure Diagnostics"; do
        run step_env "${step}"
        [[ ${output} == *$'LOOP_FAILURE_FILE: ${{ runner.temp }}/loop-finalize-failure.json'* ]]
        count=$((count + 1))
    done
    [ "${count}" -eq 5 ]
}

@test "resolve run outcome always runs with the action status and the delivered outcome" {
    run step_if "Resolve Run Outcome"
    [ "${output}" = "always()" ]
    local expected
    expected="$(cat <<'EOF2'
ACTION_STATUS: ${{ github.action_status }}
AGENT_FAILURE_MESSAGE: ${{ inputs.agent_failure_message }}
AGENT_FAILURE_STAGE: ${{ inputs.agent_failure_stage }}
AGENT_RESULT: ${{ inputs.agent_result }}
DELIVERED_OUTCOME: ${{ steps.deliver.outputs.outcome || steps.outcome.outputs.value }}
LOOP_FAILURE_FILE: ${{ runner.temp }}/loop-finalize-failure.json
EOF2
)"
    run step_env "Resolve Run Outcome"
    [ "${output}" = "${expected}" ]
}

@test "resolve run outcome runs the lib script" {
    local cmd
    cmd="$(awk '
        /^    - name: / { in_step = ($0 == "    - name: Resolve Run Outcome"); next }
        in_step && /^      run: / { sub(/^      run: /, ""); print }
    ' "${ACTION_YML}")"
    [ -n "${cmd}" ]
    run env GITHUB_ACTION_PATH="$(bats_workspace_root)/.github/actions/loop-finalize" \
        ACTION_STATUS=failure DELIVERED_OUTCOME=pr_created AGENT_RESULT=success \
        LOOP_FAILURE_FILE="${BATS_TEST_TMPDIR}/failure.json" \
        GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/output" \
        bash -c "${cmd}"
    [ "${status}" -eq 0 ]
    grep -qx 'outcome=error' "${BATS_TEST_TMPDIR}/output"
    grep -q '"finalize"' "${BATS_TEST_TMPDIR}/failure.json"
}
