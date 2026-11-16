#!/usr/bin/env bats

# Tests for .github/workflows/on-loop-github-pr-revise.yaml
#
# Use cases:
# - the job `if` does not admit comments by repository visibility (P9: refused classes never queue)
# - workflow_dispatch declares no `mention` input (P12: the dispatch path bypasses the mention gate)
# - detect_env_json fixes PR_MENTION to @loop

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    ROOT="$(bats_workspace_root)"
    WF="${ROOT}/.github/workflows/on-loop-github-pr-revise.yaml"
}

@test "job if does not bypass the intake gate on private repositories" {
    run grep -n 'repository.private' "${WF}"
    [ "$status" -eq 1 ]
}

@test "job if requires mention, non-Bot author and trusted association on comment events" {
    [ "$(grep -c "contains(github.event.comment.body, '@loop')" "${WF}")" -eq 2 ]
    [ "$(grep -c "github.event.comment.user.type != 'Bot'" "${WF}")" -eq 2 ]
    [ "$(grep -c 'author_association' "${WF}")" -eq 2 ]
}

@test "workflow_dispatch has no mention input" {
    run grep -nE '^      mention:|inputs\.mention' "${WF}"
    [ "$status" -eq 1 ]
}

@test "detect_env_json fixes PR_MENTION to @loop" {
    run grep -n "detect_env_json:" "${WF}"
    [ "$status" -eq 0 ]
    [[ ${output} == *"'@loop') }}"* ]]
}
