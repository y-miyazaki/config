#!/usr/bin/env bats

# Tests for .github/workflows/ci-loop-caller.yaml, .github/workflows/ci-loop-caller-entity.yaml, .github/workflows/ci-loop-agent.yaml
#
# Use cases:
# - Both callers share platform wiring; finalize hops live in ci-loop-agent (finalize-l1 / finalize-l2)
# - Callers declare delivery and level as required with no default
# - agent-l1 holds no issues write and hands the agent's message to finalize-l1 as message_json
# - finalize-l1 runs loop-finalize (empty current_sha and branch) with issues write, warns on a missing message, and logs the finalize outcome
# - finalize-l2 holds issues write; both reusables pass finalize_script and finalize_label_allowlist to detect and ci-loop-agent
# - target_json is required at every level
# - No workflow step edits a message a loop already posted (no Append Loop Meta step)
# - No loop-finalize step or lib/loop script edits a posted comment or review
# - Callers pass the detect outputs delivery and pr_auto_merge straight through (no auto_merge or finalize_enabled expression)
# - ci-loop-agent derives the handoff key, checkout ref and base from target_json and fails closed when it is empty
# - finalize-l2 always runs loop-finalize; loop-run-log receives state_branch with no fallback expression
# - Every with: key on a pinned loop action or ci-loop-agent call is a declared input of the local definition, and every required input is passed
# - No pre-rename input or env name remains in the three reusable workflows
# - Committed .loop state files match the on-loop callers
# - Every dogfood on-loop caller passes only declared inputs and every required input of the local reusable it calls
# - Dogfood callers declare delivery and level per the migration table, pass the level-dependent inputs only on L2+, and repeat no default
# - github-pr-revise watches only its scoped PR head and offers delivery pr_push or pr_create on manual dispatch
# - on-loop-state-promote passes state_branch main and only declared loop-state-promote inputs

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
    ACTIONS_DIR="${ROOT}/.github/actions"
}

# job_block FILE JOB: print the job's lines (header through the line before the next job)
job_block() {
    awk -v job="$2" '
        $0 == "  " job ":" {f=1; print; next}
        f && /^  [a-zA-Z0-9_-]+:/ {exit}
        f && /^[a-z]/ {exit}
        f
    ' "$1"
}

# job_if_block FILE JOB: print the job-level if: expression lines
job_if_block() {
    job_block "$1" "$2" | awk '
        /^    if:/ {print; grabbing=1; next}
        grabbing {
            if ($0 ~ /^    [a-z]/) {exit}
            print
        }
    '
}

# step_block NAME: from stdin job text, print the step named NAME
step_block() {
    awk -v name="$1" '
        $0 == "      - name: " name {f=1; print; next}
        f && /^      - name:/ {exit}
        f
    '
}

# steps_using FILE ACTION: print each step that uses the pinned ACTION, NUL-terminated
steps_using() {
    awk -v needle="/.github/actions/$2@" '
        function emit() { if (buf != "" && index(buf, needle) > 0) printf "%s%c", buf, 0; buf="" }
        /^      - name:/ {emit(); buf=$0 "\n"; next}
        /^  [a-zA-Z0-9_-]+:$/ {emit(); next}
        buf != "" {buf = buf $0 "\n"}
        END {emit()}
    ' "$1"
}

# run_script: from stdin step text, print the run: | body with step indentation removed
run_script() {
    awk '
        /^        run: \|/ {f=1; next}
        f && /^          / {sub(/^          /, ""); print; next}
        f && /^$/ {print; next}
        f {exit}
    '
}

# input_block FILE NAME: print the workflow_call input definition lines for NAME
input_block() {
    awk -v name="$2" '
        /^    inputs:/ {in_inputs=1; next}
        in_inputs && /^    [a-z]/ {exit}
        in_inputs && $0 == "      " name ":" {f=1; next}
        f && /^      [a-zA-Z0-9_]+:/ {exit}
        f
    ' "$1"
}

# workflow_inputs FILE: print declared workflow_call input names
workflow_inputs() {
    awk '
        /^    inputs:/ {in_inputs=1; next}
        in_inputs && /^    [a-z]/ {exit}
        in_inputs && /^      [a-zA-Z0-9_]+:/ {k=$1; sub(/:$/, "", k); print k}
    ' "$1"
}

# workflow_required_inputs FILE: print workflow_call input names with required: true
workflow_required_inputs() {
    awk '
        function emit() { if (k != "" && req == "true") print k; k=""; req="" }
        /^    inputs:/ {in_inputs=1; next}
        in_inputs && /^    [a-z]/ {emit(); exit}
        in_inputs && /^      [a-zA-Z0-9_]+:/ {emit(); k=$1; sub(/:$/, "", k); next}
        in_inputs && /^        required:/ {req=$2}
        END {emit()}
    ' "$1"
}

# action_inputs ACTION: print declared input names of the local ACTION/action.yml
action_inputs() {
    awk '
        /^inputs:/ {f=1; next}
        f && /^[a-z]/ {exit}
        f && /^  [a-zA-Z0-9_]+:/ {k=$1; sub(/:$/, "", k); print k}
    ' "${ACTIONS_DIR}/$1/action.yml"
}

