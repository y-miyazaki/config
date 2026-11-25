#!/usr/bin/env bats

# Tests for .apm/packages/*-hooks-*/.apm/hooks/scripts/review_gate.sh
#
# Use cases:
# - blocks when files changed and the transcript shows no review
# - passes when a review marker follows the last edit and blocks again for a later edit
# - passes in a clean working tree (chat-only turn) and after REVIEW_GATE_DISABLED=1 or stop_hook_active
# - without a readable transcript blocks once per working-tree state, then skips
# - REVIEW_GATE_MARKER / REVIEW_GATE_EDIT_MARKER adapt the detection to another agent
# - a tool result that quotes the review command or an edit never counts as one
# - a dirty tree without any edit tool call in the session (chat-only turn) passes
# - Cursor stop events get the followup_message format
# - Copilot and Cursor (undocumented transcript format) use the counter and their own review command
# - REVIEW_GATE_COMMAND_<AGENT> overrides the review command for one agent
# - REVIEW_GATE_MODEL[_<AGENT>] names the review model in the reason and stays silent when empty
# - detect_agent names the agent from the event JSON
# - every agent package ships the same script

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    command -v jq > /dev/null 2>&1 || skip "jq is not installed"
    ROOT="$(bats_workspace_root)"
    HOOK="${ROOT}/.apm/packages/common-hooks-claude/.apm/hooks/scripts/review_gate.sh"
    REPO="${BATS_TEST_TMPDIR}/repo"
    TRANSCRIPT="${BATS_TEST_TMPDIR}/t.jsonl"
    export TMPDIR="${BATS_TEST_TMPDIR}/state-tmp"
    unset HOOK_BLOCK_LIMIT REVIEW_GATE_MODEL REVIEW_GATE_MODEL_CLAUDE REVIEW_GATE_MODEL_COPILOT REVIEW_GATE_COMMAND REVIEW_GATE_DISABLED REVIEW_GATE_MARKER REVIEW_GATE_EDIT_MARKER
    mkdir -p "${REPO}" "${TMPDIR}"
    git -C "${REPO}" init -q
    git -C "${REPO}" config user.email t@example.com
    git -C "${REPO}" config user.name t
    printf 'one\n' > "${REPO}/a.txt"
    git -C "${REPO}" add a.txt
    git -C "${REPO}" commit -q -m init
    : > "$TRANSCRIPT"
}

_edit() { printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"x"}}]}}\n' >> "$TRANSCRIPT"; }
_review() { printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"code-review"}}]}}\n' >> "$TRANSCRIPT"; }
_dirty() { printf '%s\n' "$RANDOM" >> "${REPO}/a.txt"; }
_run_hook() {
    local payload
    payload=$(jq -nc --arg t "${1-$TRANSCRIPT}" --argjson a "${2:-false}" '{hook_event_name:"Stop",session_id:"s1",transcript_path:$t,stop_hook_active:$a}')
    run bash -c "cd '${REPO}' && printf '%s' '${payload}' | '${HOOK}'"
}

@test "REVIEW_GATE_MARKER and REVIEW_GATE_EDIT_MARKER adapt the detection to another agent" {
    _dirty
    printf 'AGENT-EDIT\nAGENT-REVIEW\n' > "$TRANSCRIPT"
    run bash -c "cd '${REPO}' && printf '%s' '{\"hook_event_name\":\"Stop\",\"session_id\":\"s1\",\"transcript_path\":\"${TRANSCRIPT}\"}' | REVIEW_GATE_MARKER=AGENT-REVIEW REVIEW_GATE_EDIT_MARKER=AGENT-EDIT '${HOOK}'"
    [ -z "$output" ]
}

@test "blocks when files changed and the transcript shows no review" {
    _dirty
    _edit
    _run_hook
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq -r .decision)" = "block" ]
    [[ $output == *"/code-review"* ]]
}

@test "blocks once per working-tree state when the transcript is unreadable" {
    _dirty
    _run_hook /nonexistent
    [ "$(printf '%s' "$output" | jq -r .decision)" = "block" ]
    _run_hook /nonexistent
    [ -z "$output" ]
    _dirty
    _run_hook /nonexistent
    [ "$(printf '%s' "$output" | jq -r .decision)" = "block" ]
}

@test "detect_agent names the agent from the event JSON" {
    run bash -c "source '${HOOK}' </dev/null; for j in '{\"generation_id\":\"c\"}' '{\"transcriptPath\":\"p\"}' '{\"transcript_path\":\"p\"}' '{}'; do HOOK_STDIN_DATA=\$j detect_agent; done"
    [ "$output" = $'cursor\ncopilot\nclaude\nunknown' ]
}

@test "every agent package ships the same script" {
    for pkg in copilot cursor; do
        cmp "$HOOK" "${ROOT}/.apm/packages/common-hooks-${pkg}/.apm/hooks/scripts/review_gate.sh"
    done
}

