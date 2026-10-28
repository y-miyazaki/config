#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-finalize/lib/push_target.sh
#
# Use cases:
# - sequential agent merges preserve earlier product-file commits on to.branch
# - merge conflicts fail closed without updating to.branch
# - identical agent and to.branch names are rejected
# - invalid branch names are rejected

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

PUSH_SCRIPT="$(bats_workspace_root)/.github/actions/loop-finalize/lib/push_target.sh"

push_target_git_setup() {
    PUSH_BARE="${BATS_TEST_TMPDIR}/origin.git"
    PUSH_WORK="${BATS_TEST_TMPDIR}/work"
    rm -rf "${PUSH_BARE}" "${PUSH_WORK}"
    mkdir -p "${PUSH_WORK}"
    bats_git_init_in_place "${PUSH_WORK}"
    git -C "${PUSH_WORK}" checkout -q -b main
    printf 'base\n' > "${PUSH_WORK}/shared.txt"
    git -C "${PUSH_WORK}" add shared.txt
    git -C "${PUSH_WORK}" commit -q -m "chore: seed"
    git -C "${PUSH_WORK}" checkout -q -b feature/pr-head
    git init -q --bare "${PUSH_BARE}"
    git -C "${PUSH_WORK}" remote add origin "${PUSH_BARE}"
    git -C "${PUSH_WORK}" push -q -u origin main
    git -C "${PUSH_WORK}" push -q -u origin feature/pr-head
}

push_target_run() {
    local github_output
    github_output="${BATS_TEST_TMPDIR}/github_output"
    : > "${github_output}"
    run env \
        AGENT_BRANCH="${AGENT_BRANCH}" \
        TO_BRANCH="${TO_BRANCH}" \
        GITHUB_TOKEN="test-token" \
        GITHUB_OUTPUT="${github_output}" \
        bash -c "cd '${PUSH_WORK}' && bash '${PUSH_SCRIPT}'"
    PUSH_GITHUB_OUTPUT="${github_output}"
}

@test "push_target fails closed on merge conflict without updating to.branch" {
    push_target_git_setup

    git -C "${PUSH_WORK}" checkout -q feature/pr-head
    printf 'head-a\n' > "${PUSH_WORK}/conflict.txt"
    git -C "${PUSH_WORK}" add conflict.txt
    git -C "${PUSH_WORK}" commit -q -m "feat: head side"
    git -C "${PUSH_WORK}" push -q origin feature/pr-head

    git -C "${PUSH_WORK}" checkout -q -b loop/github-pr-revise/a feature/pr-head~
    printf 'agent-a\n' > "${PUSH_WORK}/conflict.txt"
    git -C "${PUSH_WORK}" add conflict.txt
    git -C "${PUSH_WORK}" commit -q -m "feat: agent side"
    git -C "${PUSH_WORK}" push -q -u origin loop/github-pr-revise/a

    before="$(git -C "${PUSH_BARE}" rev-parse refs/heads/feature/pr-head)"
    AGENT_BRANCH="loop/github-pr-revise/a"
    TO_BRANCH="feature/pr-head"
    push_target_run
    [ "$status" -eq 1 ]
    [[ $output == *"fail closed"* ]]
    after="$(git -C "${PUSH_BARE}" rev-parse refs/heads/feature/pr-head)"
    [ "${before}" = "${after}" ]
}

@test "push_target preserves earlier product commits when a later agent merges" {
    push_target_git_setup

    git -C "${PUSH_WORK}" checkout -q -b loop/github-pr-revise/first origin/feature/pr-head
    printf 'first-fix\n' > "${PUSH_WORK}/first.txt"
    git -C "${PUSH_WORK}" add first.txt
    git -C "${PUSH_WORK}" commit -q -m "fix: first revise"
    git -C "${PUSH_WORK}" push -q -u origin loop/github-pr-revise/first

    AGENT_BRANCH="loop/github-pr-revise/first"
    TO_BRANCH="feature/pr-head"
    push_target_run
    [ "$status" -eq 0 ]
    grep -q '^pushed=true$' "${PUSH_GITHUB_OUTPUT}"

    git -C "${PUSH_WORK}" fetch -q origin
    git -C "${PUSH_WORK}" checkout -q -b loop/github-pr-revise/second origin/feature/pr-head
    printf 'second-fix\n' > "${PUSH_WORK}/second.txt"
    git -C "${PUSH_WORK}" add second.txt
    git -C "${PUSH_WORK}" commit -q -m "fix: second revise"
    git -C "${PUSH_WORK}" push -q -u origin loop/github-pr-revise/second

    AGENT_BRANCH="loop/github-pr-revise/second"
    TO_BRANCH="feature/pr-head"
    push_target_run
    [ "$status" -eq 0 ]

    git -C "${PUSH_WORK}" fetch -q origin
    git -C "${PUSH_WORK}" checkout -q -B feature/pr-head origin/feature/pr-head
    [ -f "${PUSH_WORK}/first.txt" ]
    [ -f "${PUSH_WORK}/second.txt" ]
    grep -q 'first-fix' "${PUSH_WORK}/first.txt"
    grep -q 'second-fix' "${PUSH_WORK}/second.txt"
}

@test "push_target rejects identical agent and to.branch names" {
    push_target_git_setup
    AGENT_BRANCH="feature/pr-head"
    TO_BRANCH="feature/pr-head"
    push_target_run
    [ "$status" -eq 1 ]
    [[ $output == *"must differ from to.branch"* ]]
}

@test "push_target rejects invalid branch names" {
    push_target_git_setup
    AGENT_BRANCH="loop/bad branch"
    TO_BRANCH="feature/pr-head"
    push_target_run
    [ "$status" -eq 1 ]
    [[ $output == *"invalid agent branch"* ]]
}
