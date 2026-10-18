#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-finalize/lib/resolve_run_outcome.sh
# and, until its removal, the finalize-l2 run-log decisions in .github/workflows/ci-loop-agent.yaml

# Use cases:
# - L2_CASES is a faithful transcription of the current finalize-l2 Resolve Run Log Metadata and outcome expression
# - every L2_CASES row resolves to the transcribed outcome, failure stage and message
# - intended differences from the transcription: cancelled composite, finalize record with a success status, L1 agent_execute, pr_push landing failure
# - the outcome is resolved before the agent stage is recorded
# - re-recording an already recorded agent message leaves it unchanged
# - LOOP_FAILURE_FILE is required

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

# Rows transcribed from ci-loop-agent.yaml finalize-l2 (Resolve Run Log Metadata
# :597-631 and the Append Run Log outcome expression :645) before their removal.
# Columns: name|agent_result|agent_stage|agent_message|action_status|record_stage|
#   record_message|delivered_outcome|outcome|failure_stage|failure_message
L2_CASES="$(cat <<'EOT'
success_created|success|||success|||pr_created|pr_created||
rejected|success|||success|||rejected|rejected||
unchanged|success|||success|||unchanged|unchanged||
watch_override|success|||success|||watch|watch||
agent_failed_no_stage|failure|||success|||error|error|agent_execute|
agent_failed_with_stage|failure|push|remote rejected|success|||error|error|push|remote rejected
agent_stage_on_success|success|notify_context|detect result JSON is invalid (inline)|success|||pr_created|pr_created|notify_context|detect result JSON is invalid (inline)
finalize_record|success|||failure|finalize_pr|gh pr create failed|pr_created|error|finalize_pr|gh pr create failed
finalize_record_over_agent_stage|failure|push|remote rejected|failure|finalize_pr|gh pr create failed|error|error|finalize_pr|gh pr create failed
deliver_record|success|||failure|deliver_message|Failed to post: HTTP 502|pr_reviewed|error|deliver_message|Failed to post: HTTP 502
before_determine_outcome|success|||failure||||error|finalize|
finalize_failed_keeps_agent_stage|failure|push|remote rejected|failure|||error|error|push|remote rejected
finalize_failed_keeps_agent_execute|failure|||failure|||error|error|agent_execute|
push_target_failed_no_record|success|||failure|||pr_pushed|error|finalize|
EOT
)"

#######################################
# output_value: Read a value from a GITHUB_OUTPUT file (KEY=v or KEY<<D forms)
# The delimiter may match its own line or end the last body line (the current
# YAML at :628-629 appends it to the message line).
#
# Arguments:
#   $1 - key
#   $2 - GITHUB_OUTPUT file
#
# Outputs:
#   Value (empty when the key is absent)
#######################################
output_value() {
    awk -v k="$1" '
        function flush() { if (found) { printf "%s", val } }
        BEGIN { found = 0; inml = 0 }
        {
            if (inml) {
                if ($0 == delim) { inml = 0; next }
                n = length($0); d = length(delim)
                if (n > d && substr($0, n - d + 1) == delim) {
                    val = val (nl ? "\n" : "") substr($0, 1, n - d)
                    inml = 0
                    next
                }
                val = val (nl ? "\n" : "") $0
                nl = 1
                next
            }
            if (index($0, k "<<") == 1) {
                delim = substr($0, length(k) + 3); inml = 1; val = ""; nl = 0; found = 1; next
            }
            if (index($0, k "=") == 1) { val = substr($0, length(k) + 2); found = 1 }
        }
        END { flush() }
    ' "$2"
}

#######################################
# current_l2_outcome: Transcription of the ci-loop-agent.yaml:645 expression
#
# Arguments:
#   $1 - steps.finalize.outcome
#   $2 - steps.finalize.outputs.outcome
#   $3 - needs.agent-l2.result
#   $4 - needs.agent-l2.outputs.verdict
#
# Outputs:
#   Outcome
#######################################
current_l2_outcome() {
    local step_result="$1" finalize_outcome="$2" agent_result="$3" verdict="$4"
    if [[ ${step_result} == "failure" ]]; then
        echo "error"
    elif [[ -n ${finalize_outcome} ]]; then
        echo "${finalize_outcome}"
    elif [[ ${agent_result} != "success" && ${agent_result} != "skipped" ]]; then
        echo "error"
    elif [[ ${verdict} == "REJECT" ]]; then
        echo "rejected"
    else
        echo "unchanged"
    fi
}

SCRIPT="$(bats_workspace_root)/.github/actions/loop-finalize/lib/resolve_run_outcome.sh"

setup() {
    bats_source_rel ".github/actions/lib/loop/failure_record.sh"
    LOOP_FAILURE_FILE="${BATS_TEST_TMPDIR}/failure.json"
    GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/github_output"
    export GITHUB_OUTPUT LOOP_FAILURE_FILE
}