@test "passes and blocks again according to the order of review and edit" {
    _dirty
    _edit
    _review
    _run_hook
    [ -z "$output" ]
    _edit
    _run_hook
    [ "$(printf '%s' "$output" | jq -r .decision)" = "block" ]
}

@test "passes in a clean working tree, when disabled and when stop_hook_active is true" {
    _edit
    _run_hook
    [ -z "$output" ]
    _dirty
    _run_hook "$TRANSCRIPT" true
    [ -z "$output" ]
    run bash -c "cd '${REPO}' && printf '%s' '{\"hook_event_name\":\"Stop\",\"session_id\":\"s1\",\"transcript_path\":\"${TRANSCRIPT}\"}' | REVIEW_GATE_DISABLED=1 '${HOOK}'"
    [ -z "$output" ]
}

@test "a tool result quoting the review command never counts as a review" {
    _dirty
    _edit
    printf '{"type":"user","message":{"content":[{"type":"tool_result","content":"<command-name>/code-review</command-name> \"skill\":\"code-review\""}]}}\n' >> "$TRANSCRIPT"
    _run_hook
    [ "$(printf '%s' "$output" | jq -r .decision)" = "block" ]
}

@test "a dirty tree without any edit tool call in the session passes" {
    _dirty
    _run_hook
    [ -z "$output" ]
}

@test "Cursor stop events get the followup_message format" {
    _dirty
    run bash -c "cd '${REPO}' && printf '%s' '{\"hook_event_name\":\"stop\",\"conversation_id\":\"c1\",\"cursor_version\":\"3\",\"transcript_path\":null}' | '${HOOK}'"
    [ "$status" -eq 0 ]
    [[ $(printf '%s' "$output" | jq -r .followup_message) == *"/review"* ]]
}

@test "a hand-edited settings file counts as a change but a synced skill file does not" {
    mkdir -p "${REPO}/.claude/skills"
    printf 'x\n' > "${REPO}/.claude/skills/s.md"
    printf '{}\n' > "${REPO}/.claude/settings.json"
    _edit
    _run_hook
    [[ $output == *".claude/settings.json"* ]]
    [[ $output != *"skills/s.md"* ]]
}

@test "Copilot and Cursor use the counter and their own review command because the transcript format is undocumented" {
    _dirty
    _review
    _edit
    run bash -c "cd '${REPO}' && printf '%s' '{\"sessionId\":\"s2\",\"transcriptPath\":\"${TRANSCRIPT}\",\"stopReason\":\"end_turn\"}' | '${HOOK}'"
    [ "$(printf '%s' "$output" | jq -r .decision)" = "block" ]
    [[ $output == *"/review"* && $output != *"/code-review"* ]]
    run bash -c "cd '${REPO}' && printf '%s' '{\"sessionId\":\"s2\",\"transcriptPath\":\"${TRANSCRIPT}\",\"stopReason\":\"end_turn\"}' | '${HOOK}'"
    [ -z "$output" ]
}

@test "REVIEW_GATE_COMMAND_<AGENT> overrides the review command for that agent only" {
    _dirty
    run bash -c "cd '${REPO}' && printf '%s' '{\"sessionId\":\"s3\",\"transcriptPath\":\"${TRANSCRIPT}\",\"stopReason\":\"end_turn\"}' | REVIEW_GATE_COMMAND_COPILOT=/my-review '${HOOK}'"
    [[ $output == *"/my-review"* ]]
    _edit
    _run_hook
    [[ $output == *"/code-review"* ]]
}

@test "REVIEW_GATE_MODEL names the model in the reason, per agent first, and stays silent when empty" {
    _dirty
    _edit
    _run_hook
    [[ $output != *"with the model"* ]]
    run bash -c "cd '${REPO}' && printf '%s' '{\"hook_event_name\":\"Stop\",\"session_id\":\"s4\",\"transcript_path\":\"${TRANSCRIPT}\"}' | REVIEW_GATE_MODEL=base-m REVIEW_GATE_MODEL_CLAUDE=claude-m '${HOOK}'"
    [[ $output == *"claude-m"* && $output != *"base-m"* ]]
}

@test "REVIEW_GATE_MODEL applies to every agent and an empty per-agent value turns it off" {
    _dirty
    run bash -c "cd '${REPO}' && printf '%s' '{\"sessionId\":\"s5\",\"transcriptPath\":\"${TRANSCRIPT}\",\"stopReason\":\"end_turn\"}' | REVIEW_GATE_MODEL=base-m '${HOOK}'"
    [[ $output == *"with the model base-m"* ]]
    _edit
    run bash -c "cd '${REPO}' && printf '%s' '{\"hook_event_name\":\"Stop\",\"session_id\":\"s6\",\"transcript_path\":\"${TRANSCRIPT}\"}' | REVIEW_GATE_MODEL=base-m REVIEW_GATE_MODEL_CLAUDE= '${HOOK}'"
    [[ $output != *"with the model"* ]]
}
