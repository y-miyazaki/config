#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .apm/packages/common-hooks-claude/.apm/hooks/scripts/prettier.sh
#          (copilot and cursor variants share get_changed_files)
#
# Use cases:
# - get_changed_files lists only changed prettier-supported files
# - report_failure emits PostToolUse additionalContext for Claude Code
# - report_failure emits exit 2 + stderr for Cursor afterFileEdit
# - main skips silently when no prettier-supported file changed

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

PKG_ROOT="$(bats_workspace_root)/.apm/packages"

setup() {
    TEST_REPO="$(mktemp -d)"
    git -C "${TEST_REPO}" init -q
    git -C "${TEST_REPO}" config user.email test@example.com
    git -C "${TEST_REPO}" config user.name test
    cd "${TEST_REPO}" || return 1
}

teardown() {
    cd /
    rm -rf "${TEST_REPO}"
}

@test "get_changed_files lists changed prettier-supported files only" {
    for agent in claude copilot cursor; do
        printf 'a: 1\n' > a.yaml
        printf '# t\n' > b.md
        printf 'echo hi\n' > c.sh
        run bash -c 'source "$1"; get_changed_files' _ "${PKG_ROOT}/common-hooks-${agent}/.apm/hooks/scripts/prettier.sh"
        [ "$status" -eq 0 ]
        [[ ${output} == *"a.yaml"* ]]
        [[ ${output} == *"b.md"* ]]
        [[ ${output} != *"c.sh"* ]]
        rm -f a.yaml b.md c.sh
    done
}

@test "main exits 0 silently when no prettier-supported file changed" {
    printf 'echo hi\n' > only.sh
    run bash "${PKG_ROOT}/common-hooks-claude/.apm/hooks/scripts/prettier.sh" < /dev/null
    [ "$status" -eq 0 ]
    [ -z "${output}" ]
}

@test "report_failure emits additionalContext for Claude Code PostToolUse" {
    HOOK_SCRIPT="${PKG_ROOT}/common-hooks-claude/.apm/hooks/scripts/prettier.sh"
    run bash -c 'source "$1"; HOOK_STDIN_DATA="{\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Write\"}"; report_failure "prettier failed: x"' _ "${HOOK_SCRIPT}"
    [ "$status" -eq 0 ]
    [[ ${output} == *'"additionalContext"'* ]]
    [[ ${output} == *'prettier failed: x'* ]]
}

@test "report_failure exits 2 with stderr for Cursor afterFileEdit" {
    HOOK_SCRIPT="${PKG_ROOT}/common-hooks-cursor/.apm/hooks/scripts/prettier.sh"
    run bash -c 'source "$1"; HOOK_STDIN_DATA="{\"hook_event_name\":\"afterFileEdit\",\"cursor_version\":\"3.13.25\",\"workspace_roots\":[\"/workspace\"]}"; report_failure "prettier failed: x" 2>&1' _ "${HOOK_SCRIPT}"
    [ "$status" -eq 2 ]
    [[ ${output} == *'prettier failed: x'* ]]
}