#######################################
# run_case: Run the script once and set RUN_OUTCOME, RUN_STAGE, RUN_MESSAGE
#
# Arguments:
#   $1 - AGENT_RESULT
#   $2 - AGENT_STAGE
#   $3 - AGENT_MESSAGE
#   $4 - ACTION_STATUS
#   $5 - RECORD_STAGE (recorded first when non-empty)
#   $6 - RECORD_MESSAGE
#   $7 - DELIVERED
#######################################
run_case() {
    rm -f "${LOOP_FAILURE_FILE}" "${GITHUB_OUTPUT}"
    if [[ -n ${5} ]]; then
        loop_failure_record "${5}" "${6}" "${LOOP_FAILURE_FILE}"
    fi
    run env \
        ACTION_STATUS="${4}" \
        AGENT_FAILURE_MESSAGE="${3}" \
        AGENT_FAILURE_STAGE="${2}" \
        AGENT_RESULT="${1}" \
        DELIVERED_OUTCOME="${7}" \
        bash "${SCRIPT}"
    RUN_OUTCOME="$(output_value outcome "${GITHUB_OUTPUT}")"
    RUN_STAGE=""
    RUN_MESSAGE=""
    if [[ -f ${LOOP_FAILURE_FILE} ]]; then
        RUN_STAGE="$(jq -r '.failure_stage // ""' "${LOOP_FAILURE_FILE}")"
        RUN_MESSAGE="$(jq -r '.failure_message // ""' "${LOOP_FAILURE_FILE}")"
    fi
}

#######################################
# run_named_case: run_case with the inputs of an L2_CASES row
#
# Arguments:
#   $1 - row name
#   Sets ROW_OUTCOME, ROW_STAGE, ROW_MESSAGE to the transcribed expectations
#######################################
run_named_case() {
    local name agent_result agent_stage agent_message action_status record_stage record_message delivered
    local row
    row="$(grep "^${1}|" <<< "${L2_CASES}")"
    IFS='|' read -r name agent_result agent_stage agent_message action_status record_stage record_message delivered ROW_OUTCOME ROW_STAGE ROW_MESSAGE <<< "${row}"
    run_case "${agent_result}" "${agent_stage}" "${agent_message}" "${action_status}" "${record_stage}" "${record_message}" "${delivered}"
}

@test "a cancelled composite is error and records finalize" {
    run_case success "" "" cancelled "" "" pr_created
    [ "${status}" -eq 0 ]
    [ "${RUN_OUTCOME}" = "error" ]
    [ "${RUN_STAGE}" = "finalize" ]
    [ "${RUN_MESSAGE}" = "" ]
}

@test "a finalize record makes the outcome error even when the action status is success" {
    run_case success "" "" success finalize_pr x pr_created
    [ "${status}" -eq 0 ]
    [ "${RUN_OUTCOME}" = "error" ]
    [ "${RUN_STAGE}" = "finalize_pr" ]
    [ "${RUN_MESSAGE}" = "x" ]
}

@test "an L1 agent failure records agent_execute" {
    run_case failure "" "" success "" "" error
    [ "${status}" -eq 0 ]
    [ "${RUN_OUTCOME}" = "error" ]
    [ "${RUN_STAGE}" = "agent_execute" ]
    [ "${RUN_MESSAGE}" = "" ]
}

@test "current finalize-l2 run log metadata and outcome match L2_CASES" {
    local yaml script checked=0 out_file
    local name agent_result agent_stage agent_message action_status record_stage record_message delivered_outcome outcome failure_stage failure_message
    local got_stage got_message got_outcome

    yaml="$(bats_workspace_root)/.github/workflows/ci-loop-agent.yaml"
    script="$(awk '/^      - name: Resolve Run Log Metadata$/ {f=1; next} f && /^        run: \|$/ {r=1; next} r && /^          / {sub(/^          /, ""); print; next} r {exit}' "${yaml}")"
    [ -n "${script}" ]
    grep -qxF "          outcome: \${{ steps.finalize.outcome == 'failure' && 'error' || steps.finalize.outputs.outcome || (needs.agent-l2.result != 'success' && needs.agent-l2.result != 'skipped' && 'error') || (needs.agent-l2.outputs.verdict == 'REJECT' && 'rejected') || 'unchanged' }}" "${yaml}"

    out_file="${BATS_TEST_TMPDIR}/github_output"
    while IFS='|' read -r name agent_result agent_stage agent_message action_status record_stage record_message delivered_outcome outcome failure_stage failure_message; do
        : > "${out_file}"
        GITHUB_OUTPUT="${out_file}" \
            AGENT_RESULT="${agent_result}" \
            EXEC_FAILURE_STAGE="${agent_stage}" \
            EXEC_FAILURE_MESSAGE="${agent_message}" \
            FINALIZE_STEP_RESULT="${action_status}" \
            FINALIZE_FAILURE_STAGE="${record_stage}" \
            FINALIZE_FAILURE_MESSAGE="${record_message}" \
            bash -c "${script}"
        got_stage="$(output_value failure_stage "${out_file}")"
        got_message="$(output_value failure_message "${out_file}")"
        got_outcome="$(current_l2_outcome "${action_status}" "${delivered_outcome}" "${agent_result}" "")"
        if [[ ${got_stage} != "${failure_stage}" ]]; then
            echo "case ${name}: failure_stage '${got_stage}' != '${failure_stage}'" >&2
            return 1
        fi
        if [[ ${got_message} != "${failure_message}" ]]; then
            echo "case ${name}: failure_message '${got_message}' != '${failure_message}'" >&2
            return 1
        fi
        if [[ ${got_outcome} != "${outcome}" ]]; then
            echo "case ${name}: outcome '${got_outcome}' != '${outcome}'" >&2
            return 1
        fi
        checked=$((checked + 1))
    done <<< "${L2_CASES}"
    [ "${checked}" -eq 14 ]
}

