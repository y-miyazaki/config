#!/usr/bin/env bats

# Tests for scripts/self/ci/loop_input_topology.py
#
# Use cases:
# - The repository passes the gate and prints one table row per declared caller input of the two reusables
# - Every level-dependent input, delivery and level reach detect from both reusables
# - A caller input with no decision-table entry fails the gate
# - A level-dependent input, delivery or level missing from either detect step fails the gate
# - A decision-table entry that names no caller input fails the gate
# - A missing repository root argument is a usage error

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    ROOT="$(bats_workspace_root)"
    SCRIPT="${ROOT}/scripts/self/ci/loop_input_topology.py"
    FIXTURE="${BATS_TEST_TMPDIR}/repo"
    mkdir -p "${FIXTURE}"
    cp -R "${ROOT}/.github" "${FIXTURE}/.github"
    BRANCH="${FIXTURE}/.github/workflows/ci-loop-caller.yaml"
    ENTITY="${FIXTURE}/.github/workflows/ci-loop-caller-entity.yaml"
}

teardown() {
    rm -rf "${FIXTURE}"
}

# reusable_inputs FILE: print declared workflow_call input names
reusable_inputs() {
    awk '
        /^    inputs:/ {f=1; next}
        f && /^    [a-z]/ {exit}
        f && /^      [a-zA-Z0-9_]+:/ {k=$1; sub(/:$/, "", k); print k}
    ' "$1"
}

# drop_detect_with FILE ACTION KEY: delete KEY from the with: block of the step that uses ACTION
drop_detect_with() {
    awk -v needle="/.github/actions/$2@" -v key="$3" '
        index($0, needle) > 0 {f=1}
        f && /^      - name:/ {f=0}
        f && $0 ~ "^          " key ":" {next}
        {print}
    ' "$1" > "$1.new"
    mv "$1.new" "$1"
}

@test "loop_input_topology fails when a caller input has no decision-table entry" {
    sed -i 's/^      agent_branch_prefix:$/      zz_unannotated:\n        default: ""\n        description: "fixture"\n        required: false\n        type: string\n      agent_branch_prefix:/' "${BRANCH}"
    grep -q '^      zz_unannotated:' "${BRANCH}"
    run python3 -I "${SCRIPT}" "${FIXTURE}"
    [ "$status" -ne 0 ]
    [[ ${output} == *"no decision-table entry: zz_unannotated"* ]]
}

@test "loop_input_topology fails when a decision-table entry names no caller input" {
    awk '
        /^      trigger_comment_ack:$/ {skip=1; next}
        skip && /^      [a-z_]+:$/ {skip=0}
        skip && /^    [a-z]/ {skip=0}
        !skip {print}
    ' "${BRANCH}" > "${BRANCH}.new"
    mv "${BRANCH}.new" "${BRANCH}"
    if grep -q '^      trigger_comment_ack:' "${BRANCH}"; then
        return 1
    fi
    run python3 -I "${SCRIPT}" "${FIXTURE}"
    [ "$status" -ne 0 ]
    [[ ${output} == *"decision-table entry names no caller input: trigger_comment_ack"* ]]
}

@test "loop_input_topology fails when a level-dependent input does not reach branch detect" {
    local key
    for key in agent_edit_allowlist agent_edit_denylist agent_edit_target agent_unchanged_verdict delivery finalize_label_allowlist finalize_script level; do
        rm -rf "${FIXTURE}/.github"
        cp -R "${ROOT}/.github" "${FIXTURE}/.github"
        drop_detect_with "${BRANCH}" loop-detect "${key}"
        if grep -q "^          ${key}: \${{ inputs.${key} }}" "${BRANCH}"; then
            return 1
        fi
        run python3 -I "${SCRIPT}" "${FIXTURE}"
        [ "$status" -ne 0 ]
        [[ ${output} == *"${key} does not reach detect from ci-loop-caller.yaml"* ]]
    done
}

@test "loop_input_topology fails when a level-dependent input does not reach entity detect" {
    local key
    for key in agent_edit_allowlist agent_edit_denylist agent_edit_target agent_unchanged_verdict delivery finalize_label_allowlist finalize_script level; do
        rm -rf "${FIXTURE}/.github"
        cp -R "${ROOT}/.github" "${FIXTURE}/.github"
        drop_detect_with "${ENTITY}" loop-entity-detect "${key}"
        if grep -q "^          ${key}: \${{ inputs.${key} }}" "${ENTITY}"; then
            return 1
        fi
        run python3 -I "${SCRIPT}" "${FIXTURE}"
        [ "$status" -ne 0 ]
        [[ ${output} == *"${key} does not reach detect from ci-loop-caller-entity.yaml"* ]]
    done
}

@test "loop_input_topology passes on the repository with one row per caller input" {
    local -a inputs
    local name rows
    mapfile -t inputs < <({ reusable_inputs "${ROOT}/.github/workflows/ci-loop-caller.yaml" \
        && reusable_inputs "${ROOT}/.github/workflows/ci-loop-caller-entity.yaml"; } | LC_ALL=C sort -u)
    [ "${#inputs[@]}" -ge 45 ]
    run python3 -I "${SCRIPT}" "${ROOT}"
    [ "$status" -eq 0 ]
    rows="$(grep -c '^| `' <<< "${output}")"
    [ "${rows}" -eq "${#inputs[@]}" ]
    for name in "${inputs[@]}"; do
        grep -q "^| \`${name}\` |" <<< "${output}"
    done
}

@test "loop_input_topology reports every level-dependent input reaching detect from both reusables" {
    local key row
    run python3 -I "${SCRIPT}" "${ROOT}"
    [ "$status" -eq 0 ]
    for key in agent_edit_allowlist agent_edit_denylist agent_edit_target agent_unchanged_verdict delivery finalize_label_allowlist finalize_script level; do
        row="$(grep "^| \`${key}\` |" <<< "${output}")"
        [[ ${row} == *"| はい | はい |"* ]]
    done
}

@test "loop_input_topology rejects a missing repository root" {
    run python3 -I "${SCRIPT}"
    [ "$status" -eq 2 ]
    [[ ${output} == *"usage:"* ]]
}
