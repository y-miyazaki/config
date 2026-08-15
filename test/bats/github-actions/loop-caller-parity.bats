#!/usr/bin/env bats

# Contract tests: ci-loop-caller.yaml and ci-loop-caller-entity.yaml share
# platform wiring. Finalize hops live in ci-loop-agent (finalize-l1 / finalize-l2).

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    ROOT="$(bats_workspace_root)"
    BRANCH_CALLER="${ROOT}/.github/workflows/ci-loop-caller.yaml"
    ENTITY_CALLER="${ROOT}/.github/workflows/ci-loop-caller-entity.yaml"
    AGENT="${ROOT}/.github/workflows/ci-loop-agent.yaml"
}

job_if_block() {
    local file="$1"
    local job="$2"
    awk -v job="${job}" '
        $0 ~ "^  " job ":" {flag=1; next}
        flag && /^    if:/ {print; grabbing=1; next}
        grabbing {
            if ($0 ~ /^    [a-z]/ && $0 !~ /^    if:/) {exit}
            print
        }
    ' "${file}"
}

@test "callers use the same auto_merge expression" {
    local branch entity
    branch="$(grep 'auto_merge:' "${BRANCH_CALLER}" | head -1)"
    entity="$(grep 'auto_merge:' "${ENTITY_CALLER}" | head -1)"
    [[ -n ${branch} ]]
    [[ ${branch} == "${entity}" ]]
    [[ ${branch} == *"delivery == 'open_pr'"* ]]
    [[ ${branch} == *"level == 'L3'"* ]]
    [[ ${branch} == *"target_json.finalize == 'open_pr'"* ]]
}

@test "callers use the same may_edit detect mapping" {
    local branch entity
    # Literal GitHub Actions expression; do not expand.
    # shellcheck disable=SC2016
    branch="$(grep -F 'may_edit: ${{ inputs.may_edit' "${BRANCH_CALLER}" | head -1)"
    # shellcheck disable=SC2016
    entity="$(grep -F 'may_edit: ${{ inputs.may_edit' "${ENTITY_CALLER}" | head -1)"
    [[ -n ${branch} ]]
    [[ ${branch} == "${entity}" ]]
    [[ ${branch} == *"== false && 'false' || ''"* ]]
}

@test "both callers pass pr_draft into ci-loop-agent" {
    # Literal GitHub Actions expression; do not expand.
    # shellcheck disable=SC2016
    grep -qF 'pr_draft: ${{ inputs.pr_draft }}' "${BRANCH_CALLER}"
    # shellcheck disable=SC2016
    grep -qF 'pr_draft: ${{ inputs.pr_draft }}' "${ENTITY_CALLER}"
}

@test "entity record-skip logs circuit_breaker and budget like branch caller" {
    grep -A6 'record-skip:' "${ENTITY_CALLER}" | grep -q 'circuit_breaker'
    grep -A6 'record-skip:' "${ENTITY_CALLER}" | grep -q "skip_reason == 'budget'"
}

@test "both callers reference the same ci-loop-agent workflow" {
    local branch entity
    branch="$(grep 'ci-loop-agent.yaml' "${BRANCH_CALLER}" | head -1)"
    entity="$(grep 'ci-loop-agent.yaml' "${ENTITY_CALLER}" | head -1)"
    [[ ${branch} == "${entity}" ]]
    [[ -n ${branch} ]]
    [[ ${branch} == *"ci-loop-agent.yaml"* ]]
}

@test "ci-loop-agent has finalize-l1 and finalize-l2 not record-l1" {
    grep -q '^  finalize-l1:' "${AGENT}"
    grep -q '^  finalize-l2:' "${AGENT}"
    if grep -q '^  record-l1:' "${AGENT}"; then
        return 1
    fi
    if grep -q '^  finalize:' "${AGENT}"; then
        return 1
    fi
}

@test "finalize-l2 job if does not require finalize_enabled" {
    local block
    block="$(job_if_block "${AGENT}" 'finalize-l2')"
    [[ ${block} == *"inputs.level == 'L2'"* ]]
    if [[ ${block} == *finalize_enabled* ]]; then
        return 1
    fi
}

@test "branch execute waits for ack-trigger success or skip" {
    grep -A6 '^  execute:' "${BRANCH_CALLER}" | grep -q 'needs.ack-trigger.result'
    grep -A8 '^  execute:' "${BRANCH_CALLER}" | grep -q 'ack-trigger'
}

@test "github-pr-revise caller watches a scoped PR head" {
    local wf="${ROOT}/.github/workflows/on-loop-github-pr-revise.yaml"
    grep -q 'pr_enabled: true' "${wf}"
    grep -q 'scoped_pr_number:' "${wf}"
    grep -q 'pr_exclude: fork,label:no-loop' "${wf}"
}

@test "loop-finalize step is gated on finalize_enabled" {
    grep -B5 'id: finalize' "${AGENT}" | grep -q 'if: inputs.finalize_enabled'
}

@test "finalize-l1 persists run-log after agent-l1" {
    grep -A40 '^  finalize-l1:' "${AGENT}" | grep -q 'loop-run-log'
    grep -A20 '^  finalize-l1:' "${AGENT}" | grep -q "inputs.level == 'L1'"
    grep -A15 '^  finalize-l1:' "${AGENT}" | grep -q 'needs: agent-l1'
}

@test "agent-l1 exposes usage_json and finalize-l1 passes it to run-log" {
    grep -A25 '^  agent-l1:' "${AGENT}" | grep -q 'usage_json:'
    grep -A45 '^  finalize-l1:' "${AGENT}" | grep -q "needs.agent-l1.outputs.usage_json"
}