# action_required_inputs ACTION: print input names with required: true in the local action.yml
action_required_inputs() {
    awk '
        function emit() { if (k != "" && req == "true") print k; k=""; req="" }
        /^inputs:/ {f=1; next}
        f && /^[a-z]/ {emit(); exit}
        f && /^  [a-zA-Z0-9_]+:/ {emit(); k=$1; sub(/:$/, "", k); next}
        f && /^    required:/ {req=$2}
        END {emit()}
    ' "${ACTIONS_DIR}/$1/action.yml"
}

# pinned_action_steps FILE: print "ACTION<TAB> key1 key2 ..." for every step that uses a pinned config action
pinned_action_steps() {
    awk '
        function emit() { if (act != "") print act "\t" keys; act=""; keys=""; inwith=0 }
        /^      - name:/ {emit(); next}
        /^  [a-zA-Z0-9_-]+:$/ {emit(); next}
        /^        uses: y-miyazaki\/config\/\.github\/actions\// {
            a=$2; sub(/^y-miyazaki\/config\/\.github\/actions\//, "", a); sub(/@.*/, "", a); act=a; next
        }
        /^        with:/ {inwith=1; next}
        inwith && /^          [a-zA-Z0-9_]+:/ {k=$1; sub(/:$/, "", k); keys = keys " " k; next}
        inwith && /^        [a-z-]/ {inwith=0}
        END {emit()}
    ' "$1"
}

# agent_call_with_keys FILE: print the with: keys of the job that calls ci-loop-agent.yaml
agent_call_with_keys() {
    awk '
        /^    uses: y-miyazaki\/config\/\.github\/workflows\/ci-loop-agent\.yaml@/ {f=1; next}
        f && /^    with:/ {inwith=1; next}
        inwith && /^      [a-zA-Z0-9_]+:/ {k=$1; sub(/:$/, "", k); print k; next}
        inwith && /^    [a-z]/ {exit}
        f && /^  [a-zA-Z0-9_-]+:$/ {exit}
    ' "$1"
}

# dogfood_reusable FILE: print the local reusable workflow path the dogfood caller FILE calls
dogfood_reusable() {
    awk '/^    uses: \.\/\.github\/workflows\/ci-loop-caller/ {sub(/^    uses: \.\//, ""); print; exit}' "$1"
}

# dogfood_with FILE: print the "key: value" lines of the dogfood caller's job-level with: block
dogfood_with() {
    awk '
        /^    uses: \.\/\.github\/workflows\/ci-loop-caller/ {f=1; next}
        f && /^    with:/ {inwith=1; next}
        inwith && /^      [a-zA-Z0-9_]+:/ {sub(/^      /, ""); print; next}
        inwith && /^    [a-z]/ {exit}
    ' "$1"
}

# dogfood_value FILE KEY: print the single-line with: value of KEY in the dogfood caller FILE
dogfood_value() {
    dogfood_with "$1" | awk -v key="$2" 'index($0, key ": ") == 1 {print substr($0, length(key) + 3); exit}'
}

