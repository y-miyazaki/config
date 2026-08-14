#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for scripts/self/apm/apm_skill_root.sh

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    REPO_ROOT="$(bats_workspace_root)"
    WORKSPACE_ROOT="${REPO_ROOT}"
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/self/apm/apm_skill_root.sh"
}

@test "apm_skill_root resolves repo-maintenance changelog" {
    run apm_skill_root changelog
    [ "$status" -eq 0 ]
    [[ $output == *"/repo-maintenance/.apm/skills/changelog" ]]
}

@test "apm_skill_root resolves github github-issue-autofix" {
    run apm_skill_root github-issue-autofix
    [ "$status" -eq 0 ]
    [[ $output == *"/github/.apm/skills/github-issue-autofix" ]]
}

@test "apm_skill_root resolves common agent-skills-review" {
    run apm_skill_root agent-skills-review
    [ "$status" -eq 0 ]
    [[ $output == *"/common/.apm/skills/agent-skills-review" ]]
}

@test "apm_skill_root fails for unknown skill" {
    run apm_skill_root not-a-real-skill
    [ "$status" -eq 1 ]
}
