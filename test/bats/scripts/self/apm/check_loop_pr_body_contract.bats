#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for scripts/self/apm/check_loop_pr_body_contract.sh
#
# Use cases:
# - check_loop_pr_body_contract accepts canonical loop skill package files
# - check_loop_pr_body_contract rejects deprecated Overview wording in templates

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel "scripts/self/apm/check_loop_pr_body_contract.sh"
    REPO_ROOT="$(bats_workspace_root)"
    TEST_TMP="${BATS_TEST_TMPDIR}/check_loop_pr_body_contract"
    mkdir -p "${TEST_TMP}"
}

@test "check_loop_pr_body_contract accepts canonical loop skill package files" {
    run bash "${REPO_ROOT}/scripts/self/apm/check_loop_pr_body_contract.sh"
    [ "$status" -eq 0 ]
    [[ $output == *"loop PR body contract: OK"* ]]
}

@test "check_loop_pr_body_contract rejects deprecated Overview wording in templates" {
    local skill_root="${TEST_TMP}/skills/changelog"
    mkdir -p "${skill_root}/assets" "${skill_root}/references"
    cp -R "${REPO_ROOT}/.apm/packages/common/.apm/skills/changelog/." "${skill_root}/"
    echo "one or two sentences" >> "${skill_root}/assets/pr-body-template.md"

    run env SKILLS_ROOT="${TEST_TMP}/skills" bash "${REPO_ROOT}/scripts/self/apm/check_loop_pr_body_contract.sh"
    [ "$status" -eq 1 ]
    [[ $output == *"Deprecated pattern"* ]]
}