@test ".loop JSON files are state-*, loop-budget, or allowlisted sidecars" {
    local f base
    for f in "${ROOT}"/.loop/*.json; do
        base="$(basename "${f}")"
        case "${base}" in
            state-*.json | loop-budget.json) continue ;;
            *)
                echo "unexpected ${f}" >&2
                return 1
                ;;
        esac
    done
}

@test "agent-l1 has no issues write and exposes message_json without comment inputs" {
    local block
    block="$(job_block "${AGENT}" agent-l1)"
    [[ -n ${block} ]]
    if grep -nE 'issues: write|comment_handoff_key|comment_marker|output_file' <<< "${block}"; then
        return 1
    fi
    # Literal GitHub Actions expression; do not expand.
    # shellcheck disable=SC2016
    grep -qF 'message_json: ${{ steps.agent.outputs.message_json }}' <<< "${block}"
}

@test "no workflow step edits a message a loop already posted" {
    if grep -n 'Append Loop Meta\|append_pr_review_meta' "${AGENT}" "${ROOT}"/.github/workflows/*.yaml; then
        return 1
    fi
}

@test "agent-l1 exposes usage_json and finalize-l1 passes it to run-log" {
    grep -A25 '^  agent-l1:' "${AGENT}" | grep -q 'usage_json:'
    grep -A72 '^  finalize-l1:' "${AGENT}" | grep -q "needs.agent-l1.outputs.usage_json"
}

@test "agent-l2 parse target derives key, ref and base from an integration target_json" {
    local script out
    script="$(job_block "${AGENT}" agent-l2 | step_block 'Parse Target' | run_script)"
    [[ -n ${script} ]]
    out="${BATS_TEST_TMPDIR}/github_output"
    : > "${out}"
    run env GITHUB_OUTPUT="${out}" \
        TARGET_JSON='{"key":"integration:main","mode":"integration","from":{"branch":"main","ref":"abc123"},"to":{"branch":"main"}}' \
        bash -c "${script}"
    [ "$status" -eq 0 ]
    [ "$(cat "${out}")" = "$(printf '%s\n' base_branch=main from_branch=main from_ref=abc123 key=integration:main)" ]
}

@test "agent-l2 parse target fails when target_json is empty, invalid, or lacks a key" {
    local script out target_json
    script="$(job_block "${AGENT}" agent-l2 | step_block 'Parse Target' | run_script)"
    [[ -n ${script} ]]
    out="${BATS_TEST_TMPDIR}/github_output"
    for target_json in '' 'not-json' '{"from":{"branch":"main","ref":"abc"},"to":{"branch":"main"}}'; do
        : > "${out}"
        run env GITHUB_OUTPUT="${out}" TARGET_JSON="${target_json}" bash -c "${script}"
        [ "$status" -ne 0 ]
        [ ! -s "${out}" ]
    done
}

@test "agent-l2 parse target has no base_branch fallback" {
    local block
    block="$(job_block "${AGENT}" agent-l2 | step_block 'Parse Target')"
    [[ -n ${block} ]]
    if grep -qF -e BASE_BRANCH -e inputs.base_branch -e integration: <<< "${block}"; then
        return 1
    fi
}

@test "agent-l2 parse target uses base.branch for a pull_request target" {
    local script out
    script="$(job_block "${AGENT}" agent-l2 | step_block 'Parse Target' | run_script)"
    out="${BATS_TEST_TMPDIR}/github_output"
    : > "${out}"
    run env GITHUB_OUTPUT="${out}" \
        TARGET_JSON='{"key":"pull_request:7","mode":"pull_request","base":{"branch":"main"},"from":{"branch":"feat","ref":"def456"},"to":{"branch":"feat","pr_number":7}}' \
        bash -c "${script}"
    [ "$status" -eq 0 ]
    [ "$(cat "${out}")" = "$(printf '%s\n' base_branch=main from_branch=feat from_ref=def456 key=pull_request:7)" ]
}

@test "both callers pass delivery and pr_auto_merge from detect outputs unchanged" {
    local caller
    for caller in "${BRANCH_CALLER}" "${ENTITY_CALLER}"; do
        # Literal GitHub Actions expressions; do not expand.
        # shellcheck disable=SC2016
        grep -qxF '      delivery: ${{ steps.detect.outputs.delivery }}' "${caller}"
        # shellcheck disable=SC2016
        grep -qxF '      pr_auto_merge: ${{ steps.detect.outputs.pr_auto_merge }}' "${caller}"
        # shellcheck disable=SC2016
        grep -qxF '      delivery: ${{ needs.detect.outputs.delivery }}' "${caller}"
        # shellcheck disable=SC2016
        grep -qxF '      pr_auto_merge: ${{ needs.detect.outputs.pr_auto_merge }}' "${caller}"
    done
}

@test "both callers pass pr_draft into ci-loop-agent" {
    # Literal GitHub Actions expression; do not expand.
    # shellcheck disable=SC2016
    grep -qF 'pr_draft: ${{ inputs.pr_draft }}' "${BRANCH_CALLER}"
    # shellcheck disable=SC2016
    grep -qF 'pr_draft: ${{ inputs.pr_draft }}' "${ENTITY_CALLER}"
}

@test "both callers record every non-run, not just two skip reasons" {
    # record-skip used to enumerate circuit_breaker and budget, which silently
    # dropped no_changes from the run log. Both callers now gate on should_run
    # alone so a quiet tick is distinguishable from a loop that never started.
    local caller
    for caller in "${BRANCH_CALLER}" "${ENTITY_CALLER}"; do
        grep -A6 'record-skip:' "${caller}" | grep -qF "needs.detect.outputs.should_run == 'false'"
        ! grep -A6 'record-skip:' "${caller}" | grep -q "skip_reason == '"
    done
}

@test "both callers reference the same ci-loop-agent workflow" {
    local branch entity
    branch="$(grep 'ci-loop-agent.yaml' "${BRANCH_CALLER}" | head -1)"
    entity="$(grep 'ci-loop-agent.yaml' "${ENTITY_CALLER}" | head -1)"
    [[ ${branch} == "${entity}" ]]
    [[ -n ${branch} ]]
    [[ ${branch} == *"ci-loop-agent.yaml"* ]]
}

@test "both reusables pass finalize_script and finalize_label_allowlist to detect and to ci-loop-agent" {
    local caller detect execute key
    for caller in "${BRANCH_CALLER}" "${ENTITY_CALLER}"; do
        input_block "${caller}" finalize_label_allowlist | grep -qF 'default: ""'
        detect="$(job_block "${caller}" detect | step_block 'Detect Loop Work')"
        execute="$(job_block "${caller}" execute)"
        for key in finalize_label_allowlist finalize_script; do
            grep -qxF "          ${key}: \${{ inputs.${key} }}" <<< "${detect}"
            grep -qxF "      ${key}: \${{ inputs.${key} }}" <<< "${execute}"
        done
    done
    input_block "${AGENT}" finalize_label_allowlist | grep -qF 'default: ""'
}

@test "branch execute waits for ack-trigger success or skip" {
    grep -A6 '^  execute:' "${BRANCH_CALLER}" | grep -q 'needs.ack-trigger.result'
    grep -A8 '^  execute:' "${BRANCH_CALLER}" | grep -q 'ack-trigger'
}

@test "callers carry no auto_merge expression and no finalize_enabled" {
    local caller line
    local -a lines
    for caller in "${BRANCH_CALLER}" "${ENTITY_CALLER}"; do
        if grep -q 'finalize_enabled' "${caller}"; then
            echo "finalize_enabled in ${caller}" >&2
            return 1
        fi
        mapfile -t lines < <(grep 'auto_merge' "${caller}")
        [ "${#lines[@]}" -eq 2 ]
        for line in "${lines[@]}"; do
            # Literal GitHub Actions expressions; do not expand.
            # shellcheck disable=SC2016
            case "${line}" in
                '      pr_auto_merge: ${{ steps.detect.outputs.pr_auto_merge }}' | \
                    '      pr_auto_merge: ${{ needs.detect.outputs.pr_auto_merge }}') ;;
                *)
                    echo "auto_merge expression in ${caller}: ${line}" >&2
                    return 1
                    ;;
            esac
        done
    done
}

@test "callers declare delivery and level as required with no default" {
    local caller name block
    for caller in "${BRANCH_CALLER}" "${ENTITY_CALLER}"; do
        for name in delivery level; do
            block="$(input_block "${caller}" "${name}")"
            [[ -n ${block} ]]
            grep -qxF '        required: true' <<< "${block}"
            if grep -q '^        default:' <<< "${block}"; then
                echo "${name} has a default in ${caller}" >&2
                return 1
            fi
        done
    done
}

@test "callers do not declare or pass removed inputs" {
    local caller name
    for caller in "${BRANCH_CALLER}" "${ENTITY_CALLER}"; do
        for name in may_edit git_landing_integration git_landing_pull_request dispatch_hook_token \
            finalize_enabled detect_result_json handoff_key current_sha auto_merge; do
            if grep -qE "^[[:space:]]+${name}:" "${caller}"; then
                echo "${name} in ${caller}" >&2
                return 1
            fi
        done
        if grep -qE 'target_json\.finalize|matrix\.target\.handoff_key' "${caller}"; then
            echo "removed matrix field read in ${caller}" >&2
            return 1
        fi
    done
}

@test "callers use agent_ prefix for agent config inputs" {
    grep -q "^      agent_maker_max_turns:" "${BRANCH_CALLER}"
    grep -q "^      agent_maker_model:" "${BRANCH_CALLER}"
    grep -q "^      agent_checker_max_turns:" "${BRANCH_CALLER}"
    grep -q "^      agent_checker_model:" "${BRANCH_CALLER}"
    grep -q "^      agent_loop_max_attempts:" "${BRANCH_CALLER}"
    if grep -qE "^      (implementer_max_turns|implementer_model|verifier_max_turns|verifier_model|loop_max_attempts):" "${BRANCH_CALLER}"; then
        return 1
    fi
}

@test "callers use symmetric agent_maker_instructions and agent_checker_instructions inputs" {
    grep -q "^      agent_maker_instructions:" "${BRANCH_CALLER}"
    grep -q "^      agent_checker_instructions:" "${BRANCH_CALLER}"
    grep -q "^      agent_maker_instructions:" "${ENTITY_CALLER}"
    grep -q "^      agent_checker_instructions:" "${ENTITY_CALLER}"
    if grep -qE "^      (prompt_instructions|verifier_criteria|implementer_instructions|verifier_instructions):" "${BRANCH_CALLER}"; then
        return 1
    fi
}

@test "callers use symmetric agent_maker_skill_name and agent_checker_skill_name inputs" {
    grep -q "^      agent_maker_skill_name:" "${BRANCH_CALLER}"
    grep -q "^      agent_checker_skill_name:" "${BRANCH_CALLER}"
    grep -q "^      agent_maker_skill_name:" "${ENTITY_CALLER}"
    grep -q "^      agent_checker_skill_name:" "${ENTITY_CALLER}"
}

@test "ci-loop-agent call passes only declared inputs and every required input" {
    local caller key
    local -a declared required passed
    mapfile -t declared < <(workflow_inputs "${AGENT}")
    mapfile -t required < <(workflow_required_inputs "${AGENT}")
    [ "${#declared[@]}" -gt 30 ]
    [ "${#required[@]}" -ge 5 ]
    for caller in "${BRANCH_CALLER}" "${ENTITY_CALLER}"; do
        mapfile -t passed < <(agent_call_with_keys "${caller}")
        [ "${#passed[@]}" -gt 30 ]
        for key in "${passed[@]}"; do
            if ! printf '%s\n' "${declared[@]}" | grep -qx "${key}"; then
                echo "${caller}: ci-loop-agent has no input ${key}" >&2
                return 1
            fi
        done
        for key in "${required[@]}"; do
            if ! printf '%s\n' "${passed[@]}" | grep -qx "${key}"; then
                echo "${caller}: required ci-loop-agent input ${key} not passed" >&2
                return 1
            fi
        done
    done
}

@test "ci-loop-agent declares delivery, level and state_branch as required with no default" {
    local name block
    for name in delivery level state_branch; do
        block="$(input_block "${AGENT}" "${name}")"
        [[ -n ${block} ]]
        grep -qxF '        required: true' <<< "${block}"
        if grep -q '^        default:' <<< "${block}"; then
            echo "${name} has a default in ci-loop-agent" >&2
            return 1
        fi
    done
}

@test "ci-loop-agent declares no inputs that target_json or delivery replace" {
    local name
    local -a declared
    mapfile -t declared < <(workflow_inputs "${AGENT}")
    [ "${#declared[@]}" -gt 30 ]
    for name in finalize_enabled detect_result_json handoff_key current_sha base_branch auto_merge state_push_branch; do
        if printf '%s\n' "${declared[@]}" | grep -qx "${name}"; then
            echo "ci-loop-agent still declares ${name}" >&2
            return 1
        fi
    done
    for name in delivery pr_auto_merge state_branch target_json; do
        printf '%s\n' "${declared[@]}" | grep -qx "${name}"
    done
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

@test "ci-loop-agent passes agent_edit_denylist through unmodified for loop-execute to default" {
    # loop-execute's lib/paths.sh::apply_platform_denylist_default coerces an
    # empty AGENT_EDIT_DENYLIST to the platform default at loop start, so the
    # reusable caller must not hardcode or coalesce a domain-specific default.
    # shellcheck disable=SC2016
    grep -qxF '          agent_edit_denylist: ${{ inputs.agent_edit_denylist }}' "${AGENT}"
    if grep -q "inputs.agent_edit_denylist != '' && inputs.agent_edit_denylist ||" "${AGENT}"; then
        return 1
    fi
}

@test "ci-loop-agent records unchanged instead of no-changes" {
    if grep -q 'no-changes' "${AGENT}"; then
        return 1
    fi
    [ "$(grep -c "'unchanged'" "${AGENT}")" -eq 2 ]
}

@test "ci-loop-agent requires loop_name and does not guard run-log on emptiness" {
    grep -A3 '^      loop_name:' "${AGENT}" | grep -q 'required: true'
    if grep -q "inputs.loop_name != ''" "${AGENT}"; then
        return 1
    fi
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

@test "committed loop state JSON matches loop_name or allowlisted sidecars" {
    local f base name expected extra
    extra='state-ci-sweeper-run-ledger.json'
    for f in "${ROOT}"/.loop/state-*.json; do
        base="$(basename "${f}")"
        [[ ${base} == "${extra}" ]] && continue
        name="${base#state-}"
        name="${name%.json}"
        expected="${ROOT}/.github/workflows/on-loop-${name}.yaml"
        if [[ ! -f ${expected} ]]; then
            echo "orphan ${f} (no ${expected})" >&2
            return 1
        fi
        if ! awk '/^      loop_name:/{print $2; exit}' "${expected}" | grep -qx "${name}"; then
            echo "orphan ${f} (loop_name mismatch in ${expected})" >&2
            return 1
        fi
    done
}

@test "dogfood callers declare delivery and level per the migration table" {
    local wf name expected revise count=0
    # Literal GitHub Actions expression; do not expand.
    # shellcheck disable=SC2016
    revise='${{ inputs.delivery || '"'pr_push'"' }} L2'
    for wf in "${ROOT}"/.github/workflows/on-loop-*.yaml; do
        [[ -n "$(dogfood_reusable "${wf}")" ]] || continue
        name="$(basename "${wf}" .yaml)"
        name="${name#on-loop-}"
        case "${name}" in
            github-pr-revise) expected="${revise}" ;;
            github-issue-triage) expected='none L1' ;;
            github-pr-review) expected='none L2' ;;
            changelog | ci-sweeper | docs-updater | github-issue-autofix | refactor | tech-debt | test-gap)
                expected='pr_create L2'
                ;;
            *)
                echo "unmapped dogfood caller ${wf}" >&2
                return 1
                ;;
        esac
        if [[ "$(dogfood_value "${wf}" delivery) $(dogfood_value "${wf}" level)" != "${expected}" ]]; then
            echo "${name}: want '${expected}', got '$(dogfood_value "${wf}" delivery) $(dogfood_value "${wf}" level)'" >&2
            return 1
        fi
        count=$((count + 1))
    done
    [ "${count}" -eq 10 ]
}

@test "dogfood callers pass only declared inputs and every required input of the local reusable" {
    local wf reusable key count=0
    local -a declared required passed
    for wf in "${ROOT}"/.github/workflows/on-loop-*.yaml; do
        reusable="$(dogfood_reusable "${wf}")"
        [[ -n ${reusable} ]] || continue
        mapfile -t declared < <(workflow_inputs "${ROOT}/${reusable}")
        mapfile -t required < <(workflow_required_inputs "${ROOT}/${reusable}")
        mapfile -t passed < <(dogfood_with "${wf}" | sed 's/:.*//')
        [ "${#declared[@]}" -gt 30 ]
        [ "${#required[@]}" -ge 10 ]
        [ "${#passed[@]}" -gt 10 ]
        for key in "${passed[@]}"; do
            if ! printf '%s\n' "${declared[@]}" | grep -qx "${key}"; then
                echo "$(basename "${wf}"): ${reusable} has no input ${key}" >&2
                return 1
            fi
        done
        for key in "${required[@]}"; do
            if ! printf '%s\n' "${passed[@]}" | grep -qx "${key}"; then
                echo "$(basename "${wf}"): required ${reusable} input ${key} not passed" >&2
                return 1
            fi
        done
        count=$((count + 1))
    done
    [ "${count}" -eq 10 ]
}

