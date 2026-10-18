#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-finalize/lib/resolve_run_outcome.sh
# and, until its removal, the finalize-l2 run-log decisions in .github/workflows/ci-loop-agent.yaml

# Use cases:
# - L2_CASES is a faithful transcription of the current finalize-l2 Resolve Run Log Metadata and outcome expression

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
