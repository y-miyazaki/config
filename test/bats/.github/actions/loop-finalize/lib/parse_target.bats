#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-finalize/lib/parse_target.sh
#
# Use cases:
# - an empty TARGET_JSON fails (no silent open_pr fallback)
# - invalid JSON, a missing key, or a missing to.branch fails
# - the PR base and to_branch come from target_json.to.branch (integration and pull_request)
# - an empty or unimplemented (issue_create) delivery fails
# - issue_comment accepts an issue entity and pr_review accepts a pr entity
# - pr_push with an integration target fails (delivery/target guard)
# - an empty STATE_BRANCH fails before any PR or push step runs

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

PARSE_SCRIPT="$(bats_workspace_root)/.github/actions/loop-finalize/lib/parse_target.sh"

setup() {
    export GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/github_output"
    export STATE_BRANCH="main"
    : > "${GITHUB_OUTPUT}"
}

@test "parse_target fails for an empty or unimplemented delivery" {
    local delivery checked=0
    for delivery in "" open_pr push_head issue_create; do
        run env DELIVERY="${delivery}" TARGET_JSON='{"key":"integration:main","mode":"integration","to":{"branch":"main"}}' \
            bash "${PARSE_SCRIPT}"
        [ "${status}" -eq 1 ]
        [[ ${output} == *"::error::delivery"* ]]
        [ ! -s "${GITHUB_OUTPUT}" ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 4 ]
}

@test "parse_target accepts issue_comment with an issue entity and pr_review with a pr entity" {
    run env DELIVERY=issue_comment TARGET_JSON='{"key":"entity:issue:3","entity":{"handoff_key":"entity:issue:3","kind":"issue"},"to":{"branch":"main"}}' \
        bash "${PARSE_SCRIPT}"
    [ "${status}" -eq 0 ]
    run cat "${GITHUB_OUTPUT}"
    [ "${output}" = $'base_branch=main\ntarget_key=entity:issue:3\npr_base_branch=main\nto_branch=main' ]
    : > "${GITHUB_OUTPUT}"
    run env DELIVERY=pr_review TARGET_JSON='{"key":"entity:pr:4","entity":{"handoff_key":"entity:pr:4","kind":"pr"},"to":{"branch":"main"}}' \
        bash "${PARSE_SCRIPT}"
    [ "${status}" -eq 0 ]
    run cat "${GITHUB_OUTPUT}"
    [ "${output}" = $'base_branch=main\ntarget_key=entity:pr:4\npr_base_branch=main\nto_branch=main' ]
    run env DELIVERY=issue_comment TARGET_JSON='{"key":"entity:pr:4","entity":{"kind":"pr"},"to":{"branch":"main"}}' \
        bash "${PARSE_SCRIPT}"
    [ "${status}" -eq 1 ]
}

@test "parse_target fails for an empty target_json" {
    run env DELIVERY=pr_create TARGET_JSON='' bash "${PARSE_SCRIPT}"
    [ "${status}" -eq 1 ]
    [ "${output}" = "::error::target_json is required" ]
    [ ! -s "${GITHUB_OUTPUT}" ]
}

@test "parse_target fails for invalid JSON, a missing key, or a missing to.branch" {
    local target checked=0
    for target in 'not-json' '{"mode":"integration","to":{"branch":"main"}}' '{"key":"integration:main","mode":"integration"}'; do
        run env DELIVERY=pr_create TARGET_JSON="${target}" bash "${PARSE_SCRIPT}"
        [ "${status}" -eq 1 ]
        [[ ${output} == "::error::target_json"* ]]
        [ ! -s "${GITHUB_OUTPUT}" ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 3 ]
}

@test "parse_target fails for an empty state_branch" {
    run env DELIVERY=pr_create STATE_BRANCH='' TARGET_JSON='{"key":"integration:main","mode":"integration","to":{"branch":"main"}}' \
        bash "${PARSE_SCRIPT}"
    [ "${status}" -eq 1 ]
    [ "${output}" = "::error::state_branch is required" ]
    [ ! -s "${GITHUB_OUTPUT}" ]
}

@test "parse_target fails for pr_push with an integration target" {
    run env DELIVERY=pr_push TARGET_JSON='{"key":"integration:main","mode":"integration","to":{"branch":"main"}}' \
        bash "${PARSE_SCRIPT}"
    [ "${status}" -eq 1 ]
    [[ ${output} == *"::error::delivery pr_push allows only pull_request targets (got: integration)"* ]]
    [ ! -s "${GITHUB_OUTPUT}" ]
}

@test "parse_target reads the PR base from target_json for an integration target" {
    run env DELIVERY=pr_create TARGET_JSON='{"key":"integration:release","mode":"integration","to":{"branch":"release"}}' \
        bash "${PARSE_SCRIPT}"
    [ "${status}" -eq 0 ]
    run cat "${GITHUB_OUTPUT}"
    [ "${output}" = $'base_branch=release\ntarget_key=integration:release\npr_base_branch=release\nto_branch=release' ]
}

@test "parse_target reads the PR base from target_json for a pull_request target" {
    run env DELIVERY=pr_push TARGET_JSON='{"key":"pull_request:7","mode":"pull_request","to":{"branch":"feature/x","pr_number":7},"base":{"branch":"main"}}' \
        bash "${PARSE_SCRIPT}"
    [ "${status}" -eq 0 ]
    run cat "${GITHUB_OUTPUT}"
    [ "${output}" = $'base_branch=main\ntarget_key=pull_request:7\npr_base_branch=feature/x\nto_branch=feature/x' ]
}

@test "writes base_branch from base.branch for pull_request and to.branch otherwise" {
    run env DELIVERY=pr_push TARGET_JSON='{"key":"pull_request:7","mode":"pull_request","to":{"branch":"feature/x","pr_number":7},"base":{"branch":"develop"}}' \
        bash "${PARSE_SCRIPT}"
    [ "${status}" -eq 0 ]
    grep -qx 'base_branch=develop' "${GITHUB_OUTPUT}"
    : > "${GITHUB_OUTPUT}"
    run env DELIVERY=pr_create TARGET_JSON='{"key":"integration:release","mode":"integration","to":{"branch":"release"},"base":{"branch":"ignored"}}' \
        bash "${PARSE_SCRIPT}"
    [ "${status}" -eq 0 ]
    grep -qx 'base_branch=release' "${GITHUB_OUTPUT}"
}
