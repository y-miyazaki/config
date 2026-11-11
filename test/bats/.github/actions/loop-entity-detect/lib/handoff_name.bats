#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# Tests for .github/actions/loop-entity-detect/lib/handoff_name.sh
#
# Use cases:
# - build_handoff_artifact_name returns loop-handoff-run_id when the suffix is empty
# - build_handoff_artifact_name appends the suffix to the run id
# - build_handoff_artifact_name accepts letters, digits, dot, underscore, and hyphen
# - build_handoff_artifact_name fails with ::error:: on characters outside the allowed set
# - build_handoff_artifact_name fails without a run id
# - main writes artifact_name to GITHUB_OUTPUT

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    HANDOFF_NAME_SH="$(bats_workspace_root)/.github/actions/loop-entity-detect/lib/handoff_name.sh"
    ACTION_YML="$(bats_workspace_root)/.github/actions/loop-entity-detect/action.yml"
    ENTITY_CALLER="$(bats_workspace_root)/.github/workflows/ci-loop-caller-entity.yaml"
    # shellcheck disable=SC1090,SC1091
    source "${HANDOFF_NAME_SH}"
}

@test "handoff artifact name equals loop-handoff-run_id when suffix empty" {
    run build_handoff_artifact_name 123 ""
    [ "$status" -eq 0 ]
    [ "$output" = "loop-handoff-123" ]
}

@test "handoff artifact name appends suffix" {
    run build_handoff_artifact_name 123 "-issue-42"
    [ "$status" -eq 0 ]
    [ "$output" = "loop-handoff-123-issue-42" ]
    run build_handoff_artifact_name 123 "A.b_c-9"
    [ "$status" -eq 0 ]
    [ "$output" = "loop-handoff-123A.b_c-9" ]
}

@test "handoff artifact name rejects invalid suffix characters" {
    local bad
    for bad in "a b" "a/b" 'a"b' "a:b" "a*b" $'a\nb'; do
        run --separate-stderr build_handoff_artifact_name 123 "${bad}"
        [ "$status" -ne 0 ]
        [[ ${stderr} == *"::error::"* ]]
    done
}

@test "handoff artifact name fails without run id" {
    run --separate-stderr build_handoff_artifact_name "" ""
    [ "$status" -ne 0 ]
    [[ ${stderr} == *"::error::"* ]]
}

@test "handoff name main writes artifact_name to GITHUB_OUTPUT" {
    local out="${BATS_TEST_TMPDIR}/out"
    : > "${out}"
    run env GITHUB_OUTPUT="${out}" GITHUB_RUN_ID=77 HANDOFF_ARTIFACT_SUFFIX="-x" bash "${HANDOFF_NAME_SH}"
    [ "$status" -eq 0 ]
    grep -qxF 'artifact_name=loop-handoff-77-x' "${out}"
}

@test "handoff_artifact_suffix input defaults to empty in action and entity caller" {
    awk '/^  handoff_artifact_suffix:$/{f=1;next} f&&/^  [a-z]/{exit} f' "${ACTION_YML}" | grep -qF 'default: ""'
    awk '/^      handoff_artifact_suffix:$/{f=1;next} f&&/^      [a-z]/{exit} f' "${ENTITY_CALLER}" | grep -qF 'default: ""'
    grep -qxF '          handoff_artifact_suffix: ${{ inputs.handoff_artifact_suffix }}' "${ENTITY_CALLER}"
}

@test "upload step uses the handoff step output as the single source of the name" {
    grep -qF 'name: ${{ steps.handoff.outputs.artifact_name }}' "${ACTION_YML}"
    ! grep -qF 'name: loop-handoff-${{ github.run_id }}' "${ACTION_YML}"
}