@test "dogfood callers pass the level-dependent inputs only on L2 and above" {
    local wf name level key count=0
    for wf in "${ROOT}"/.github/workflows/on-loop-*.yaml; do
        [[ -n "$(dogfood_reusable "${wf}")" ]] || continue
        name="$(basename "${wf}")"
        level="$(dogfood_value "${wf}" level)"
        for key in agent_edit_allowlist agent_edit_denylist agent_edit_target agent_unchanged_verdict; do
            if [[ ${level} == L1 ]] && dogfood_with "${wf}" | grep -q "^${key}:"; then
                echo "${name}: L1 caller passes ${key}" >&2
                return 1
            fi
        done
        if [[ ${level} != L1 ]]; then
            for key in agent_edit_allowlist agent_edit_target agent_unchanged_verdict; do
                if [[ -z "$(dogfood_value "${wf}" "${key}")" || "$(dogfood_value "${wf}" "${key}")" == '""' ]]; then
                    echo "${name}: L2 caller lacks ${key}" >&2
                    return 1
                fi
            done
        fi
        count=$((count + 1))
    done
    [ "${count}" -eq 10 ]
}

@test "dogfood callers repeat no reusable default and no removed input" {
    local wf name line
    for wf in "${ROOT}"/.github/workflows/on-loop-*.yaml; do
        [[ -n "$(dogfood_reusable "${wf}")" ]] || continue
        name="$(basename "${wf}")"
        while IFS= read -r line; do
            case "${line}" in
                'agent_checker_skill_name: loop-verifier' | 'agent_edit_denylist: ""' | 'detect_env_json: "{}"' | \
                    'detect_max_targets: 3' | 'detect_pr_bot_allowlist: ""' | 'detect_pr_denylist: fork,draft,label:no-loop' | \
                    'detect_pr_enabled: false' | 'environment: default' | 'pr_body: ""')
                    echo "${name}: repeats a default: ${line}" >&2
                    return 1
                    ;;
                may_edit:* | git_landing_*:* | dispatch_hook_token:*)
                    echo "${name}: removed input: ${line}" >&2
                    return 1
                    ;;
            esac
        done < <(dogfood_with "${wf}")
    done
}