@test "ci-loop-agent requires loop_name and does not guard run-log on emptiness" {
    grep -A3 '^      loop_name:' "${AGENT}" | grep -q 'required: true'
    if grep -q "inputs.loop_name != ''" "${AGENT}"; then
        return 1
    fi
}

@test "ci-loop-agent does not expose loop-execute internal prompt inputs" {
    if grep -qE '^      prompt_(verifier_|implementer_feedback|file):' "${AGENT}"; then
        return 1
    fi
    if grep -q 'prompt_verifier_' "${AGENT}"; then
        return 1
    fi
    if grep -q 'prompt_implementer_feedback' "${AGENT}"; then
        return 1
    fi
}

@test "ci-loop-agent coalesces empty denylist to platform default for loop-execute" {
    grep -q "inputs.denylist != '' && inputs.denylist ||" "${AGENT}"
}

@test "loop workflows do not use deprecated skill_name or verifier_skill_name inputs" {
    local f
    for f in "${ROOT}"/.github/workflows/on-loop-*.yaml \
        "${ROOT}"/.github/workflows/example/on-loop-*.yaml \
        "${BRANCH_CALLER}" "${ENTITY_CALLER}" \
        "${ROOT}"/.github/actions/loop-detect/action.yml \
        "${ROOT}"/.github/actions/loop-entity-detect/action.yml \
        "${ROOT}"/.github/actions/loop-execute/action.yml \
        "${AGENT}"; do
        if grep -qE '^[[:space:]]+(skill_name|verifier_skill_name):' "${f}"; then
            echo "deprecated skill input in ${f}" >&2
            return 1
        fi
    done
}

@test "callers use symmetric agent_implementer_skill_name and agent_verifier_skill_name inputs" {
    grep -q "^      agent_implementer_skill_name:" "${BRANCH_CALLER}"
    grep -q "^      agent_verifier_skill_name:" "${BRANCH_CALLER}"
    grep -q "^      agent_implementer_skill_name:" "${ENTITY_CALLER}"
    grep -q "^      agent_verifier_skill_name:" "${ENTITY_CALLER}"
}

@test "loop workflows do not use deprecated prompt_instructions input" {
    local f
    for f in "${ROOT}"/.github/workflows/on-loop-*.yaml \
        "${ROOT}"/.github/workflows/example/on-loop-*.yaml \
        "${BRANCH_CALLER}" "${ENTITY_CALLER}" \
        "${ROOT}"/.github/actions/loop-detect/action.yml \
        "${ROOT}"/.github/actions/loop-entity-detect/action.yml; do
        if grep -qE '^[[:space:]]+prompt_instructions:' "${f}"; then
            echo "deprecated prompt_instructions in ${f}" >&2
            return 1
        fi
    done
}

@test "callers use symmetric agent_implementer_instructions and agent_verifier_instructions inputs" {
    grep -q "^      agent_implementer_instructions:" "${BRANCH_CALLER}"
    grep -q "^      agent_verifier_instructions:" "${BRANCH_CALLER}"
    grep -q "^      agent_implementer_instructions:" "${ENTITY_CALLER}"
    grep -q "^      agent_verifier_instructions:" "${ENTITY_CALLER}"
    if grep -qE "^      (prompt_instructions|verifier_criteria|implementer_instructions|verifier_instructions):" "${BRANCH_CALLER}"; then
        return 1
    fi
}

@test "callers use agent_ prefix for agent config inputs" {
    grep -q "^      agent_implementer_max_turns:" "${BRANCH_CALLER}"
    grep -q "^      agent_implementer_model:" "${BRANCH_CALLER}"
    grep -q "^      agent_verifier_max_turns:" "${BRANCH_CALLER}"
    grep -q "^      agent_verifier_model:" "${BRANCH_CALLER}"
    grep -q "^      agent_loop_max_attempts:" "${BRANCH_CALLER}"
    if grep -qE "^      (implementer_max_turns|implementer_model|verifier_max_turns|verifier_model|loop_max_attempts):" "${BRANCH_CALLER}"; then
        return 1
    fi
}

@test "ci-loop-caller workflow_call inputs are alphabetically ordered" {
    mapfile -t keys < <(awk '
        /^    inputs:/ { in_inputs=1; next }
        in_inputs && /^    secrets:/ { exit }
        in_inputs && /^      [a-zA-Z0-9_]+:/ {
            sub(/^      /, "")
            sub(/:.*/, "")
            print
        }
    ' "${BRANCH_CALLER}")
    mapfile -t sorted < <(printf '%s\n' "${keys[@]}" | LC_ALL=C sort)
    [[ ${keys[*]} == "${sorted[*]}" ]]
}

@test "ci-loop-caller detect with block keys are alphabetically ordered" {
    mapfile -t keys < <(awk '
        /id: detect/ { after_detect=1 }
        after_detect && /^        with:/ { in_with=1; next }
        in_with && /^      - name:/ { exit }
        in_with && /^          [a-zA-Z0-9_]+:/ {
            sub(/^          /, "")
            sub(/:.*/, "")
            print
        }
    ' "${BRANCH_CALLER}")
    mapfile -t sorted < <(printf '%s\n' "${keys[@]}" | LC_ALL=C sort)
    [[ ${keys[*]} == "${sorted[*]}" ]]
}

@test "loop action env blocks are alphabetically ordered" {
    local checker
    checker="${ROOT}/scripts/lib/yaml_map_order.py"
    python3 "${checker}" check \
        "${ROOT}/.github/actions/loop-detect/action.yml" \
        "${ROOT}/.github/actions/loop-entity-detect/action.yml" \
        "${ROOT}/.github/actions/loop-execute/action.yml"
}
