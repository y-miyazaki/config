#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2154

# Tests for .github/actions/loop-execute/lib/verifier_skill.sh

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/loop-execute/lib/verifier_skill.sh"
    WORKSPACE_ROOT="$(bats_workspace_root)"
    export WORKSPACE_ROOT
    unset VERIFIER_SKILL_ROOT GITHUB_WORKSPACE WORKTREE_PATH AGENT_CHECKER_SKILL_NAME
    unset PROMPT_VERIFIER_INITIAL PROMPT_VERIFIER_REGRESSION PROMPT_VERIFIER_TASK
    unset PROMPT_VERIFIER_OUTPUT_CONTRACT PROMPT_VERIFIER_DEFAULT_CRITERIA
}

@test "resolve_verifier_skill_root fails when name is unset" {
    run resolve_verifier_skill_root
    [ "$status" -eq 1 ]
}

@test "resolve_verifier_skill_root finds package source for caller name" {
    export AGENT_CHECKER_SKILL_NAME="loop-verifier"
    run resolve_verifier_skill_root
    [ "$status" -eq 0 ]
    [[ ${output} == */loop-verifier ]]
}

@test "bind_verifier_skill sets skill root without inlining SKILL.md" {
    export AGENT_CHECKER_SKILL_NAME="loop-verifier"
    bats_source_rel ".github/actions/loop-execute/lib/common.sh"
    load_default_prompts
    [[ ${VERIFIER_SKILL_ROOT} == */loop-verifier ]]
    [ -z "${PROMPT_VERIFIER_TASK:-}" ]
    [ -z "${PROMPT_VERIFIER_OUTPUT_CONTRACT:-}" ]
    [ -z "${PROMPT_VERIFIER_DEFAULT_CRITERIA:-}" ]
    [[ ${PROMPT_VERIFIER_INITIAL} == *"INITIAL verification mode"* ]]
}

@test "write_verifier_skill_slash uses /skill path when bound" {
    export AGENT_CHECKER_SKILL_NAME="loop-verifier"
    bats_source_rel ".github/actions/loop-execute/lib/common.sh"
    load_default_prompts
    run write_verifier_skill_slash
    [ "$status" -eq 0 ]
    [[ ${output} == /skill\ *SKILL.md ]]
}

@test "write_verifier_skill_input points at SKILL.md" {
    export AGENT_CHECKER_SKILL_NAME="loop-verifier"
    bats_source_rel ".github/actions/loop-execute/lib/common.sh"
    load_default_prompts
    run write_verifier_skill_input
    [ "$status" -eq 0 ]
    [[ ${output} == *"Checker skill: loop-verifier"* ]]
    [[ ${output} == *"Follow "* ]]
    [[ ${output} == *"/SKILL.md"* ]]
}

@test "write_verifier_skill_slash emits nothing when skill files are missing" {
    export AGENT_CHECKER_SKILL_NAME="missing-checker-skill"
    bats_source_rel ".github/actions/loop-execute/lib/common.sh"
    load_default_prompts
    run write_verifier_skill_slash
    [ "$status" -eq 0 ]
    [ -z "${output}" ]
    [[ ${PROMPT_VERIFIER_TASK:-} == *"loop maker"* ]]
}

@test "resolve_verifier_skill_root honors VERIFIER_SKILL_ROOT" {
    tmp_root="$(mktemp -d)"
    mkdir -p "${tmp_root}/references"
    echo "override" > "${tmp_root}/SKILL.md"
    export AGENT_CHECKER_SKILL_NAME="loop-verifier"
    export VERIFIER_SKILL_ROOT="${tmp_root}"
    run resolve_verifier_skill_root
    [ "$status" -eq 0 ]
    [ "${output}" = "${tmp_root}" ]
    rm -rf "${tmp_root}"
}