@test "finalize-l1 has issues write and no pull-requests write" {
    local block
    block="$(job_block "${AGENT}" finalize-l1)"
    grep -qxF '      contents: write' <<< "${block}"
    grep -qxF '      issues: write' <<< "${block}"
    if grep -n 'pull-requests: write' <<< "${block}"; then
        return 1
    fi
}

@test "finalize-l1 persists run-log after agent-l1" {
    grep -A72 '^  finalize-l1:' "${AGENT}" | grep -q 'loop-run-log'
    grep -A20 '^  finalize-l1:' "${AGENT}" | grep -q "inputs.level == 'L1'"
    grep -A15 '^  finalize-l1:' "${AGENT}" | grep -q 'needs: agent-l1'
}

@test "finalize-l1 run log uses the finalize outcome" {
    local step
    step="$(job_block "${AGENT}" finalize-l1 | step_block 'Append Run Log')"
    grep -qxF '        if: always()' <<< "${step}"
    # Literal GitHub Actions expression; do not expand.
    # shellcheck disable=SC2016
    grep -qxF "          outcome: \${{ steps.finalize.outcome == 'failure' && 'error' || steps.finalize.outputs.outcome || (needs.agent-l1.result != 'success' && needs.agent-l1.result != 'skipped' && 'error') || 'unchanged' }}" <<< "${step}"
}

