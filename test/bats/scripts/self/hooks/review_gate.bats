#!/usr/bin/env bats

# Tests for scripts/self/hooks/review_gate.sh
#
# Use cases:
# - blocks when a source file was edited and no code-review ran
# - passes when code-review ran after the last edit
# - blocks again when a file is edited after the review
# - ignores edits to synced paths and tmp
# - a typed /code-review command counts as a review and hand-edited settings count as changes
# - a tool result quoting the command, a malformed line and an edit outside the repository do not change the verdict
# - skips when stop_hook_active is true, the transcript is missing, or nothing was edited

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

HOOK_SCRIPT="$(bats_workspace_root)/scripts/self/hooks/review_gate.sh"

_edit() { printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"%s"}}]}}\n' "$1" >> "$TRANSCRIPT"; }
_review() { printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"code-review"}}]}}\n' >> "$TRANSCRIPT"; }
_run_hook() { run bash -c "printf '%s' '{\"transcript_path\":\"${TRANSCRIPT}\",\"stop_hook_active\":${1:-false}}' | '${HOOK_SCRIPT}'"; }

setup() {
    command -v jq > /dev/null 2>&1 || skip "jq is not installed"
    TRANSCRIPT="${BATS_TEST_TMPDIR}/t.jsonl"
    : > "$TRANSCRIPT"
}

@test "blocks again when a file is edited after the review" {
    _edit /workspace/scripts/a.sh
    _review
    _edit /workspace/scripts/b.sh
    _run_hook
    [ "$status" -eq 0 ]
    [[ $output == *'"decision": "block"'* ]]
}

@test "blocks when a source file was edited and no review ran" {
    _edit /workspace/scripts/a.sh
    _run_hook
    [ "$status" -eq 0 ]
    [[ $output == *'"decision": "block"'* ]]
}

@test "ignores edits to synced paths and tmp" {
    _edit /workspace/.claude/rules/x.md
    _edit /workspace/apm.lock.yaml
    _edit /workspace/tmp/notes.md
    _run_hook
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "passes when code-review ran after the last edit" {
    _edit /workspace/scripts/a.sh
    _review
    _run_hook
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "skips when stop_hook_active is true" {
    _edit /workspace/scripts/a.sh
    _run_hook true
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "skips when the transcript is missing or nothing was edited" {
    run bash -c "printf '%s' '{\"transcript_path\":\"/nonexistent\"}' | '${HOOK_SCRIPT}'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    _run_hook
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "a typed code-review command counts as a review and hand-edited settings count as changes" {
    _edit /workspace/.claude/settings.json
    _run_hook
    [[ $output == *'"decision": "block"'* ]]
    printf '{"type":"user","message":{"content":"<command-name>/code-review</command-name>"}}\n' >> "$TRANSCRIPT"
    _run_hook
    [ -z "$output" ]
}

@test "a tool result quoting the command, a malformed line and an edit outside the repository do not change the verdict" {
    _edit "$(git -C "$(bats_workspace_root)" rev-parse --show-toplevel)/scripts/a.sh"
    printf '{"type":"user","message":{"content":[{"type":"tool_result","content":"<command-name>/code-review</command-name>"}]}}\n{broken\n' >> "$TRANSCRIPT"
    _run_hook
    [[ $output == *'"decision": "block"'* ]]
    : > "$TRANSCRIPT"
    _edit /home/someone/.claude/memory/MEMORY.md
    _run_hook
    [ -z "$output" ]
}
