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
# - check_loop_pr_body_contract validates test-gap required files
# - check_loop_pr_body_contract requires templates to point at category-pr-body-links.md
# - check_loop_pr_body_contract rejects backtick placeholders for linkable items in templates
# - check_loop_pr_body_contract requires SKILL.md to list the link rules and both PR body templates
# - check_loop_pr_body_contract requires templates to state the keep-table-columns rule
# - check_loop_pr_body_contract requires comment-posting skills to ship and list their link rules

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
    cp -R "$(apm_skill_dir changelog)/." "${skill_root}/"
    echo "one or two sentences" >> "${skill_root}/assets/pr-body-template.md"

    run env SKILLS_ROOT="${TEST_TMP}/skills" bash "${REPO_ROOT}/scripts/self/apm/check_loop_pr_body_contract.sh"
    [ "$status" -eq 1 ]
    [[ $output == *"Deprecated pattern"* ]]
}

@test "check_loop_pr_body_contract requires common-output-format.md for all loop skills" {
    local skill_root="${TEST_TMP}/skills/changelog"
    mkdir -p "${skill_root}/assets" "${skill_root}/references"
    cp -R "$(apm_skill_dir changelog)/." "${skill_root}/"
    rm -f "${skill_root}/references/common-output-format.md"

    run env SKILLS_ROOT="${TEST_TMP}/skills" bash "${REPO_ROOT}/scripts/self/apm/check_loop_pr_body_contract.sh"
    [ "$status" -eq 1 ]
    [[ $output == *"Missing"* ]]
    [[ $output == *"common-output-format.md"* ]]
}

@test "check_loop_pr_body_contract requires common-output-format-automation.md for split skills" {
    local skill_root="${TEST_TMP}/skills/docs-updater"
    mkdir -p "${skill_root}/assets" "${skill_root}/references"
    cp -R "$(apm_skill_dir docs-updater)/." "${skill_root}/"
    rm -f "${skill_root}/references/common-output-format-automation.md"

    run env SKILLS_ROOT="${TEST_TMP}/skills" bash "${REPO_ROOT}/scripts/self/apm/check_loop_pr_body_contract.sh"
    [ "$status" -eq 1 ]
    [[ $output == *"Missing"* ]]
    [[ $output == *"common-output-format-automation.md"* ]]
}

@test "check_loop_pr_body_contract does not require automation format for non-split skills" {
    local skills_root skill
    skills_root="${TEST_TMP}/skills"
    for skill in changelog ci-sweeper docs-updater github-issue-autofix github-issue-triage github-pr-review github-pr-revise refactor tech-debt test-gap; do
        mkdir -p "${skills_root}/${skill}"
        cp -R "$(apm_skill_dir "${skill}")/." "${skills_root}/${skill}/"
    done
    rm -f "${skills_root}/changelog/references/common-output-format-automation.md"

    run env SKILLS_ROOT="${skills_root}" bash "${REPO_ROOT}/scripts/self/apm/check_loop_pr_body_contract.sh"
    [ "$status" -eq 0 ]
    [[ $output == *"loop PR body contract: OK"* ]]
}

@test "check_loop_pr_body_contract rejects deprecated patterns in automation format files" {
    local skill_root="${TEST_TMP}/skills/docs-updater"
    mkdir -p "${skill_root}/assets" "${skill_root}/references"
    cp -R "$(apm_skill_dir docs-updater)/." "${skill_root}/"
    echo "one or two sentences" >> "${skill_root}/references/common-output-format-automation.md"

    run env SKILLS_ROOT="${TEST_TMP}/skills" bash "${REPO_ROOT}/scripts/self/apm/check_loop_pr_body_contract.sh"
    [ "$status" -eq 1 ]
    [[ $output == *"Deprecated pattern"* ]]
    [[ $output == *"common-output-format-automation.md"* ]]
}

@test "check_loop_pr_body_contract rejects example org/repo markdown links in templates" {
    local skill_root="${TEST_TMP}/skills/docs-updater"
    mkdir -p "${skill_root}/assets" "${skill_root}/references"
    cp -R "$(apm_skill_dir docs-updater)/." "${skill_root}/"
    echo '[bad](https://github.com/org/repo/blob/main/docs/x.md)' >> "${skill_root}/assets/pr-body-template.md"

    run env SKILLS_ROOT="${TEST_TMP}/skills" bash "${REPO_ROOT}/scripts/self/apm/check_loop_pr_body_contract.sh"
    [ "$status" -eq 1 ]
    [[ $output == *"Example org/repo markdown link"* ]]
}

@test "check_loop_pr_body_contract requires Survey and Apply sections in common-output-format.md" {
    local skill_root="${TEST_TMP}/skills/github-issue-autofix"
    mkdir -p "${skill_root}/assets" "${skill_root}/references"
    cp -R "$(apm_skill_dir github-issue-autofix)/." "${skill_root}/"
    sed -i '/^## Survey result/d' "${skill_root}/references/common-output-format.md"

    run env SKILLS_ROOT="${TEST_TMP}/skills" bash "${REPO_ROOT}/scripts/self/apm/check_loop_pr_body_contract.sh"
    [ "$status" -eq 1 ]
    [[ $output == *"missing ## Survey result section"* ]]
}