@test "finalize-l1 runs loop-finalize with an empty current_sha and branch" {
    local step
    step="$(job_block "${AGENT}" finalize-l1 | step_block 'Finalize')"
    grep -qF 'uses: y-miyazaki/config/.github/actions/loop-finalize@' <<< "${step}"
    grep -qxF '        continue-on-error: true' <<< "${step}"
    grep -qxF '        id: finalize' <<< "${step}"
    grep -qxF '          current_sha: ""' <<< "${step}"
    grep -qxF '          branch: ""' <<< "${step}"
    # Literal GitHub Actions expressions; do not expand.
    # shellcheck disable=SC2016
    grep -qxF "          message_json: \${{ needs.agent-l1.outputs.message_json || '' }}" <<< "${step}"
    # shellcheck disable=SC2016
    grep -qxF '          finalize_label_allowlist: ${{ inputs.finalize_label_allowlist }}' <<< "${step}"
}

@test "finalize-l1 warns when a successful agent left no message" {
    local step
    step="$(job_block "${AGENT}" finalize-l1 | step_block 'Warn Missing Message')"
    grep -qxF "        if: needs.agent-l1.result == 'success' && needs.agent-l1.outputs.message_json == '' && inputs.delivery == 'issue_comment'" <<< "${step}"
    grep -qF '::warning' <<< "${step}"
}

