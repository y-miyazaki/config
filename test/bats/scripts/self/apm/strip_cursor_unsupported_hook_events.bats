#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for scripts/self/apm/strip_cursor_unsupported_hook_events.sh
#
# Use cases:
# - removes PascalCase Stop/PostToolUse/PreToolUse from .cursor/hooks.json
# - preserves camelCase stop/postToolUse/preToolUse and other events
# - no-op when hooks.json is missing
# - idempotent when PascalCase keys are already absent
# - fails with clear error when jq is unavailable

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    REPO_ROOT="$(bats_workspace_root)"
    TEST_TMP="${BATS_TEST_TMPDIR}/strip_cursor_hooks"
    mkdir -p "${TEST_TMP}/.cursor"
    HOOKS_JSON="${TEST_TMP}/.cursor/hooks.json"
    SCRIPT="${REPO_ROOT}/scripts/self/apm/strip_cursor_unsupported_hook_events.sh"
}

@test "strip_cursor_unsupported_hook_events removes PascalCase Stop PostToolUse PreToolUse" {
    cat > "${HOOKS_JSON}" << 'EOF'
{
  "version": 1,
  "hooks": {
    "stop": [{"command": "keep-stop.sh"}],
    "postToolUse": [{"command": "keep-post.sh"}],
    "preToolUse": [{"command": "keep-pre.sh"}],
    "afterFileEdit": [{"command": "keep-edit.sh"}],
    "Stop": [{"matcher": "", "hooks": [{"type": "command", "command": "drop-stop.sh"}]}],
    "PostToolUse": [{"matcher": "", "hooks": [{"type": "command", "command": "drop-post.sh"}]}],
    "PreToolUse": [{"matcher": "", "hooks": [{"type": "command", "command": "drop-pre.sh"}]}]
  }
}
EOF

    run bash "${SCRIPT}" "${HOOKS_JSON}"
    [ "$status" -eq 0 ]

    run jq -r '.hooks | keys[]' "${HOOKS_JSON}"
    [ "$status" -eq 0 ]
    [[ $output == *"afterFileEdit"* ]]
    [[ $output == *"postToolUse"* ]]
    [[ $output == *"preToolUse"* ]]
    [[ $output == *"stop"* ]]
    [[ $output != *"Stop"* ]]
    [[ $output != *"PostToolUse"* ]]
    [[ $output != *"PreToolUse"* ]]

    run jq -r '.hooks.stop[0].command' "${HOOKS_JSON}"
    [ "$status" -eq 0 ]
    [ "$output" = "keep-stop.sh" ]
}

@test "strip_cursor_unsupported_hook_events is idempotent when PascalCase keys absent" {
    cat > "${HOOKS_JSON}" << 'EOF'
{
  "version": 1,
  "hooks": {
    "stop": [{"command": "keep-stop.sh"}]
  }
}
EOF

    run bash "${SCRIPT}" "${HOOKS_JSON}"
    [ "$status" -eq 0 ]
    run bash "${SCRIPT}" "${HOOKS_JSON}"
    [ "$status" -eq 0 ]

    run jq -c '.hooks' "${HOOKS_JSON}"
    [ "$status" -eq 0 ]
    [ "$output" = '{"stop":[{"command":"keep-stop.sh"}]}' ]
}

@test "strip_cursor_unsupported_hook_events fails when jq is unavailable" {
    cat > "${HOOKS_JSON}" << 'EOF'
{
  "version": 1,
  "hooks": {
    "Stop": [{"matcher": "", "hooks": [{"type": "command", "command": "drop-stop.sh"}]}]
  }
}
EOF

    EMPTY_BIN="${BATS_TEST_TMPDIR}/empty_bin"
    mkdir -p "${EMPTY_BIN}"

    run env PATH="${EMPTY_BIN}" /bin/bash "${SCRIPT}" "${HOOKS_JSON}"
    [ "$status" -eq 1 ]
    [[ $output == *"jq is required"* ]]
}

@test "strip_cursor_unsupported_hook_events no-ops when hooks.json missing" {
    rm -f "${HOOKS_JSON}"
    run bash "${SCRIPT}" "${HOOKS_JSON}"
    [ "$status" -eq 0 ]
}
