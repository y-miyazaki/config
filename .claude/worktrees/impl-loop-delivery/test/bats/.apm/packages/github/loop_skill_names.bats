#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .apm/packages/github/.apm/skills/ (loop entry skills: github-issue-autofix,
# github-issue-triage, github-pr-review, github-pr-revise)
#
# Use cases:
# - each loop skill branches on the agent_edit_allowed / agent_edit_target prompt keys
# - no loop skill mentions retired prompt keys, platform names, or may-edit eval file names
# - no loop skill mentions retired outcome values (pr-created, pr-closed, no-changes, no-action)

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

RETIRED_OUTCOMES='pr-created|pr-closed|no-changes|no-action'

@test "github-issue-autofix branches on agent_edit_allowed and agent_edit_target" {
    run grep -c 'agent_edit_allowed' "$(apm_skill_dir github-issue-autofix)/SKILL.md"
    [ "$status" -eq 0 ]
    run grep -c 'agent_edit_target' "$(apm_skill_dir github-issue-autofix)/SKILL.md"
    [ "$status" -eq 0 ]
}

@test "github-issue-autofix has no retired loop names" {
    run assert_apm_skill_no_legacy_loop_names github-issue-autofix "${RETIRED_OUTCOMES}"
    [ "$status" -eq 0 ]
}

@test "github-issue-triage branches on agent_edit_allowed" {
    run grep -c 'agent_edit_allowed' "$(apm_skill_dir github-issue-triage)/SKILL.md"
    [ "$status" -eq 0 ]
}

@test "github-issue-triage has no retired loop names" {
    run assert_apm_skill_no_legacy_loop_names github-issue-triage "${RETIRED_OUTCOMES}"
    [ "$status" -eq 0 ]
}

@test "github-pr-review branches on agent_edit_allowed and agent_edit_target" {
    run grep -c 'agent_edit_allowed' "$(apm_skill_dir github-pr-review)/SKILL.md"
    [ "$status" -eq 0 ]
    run grep -c 'agent_edit_target' "$(apm_skill_dir github-pr-review)/SKILL.md"
    [ "$status" -eq 0 ]
}

@test "github-pr-review has no retired loop names" {
    run assert_apm_skill_no_legacy_loop_names github-pr-review "${RETIRED_OUTCOMES}"
    [ "$status" -eq 0 ]
}

@test "github-pr-revise branches on agent_edit_allowed and agent_edit_target" {
    run grep -c 'agent_edit_allowed' "$(apm_skill_dir github-pr-revise)/SKILL.md"
    [ "$status" -eq 0 ]
    run grep -c 'agent_edit_target' "$(apm_skill_dir github-pr-revise)/SKILL.md"
    [ "$status" -eq 0 ]
}

@test "github-pr-revise has no retired loop names" {
    run assert_apm_skill_no_legacy_loop_names github-pr-revise "${RETIRED_OUTCOMES}"
    [ "$status" -eq 0 ]
}