@test "finalize-l2 has issues write" {
    local block step
    block="$(job_block "${AGENT}" finalize-l2)"
    grep -qxF '      issues: write' <<< "${block}"
    step="$(step_block 'Finalize' <<< "${block}")"
    # Literal GitHub Actions expression; do not expand.
    # shellcheck disable=SC2016
    grep -qxF '          finalize_label_allowlist: ${{ inputs.finalize_label_allowlist }}' <<< "${step}"
}

@test "finalize-l2 job if does not require finalize_enabled" {
    local block
    block="$(job_if_block "${AGENT}" 'finalize-l2')"
    [[ ${block} == *"inputs.level == 'L2'"* ]]
    if [[ ${block} == *finalize_enabled* ]]; then
        return 1
    fi
}

@test "finalize-l2 parse target reads key, current sha and pr number from target_json" {
    local script out
    script="$(job_block "${AGENT}" finalize-l2 | step_block 'Parse Target' | run_script)"
    [[ -n ${script} ]]
    out="${BATS_TEST_TMPDIR}/github_output"
    : > "${out}"
    run env GITHUB_OUTPUT="${out}" \
        TARGET_JSON='{"key":"pull_request:7","mode":"pull_request","base":{"branch":"main"},"from":{"branch":"feat","ref":"def456"},"to":{"branch":"feat","pr_number":7}}' \
        bash -c "${script}"
    [ "$status" -eq 0 ]
    [ "$(cat "${out}")" = "$(printf '%s\n' from_ref=def456 key=pull_request:7 pr_number=7)" ]
}

@test "finalize-l2 runs loop-finalize with no step if" {
    local -a steps
    mapfile -d '' -t steps < <(job_block "${AGENT}" finalize-l2 > "${BATS_TEST_TMPDIR}/job" && steps_using "${BATS_TEST_TMPDIR}/job" loop-finalize)
    [ "${#steps[@]}" -eq 1 ]
    grep -qxF '        id: finalize' <<< "${steps[0]}"
    if grep -q '^        if:' <<< "${steps[0]}"; then
        return 1
    fi
}

@test "github-pr-revise caller watches a scoped PR head" {
    local wf="${ROOT}/.github/workflows/on-loop-github-pr-revise.yaml"
    [ "$(dogfood_value "${wf}" detect_pr_enabled)" = true ]
    # detect_pr_number is a number input: the expression must go through fromJSON, or a
    # workflow_dispatch run fails at startup with no jobs ("workflow file issue").
    [[ "$(dogfood_value "${wf}" detect_pr_number)" == '${{ fromJSON('*'inputs.pr_number || 0) }}' ]]
    [ "$(dogfood_value "${wf}" detect_pr_denylist)" = 'fork,label:no-loop' ]
    # pr_push rejects detect_branch_match (spec 7-3).
    if dogfood_with "${wf}" | grep -q '^detect_branch_match:'; then
        return 1
    fi
}

@test "github-pr-revise manual dispatch offers delivery pr_push or pr_create" {
    local wf="${ROOT}/.github/workflows/on-loop-github-pr-revise.yaml" block
    block="$(awk '
        /^      delivery:/ {f=1; print; next}
        f && /^      [a-z_]+:/ {exit}
        f
    ' "${wf}")"
    grep -qxF '        type: choice' <<< "${block}"
    grep -qxF '        default: pr_push' <<< "${block}"
    [ "$(grep -c '^          - ' <<< "${block}")" -eq 2 ]
    grep -qxF '          - pr_create' <<< "${block}"
    grep -qxF '          - pr_push' <<< "${block}"
    if grep -q 'git_landing' "${wf}"; then
        return 1
    fi
}

@test "loop action env blocks are alphabetically ordered" {
    local checker
    checker="${ROOT}/scripts/lib/yaml_map_order.py"
    python3 "${checker}" check \
        "${ROOT}/.github/actions/loop-detect/action.yml" \
        "${ROOT}/.github/actions/loop-entity-detect/action.yml" \
        "${ROOT}/.github/actions/loop-execute/action.yml"
}

