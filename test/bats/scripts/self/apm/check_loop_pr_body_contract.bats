#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for scripts/self/apm/check_loop_pr_body_contract.sh
#
# Use cases:
# - check_loop_pr_body_contract accepts canonical loop skill package files
# - check_loop_pr_body_contract rejects deprecated Overview wording in templates
# - check_loop_pr_body_contract requires common-output-format.md for all loop skills
# - check_loop_pr_body_contract requires common-output-format-automation.md for split skills
# - check_loop_pr_body_contract does not require automation format for non-split skills
# - check_loop_pr_body_contract rejects deprecated patterns in automation format files
# - check_loop_pr_body_contract rejects example org/repo markdown links in templates

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

@test "check_loop_pr_body_contract requires common-output-format.md for all loop skills" {
    local skill_root="${TEST_TMP}/skills/changelog"
    mkdir -p "${skill_root}/assets" "${skill_root}/references"
    cp -R "${REPO_ROOT}/.apm/packages/common/.apm/skills/changelog/." "${skill_root}/"
    rm -f "${skill_root}/references/common-output-format.md"

    run env SKILLS_ROOT="${TEST_TMP}/skills" bash "${REPO_ROOT}/scripts/self/apm/check_loop_pr_body_contract.sh"
    [ "$status" -eq 1 ]
    [[ $output == *"Missing"* ]]
    [[ $output == *"common-output-format.md"* ]]
}

@test "check_loop_pr_body_contract requires common-output-format-automation.md for split skills" {
    local skill_root="${TEST_TMP}/skills/docs-updater"
    mkdir -p "${skill_root}/assets" "${skill_root}/references"
    cp -R "${REPO_ROOT}/.apm/packages/common/.apm/skills/docs-updater/." "${skill_root}/"
    rm -f "${skill_root}/references/common-output-format-automation.md"

    run env SKILLS_ROOT="${TEST_TMP}/skills" bash "${REPO_ROOT}/scripts/self/apm/check_loop_pr_body_contract.sh"
    [ "$status" -eq 1 ]
    [[ $output == *"Missing"* ]]
    [[ $output == *"common-output-format-automation.md"* ]]
}

@test "check_loop_pr_body_contract does not require automation format for non-split skills" {
    local skills_root skill
    skills_root="${TEST_TMP}/skills"
    for skill in changelog ci-sweeper docs-updater issue-autofix pr-revise refactor tech-debt; do
        mkdir -p "${skills_root}/${skill}"
        cp -R "${REPO_ROOT}/.apm/packages/common/.apm/skills/${skill}/." "${skills_root}/${skill}/"
    done
    rm -f "${skills_root}/changelog/references/common-output-format-automation.md"

    run env SKILLS_ROOT="${skills_root}" bash "${REPO_ROOT}/scripts/self/apm/check_loop_pr_body_contract.sh"
    [ "$status" -eq 0 ]
    [[ $output == *"loop PR body contract: OK"* ]]
}

@test "check_loop_pr_body_contract rejects deprecated patterns in automation format files" {
    local skill_root="${TEST_TMP}/skills/docs-updater"
    mkdir -p "${skill_root}/assets" "${skill_root}/references"
    cp -R "${REPO_ROOT}/.apm/packages/common/.apm/skills/docs-updater/." "${skill_root}/"
    echo "one or two sentences" >> "${skill_root}/references/common-output-format-automation.md"

    run env SKILLS_ROOT="${TEST_TMP}/skills" bash "${REPO_ROOT}/scripts/self/apm/check_loop_pr_body_contract.sh"
    [ "$status" -eq 1 ]
    [[ $output == *"Deprecated pattern"* ]]
    [[ $output == *"common-output-format-automation.md"* ]]
}

@test "check_loop_pr_body_contract rejects example org/repo markdown links in templates" {
    local skill_root="${TEST_TMP}/skills/docs-updater"
    mkdir -p "${skill_root}/assets" "${skill_root}/references"
    cp -R "${REPO_ROOT}/.apm/packages/common/.apm/skills/docs-updater/." "${skill_root}/"
    echo '[bad](https://github.com/org/repo/blob/main/docs/x.md)' >> "${skill_root}/assets/pr-body-template.md"

    run env SKILLS_ROOT="${TEST_TMP}/skills" bash "${REPO_ROOT}/scripts/self/apm/check_loop_pr_body_contract.sh"
    [ "$status" -eq 1 ]
    [[ $output == *"Example org/repo markdown link"* ]]
}

@test "check_loop_pr_body_contract requires Survey and Apply sections in common-output-format.md" {
    local skill_root="${TEST_TMP}/skills/issue-autofix"
    mkdir -p "${skill_root}/assets" "${skill_root}/references"
    cp -R "${REPO_ROOT}/.apm/packages/common/.apm/skills/issue-autofix/." "${skill_root}/"
    sed -i '/^## Survey result/d' "${skill_root}/references/common-output-format.md"

    run env SKILLS_ROOT="${TEST_TMP}/skills" bash "${REPO_ROOT}/scripts/self/apm/check_loop_pr_body_contract.sh"
    [ "$status" -eq 1 ]
    [[ $output == *"missing ## Survey result section"* ]]
}