@test "every L2_CASES row resolves to the transcribed outcome, stage and message" {
    local checked=0 name
    while IFS='|' read -r name _; do
        run_named_case "${name}"
        if [[ ${status} -ne 0 || ${RUN_OUTCOME} != "${ROW_OUTCOME}" || ${RUN_STAGE} != "${ROW_STAGE}" || ${RUN_MESSAGE} != "${ROW_MESSAGE}" ]]; then
            echo "case ${name}: status=${status} outcome='${RUN_OUTCOME}' stage='${RUN_STAGE}' message='${RUN_MESSAGE}'" >&2
            return 1
        fi
        checked=$((checked + 1))
    done <<< "${L2_CASES}"
    [ "${checked}" -eq 14 ]
}

@test "fails without LOOP_FAILURE_FILE" {
    rm -f "${GITHUB_OUTPUT}"
    run env -u LOOP_FAILURE_FILE ACTION_STATUS=success AGENT_RESULT=success DELIVERED_OUTCOME=unchanged bash "${SCRIPT}"
    [ "${status}" -eq 1 ]
    [[ ${output} == *"::error::LOOP_FAILURE_FILE is required"* ]]
    ! grep -q '^outcome=' "${GITHUB_OUTPUT}" 2> /dev/null
}

@test "outcome is resolved before the agent stage is recorded" {
    run_named_case agent_stage_on_success
    [ "${status}" -eq 0 ]
    [ "${RUN_STAGE}" = "notify_context" ]
    [ "${RUN_OUTCOME}" = "pr_created" ]
}

@test "pr_push landing failure is error for notify and run log alike" {
    run_named_case push_target_failed_no_record
    [ "${status}" -eq 0 ]
    [ "${RUN_OUTCOME}" = "error" ]
    [ "${RUN_STAGE}" = "finalize" ]
}

@test "re-recording a recorded agent message keeps it unchanged" {
    local recorded src long
    long="$(printf 'a%.0s' {1..600})"
    for src in "auth failed: x-access-token:ghp_abcdefghijklmnopqrstuvwxyz" "${long}"; do
        loop_failure_record "push" "${src}" "${BATS_TEST_TMPDIR}/first.json"
        recorded="$(jq -r '.failure_message' "${BATS_TEST_TMPDIR}/first.json")"
        rm -f "${LOOP_FAILURE_FILE}" "${GITHUB_OUTPUT}"
        run env ACTION_STATUS=success AGENT_FAILURE_MESSAGE="${recorded}" AGENT_FAILURE_STAGE=push AGENT_RESULT=success DELIVERED_OUTCOME=pr_created bash "${SCRIPT}"
        [ "${status}" -eq 0 ]
        [ "$(jq -r '.failure_message' "${LOOP_FAILURE_FILE}")" = "${recorded}" ]
    done
    [[ ${recorded} == *"aaaa"* ]]
    [ "${#recorded}" -eq 500 ]
    loop_failure_record "push" "auth failed: x-access-token:ghp_abcdefghijklmnopqrstuvwxyz" "${BATS_TEST_TMPDIR}/first.json"
    [[ "$(jq -r '.failure_message' "${BATS_TEST_TMPDIR}/first.json")" == *"[REDACTED]"* ]]
    [[ "$(jq -r '.failure_message' "${BATS_TEST_TMPDIR}/first.json")" != *"ghp_"* ]]
}

@test "writes no failure record when nothing failed" {
    local name
    for name in success_created rejected unchanged watch_override; do
        run_named_case "${name}"
        [ "${status}" -eq 0 ]
        run loop_failure_recorded "${LOOP_FAILURE_FILE}"
        [ "${status}" -eq 1 ]
    done
}