@test "loop action steps pass only declared inputs and every required input" {
    local wf action keys key checked=""
    local -a declared required
    for wf in "${BRANCH_CALLER}" "${ENTITY_CALLER}" "${AGENT}"; do
        while IFS=$'\t' read -r action keys; do
            [[ -f "${ACTIONS_DIR}/${action}/action.yml" ]]
            mapfile -t declared < <(action_inputs "${action}")
            mapfile -t required < <(action_required_inputs "${action}")
            [ "${#declared[@]}" -gt 0 ]
            for key in ${keys}; do
                if ! printf '%s\n' "${declared[@]}" | grep -qx "${key}"; then
                    echo "$(basename "${wf}"): ${action} has no input ${key}" >&2
                    return 1
                fi
            done
            for key in "${required[@]}"; do
                if [[ " ${keys} " != *" ${key} "* ]]; then
                    echo "$(basename "${wf}"): required ${action} input ${key} not passed" >&2
                    return 1
                fi
            done
            checked="${checked} ${action}"
        done < <(pinned_action_steps "${wf}")
    done
    for action in loop-agent-once loop-detect loop-entity-detect loop-execute loop-finalize \
        loop-notify-pr loop-resolve-push-token loop-run-log loop-worktree-setup; do
        [[ " ${checked} " == *" ${action} "* ]]
    done
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

@test "loop-run-log steps receive state_branch from inputs with no fallback expression" {
    local wf step count=0
    local -a steps
    for wf in "${BRANCH_CALLER}" "${ENTITY_CALLER}" "${AGENT}"; do
        mapfile -d '' -t steps < <(steps_using "${wf}" loop-run-log)
        for step in "${steps[@]}"; do
            # Literal GitHub Actions expression; do not expand.
            # shellcheck disable=SC2016
            grep -qxF '          state_branch: ${{ inputs.state_branch }}' <<< "${step}"
            if grep -q 'base_branch' <<< "${step}"; then
                return 1
            fi
            count=$((count + 1))
        done
    done
    [ "${count}" -eq 4 ]
}

@test "on-loop callers have committed .loop/state-<loop_name>.json" {
    local wf name path
    for wf in "${ROOT}"/.github/workflows/on-loop-*.yaml; do
        name="$(awk '/^      loop_name:/{print $2; exit}' "${wf}")"
        [[ -n ${name} ]] || continue
        path="${ROOT}/.loop/state-${name}.json"
        if [[ ! -f ${path} ]]; then
            echo "missing ${path} for ${wf}" >&2
            return 1
        fi
    done
}

@test "on-loop-state-promote passes declared loop-state-promote inputs and state_branch main" {
    local wf="${ROOT}/.github/workflows/on-loop-state-promote.yaml" key
    local -a declared required passed
    mapfile -t declared < <(action_inputs loop-state-promote)
    mapfile -t required < <(action_required_inputs loop-state-promote)
    mapfile -t passed < <(awk '
        /uses: \.\/\.github\/actions\/loop-state-promote$/ {f=1; next}
        f && /^        with:/ {inwith=1; next}
        inwith && /^          [a-zA-Z0-9_]+:/ {k=$1; sub(/:$/, "", k); print k; next}
        inwith {exit}
    ' "${wf}")
    [ "${#passed[@]}" -ge 4 ]
    for key in "${passed[@]}"; do
        printf '%s\n' "${declared[@]}" | grep -qx "${key}"
    done
    for key in "${required[@]}"; do
        printf '%s\n' "${passed[@]}" | grep -qx "${key}"
    done
    grep -qxF '          state_branch: main' "${wf}"
}

@test "reusable workflows use no pre-rename input or env names" {
    # base_branch, handoff_key and current_sha stay valid as with: keys of
    # loop-execute / loop-finalize; the ci-loop-agent input check covers them.
    local wf name
    local -a old_names=(
        ack_trigger_comment additional_commit_paths agent_allowed_tools allowlist
        auto_merge base_ref branch_match branch_match_mode branch_prefix branch_state
        cli_version commit_message denylist detect_domain_env_json dispatch_hook_script
        dispatch_hook_token domain_persistence_script effort engine finalize_enabled
        git_landing_integration git_landing_pull_request infer_files_pattern labels
        loop_branch_match loop_integration_branches loop_max_targets_per_schedule
        loop_pr_enabled loop_pr_exclude loop_pr_include_bots loop_priority
        loop_scoped_pr_number max_attempts max_targets_per_schedule max_turns may_edit
        model no_changes_verdict outcome_override pr_enabled pr_exclude pr_include_bots
        priority scoped_pr_number state_push_branch write_target
        DETECT_DOMAIN_ENV_JSON ENGINE finalize_hook_script FINALIZE_HOOK_SCRIPT
    )
    for wf in "${BRANCH_CALLER}" "${ENTITY_CALLER}" "${AGENT}"; do
        for name in "${old_names[@]}"; do
            if grep -qE "^[[:space:]]+${name}:" "${wf}"; then
                echo "$(basename "${wf}"): old name ${name}" >&2
                return 1
            fi
            if grep -qF "inputs.${name} " "${wf}" || grep -qF "outputs.${name} " "${wf}"; then
                echo "$(basename "${wf}"): old reference ${name}" >&2
                return 1
            fi
        done
    done
}

@test "target_json is described as required at every level" {
    input_block "${AGENT}" target_json | grep -qF 'required at every level'
}

@test "no tracked file outside docs/superpowers names finalize_hook_script" {
    run git -C "${ROOT}" grep -l -e finalize_hook_script -e FINALIZE_HOOK_SCRIPT -- . ':!docs/superpowers' ':!.agents' ':!.claude/skills' ':!apm_modules' ':!apm.lock.yaml' ':!.apm/packages/github/.apm/skills/github-pr-review/scripts/post_review.sh' ':!test/bats/github-actions/loop-caller-parity.bats' ':!scripts/self/ci/loop_input_topology.py'
    [ "${status}" -eq 1 ]
    [ -z "${output}" ]
}

@test "no loop-finalize step or lib/loop script edits a posted comment or review" {
    run grep -nE -e '-X PATCH' -e '--method PATCH' -e 'edit-last' -e 'pulls/[^ ]*/reviews/[0-9]' "${ROOT}/.github/actions/loop-finalize/action.yml" "${ROOT}"/.github/actions/lib/loop/*.sh
    [ "${status}" -eq 1 ]
    [ -z "${output}" ]
}
