#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .apm/packages/loop-tech-debt/.apm/skills/loop-tech-debt/scripts/detect_tech_debt.sh
#
# Use cases:
# - detect_tech_debt defaults to scope all and skips on empty fixture repo
# - detect_tech_debt rejects unknown --scope
# - detect_tech_debt range without --since returns error JSON exit 0

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

DETECT_SCRIPT="$(apm_skill_script_path loop-tech-debt detect_tech_debt.sh)"

@test "detect_tech_debt defaults to scope all and skips on empty fixture repo" {
    git_test_repo_setup
    printf 'ok\n' > "${GIT_TEST_REPO}/README.md"
    git -C "${GIT_TEST_REPO}" add README.md
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    git_test_repo_run "bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    assert_detect_tech_debt_ok_json "${output}" "all" ""
    [[ $output == *'"skip": true'* ]]
}

@test "detect_tech_debt rejects unknown --scope" {
    git_test_repo_setup
    touch "${GIT_TEST_REPO}/file.txt"
    git -C "${GIT_TEST_REPO}" add file.txt
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    git_test_repo_run "bash '${DETECT_SCRIPT}' --scope weird"
    [ "$status" -eq 0 ]
    assert_detect_tech_debt_error_json "${output}" "scope"
}

@test "detect_tech_debt range without --since returns error JSON exit 0" {
    git_test_repo_setup
    touch "${GIT_TEST_REPO}/file.txt"
    git -C "${GIT_TEST_REPO}" add file.txt
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    git_test_repo_run "bash '${DETECT_SCRIPT}' --scope range"
    [ "$status" -eq 0 ]
    assert_detect_tech_debt_error_json "${output}" "requires --since"
}