@test "check_loop_pr_body_contract validates test-gap required files" {
    local skills_root="${TEST_TMP}/skills"
    mkdir -p "${skills_root}/test-gap/assets" "${skills_root}/test-gap/references"

    run env SKILLS_ROOT="${skills_root}" bash "${REPO_ROOT}/scripts/self/apm/check_loop_pr_body_contract.sh"
    [ "$status" -eq 1 ]
    [[ $output == *"Missing references/common-output-format.md for skill test-gap"* ]]
}

@test "check_loop_pr_body_contract requires templates to point at category-pr-body-links.md" {
    local skill_root="${TEST_TMP}/skills/test-gap"
    mkdir -p "${skill_root}/assets" "${skill_root}/references"
    cp -R "$(apm_skill_dir test-gap)/." "${skill_root}/"
    sed -i '/category-pr-body-links.md/d' "${skill_root}/assets/pr-body-template.md"

    run env SKILLS_ROOT="${TEST_TMP}/skills" bash "${REPO_ROOT}/scripts/self/apm/check_loop_pr_body_contract.sh"
    [ "$status" -eq 1 ]
    [[ $output == *"test-gap/assets/pr-body-template.md must point at category-pr-body-links.md"* ]]
}

@test "check_loop_pr_body_contract rejects backtick placeholders for linkable items in templates" {
    local skill_root="${TEST_TMP}/skills/docs-updater"
    mkdir -p "${skill_root}/assets" "${skill_root}/references"
    cp -R "$(apm_skill_dir docs-updater)/." "${skill_root}/"
    # shellcheck disable=SC2016 # literal backticks are the template row under test
    printf '%s\n' '| `docs/foo.md` | <from findings> | <minimal change summary> |' >> "${skill_root}/assets/pr-body-template.md"

    run env SKILLS_ROOT="${TEST_TMP}/skills" bash "${REPO_ROOT}/scripts/self/apm/check_loop_pr_body_contract.sh"
    [ "$status" -eq 1 ]
    [[ $output == *"docs-updater/assets/pr-body-template.md has a backtick path in a Summary table row"* ]]
}

@test "check_loop_pr_body_contract requires SKILL.md to list the link rules and both PR body templates" {
    local skill_root="${TEST_TMP}/skills/refactor"
    mkdir -p "${skill_root}/assets" "${skill_root}/references"
    cp -R "$(apm_skill_dir refactor)/." "${skill_root}/"
    sed -i '/category-pr-body-links.md/d; /assets\/pr-body-template-survey.md/d' "${skill_root}/SKILL.md"

    run env SKILLS_ROOT="${TEST_TMP}/skills" bash "${REPO_ROOT}/scripts/self/apm/check_loop_pr_body_contract.sh"
    [ "$status" -eq 1 ]
    [[ $output == *"refactor/SKILL.md must list references/category-pr-body-links.md"* ]]
    [[ $output == *"refactor/SKILL.md must list assets/pr-body-template.md and assets/pr-body-template-survey.md"* ]]
}

@test "check_loop_pr_body_contract requires templates to state the keep-table-columns rule" {
    local skill_root="${TEST_TMP}/skills/tech-debt"
    mkdir -p "${skill_root}/assets" "${skill_root}/references"
    cp -R "$(apm_skill_dir tech-debt)/." "${skill_root}/"
    sed -i '/Keep the table columns as written/d' "${skill_root}/assets/pr-body-template-survey.md"

    run env SKILLS_ROOT="${TEST_TMP}/skills" bash "${REPO_ROOT}/scripts/self/apm/check_loop_pr_body_contract.sh"
    [ "$status" -eq 1 ]
    [[ $output == *"tech-debt/assets/pr-body-template-survey.md must say to keep the table columns as written"* ]]
}

@test "check_loop_pr_body_contract requires comment-posting skills to ship and list their link rules" {
    local skill
    for skill in github-issue-triage github-pr-review; do
        local skill_root="${TEST_TMP}/skills/${skill}"
        mkdir -p "${skill_root}"
        cp -R "$(apm_skill_dir "${skill}")/." "${skill_root}/"
    done
    rm -f "${TEST_TMP}/skills/github-issue-triage/references/category-pr-body-links.md"
    sed -i '/category-pr-body-links.md/d' "${TEST_TMP}/skills/github-pr-review/SKILL.md"

    run env SKILLS_ROOT="${TEST_TMP}/skills" bash "${REPO_ROOT}/scripts/self/apm/check_loop_pr_body_contract.sh"
    [ "$status" -eq 1 ]
    [[ $output == *"github-issue-triage/references/category-pr-body-links.md is missing"* ]]
    [[ $output == *"github-pr-review/SKILL.md must list references/category-pr-body-links.md"* ]]
}
