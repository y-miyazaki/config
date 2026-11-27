#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031

# Tests for .apm/packages/*-hooks-*/.apm/hooks/scripts/review_gate.sh
#
# Use cases:
# - asks for a review when the working tree changed and the state was not reported yet
# - passes when the same state was already reported and asks again when the state changes
# - the reason lets the agent finish without a second review when the diff was already reviewed
# - passes in a clean working tree and after REVIEW_GATE_DISABLED=1; stop_hook_active does not pass a changed state
# - REVIEW_GATE_MAX_PROMPTS bounds the review requests of one session, a clean tree resets the count
#   and a value that is not a positive number falls back to the default
# - Cursor stop events get the followup_message format
# - Copilot and Cursor use their own review command
# - REVIEW_GATE_COMMAND_<AGENT> overrides the review command for one agent
# - REVIEW_GATE_MODEL[_<AGENT>] names the review model in the reason; when empty the reason asks for a different model and leaves the model choice to the agent
# - the reason leaves the review depth to the agent in every case
# - agent-managed synced files are not listed as changes, hand-edited settings are
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
    export TMPDIR="${BATS_TEST_TMPDIR}/state-tmp"
    unset HOOK_BLOCK_LIMIT REVIEW_GATE_MODEL REVIEW_GATE_MODEL_CLAUDE REVIEW_GATE_MODEL_COPILOT REVIEW_GATE_COMMAND REVIEW_GATE_DISABLED REVIEW_GATE_MAX_PROMPTS
    mkdir -p "${REPO}" "${TMPDIR}"
    git -C "${REPO}" init -q
    git -C "${REPO}" config user.email t@example.com
    git -C "${REPO}" config user.name t
    printf 'one\n' > "${REPO}/a.txt"
    git -C "${REPO}" add a.txt
    git -C "${REPO}" commit -q -m init
}

_dirty() { printf '%s\n' "$RANDOM" >> "${REPO}/a.txt"; }
_run_hook() {
    local payload
    payload=$(jq -nc --arg s "${1:-s1}" --argjson a "${2:-false}" '{hook_event_name:"Stop",session_id:$s,transcript_path:"/nonexistent",stop_hook_active:$a}')
    run bash -c "cd '${REPO}' && printf '%s' '${payload}' | ${3:-} '${HOOK}'"
}
_run_copilot() {
    run bash -c "cd '${REPO}' && printf '%s' '{\"sessionId\":\"${1:-s2}\",\"transcriptPath\":\"/nonexistent\",\"stopReason\":\"end_turn\"}' | ${2:-} '${HOOK}'"
}

@test "Copilot and Cursor name their own review command" {
    _dirty
    _run_copilot s2
    [ "$(printf '%s' "$output" | jq -r .decision)" = "block" ]
    [[ $output == *"/review"* && $output != *"/code-review"* ]]
    run bash -c "cd '${REPO}' && printf '%s' '{\"hook_event_name\":\"stop\",\"cursor_version\":\"3\",\"transcript_path\":null}' | '${HOOK}'"
    [[ $(printf '%s' "$output" | jq -r .followup_message) == *"/review"* ]]
}

@test "Cursor stop events get the followup_message format" {
    _dirty
    run bash -c "cd '${REPO}' && printf '%s' '{\"hook_event_name\":\"stop\",\"conversation_id\":\"c1\",\"cursor_version\":\"3\",\"transcript_path\":null}' | '${HOOK}'"
    [ "$status" -eq 0 ]
    [[ $(printf '%s' "$output" | jq -r .followup_message) == *"/review"* ]]
}

@test "REVIEW_GATE_COMMAND_<AGENT> overrides the review command for that agent only" {
    _dirty
    _run_copilot s3 "REVIEW_GATE_COMMAND_COPILOT=/my-review"
    [[ $output == *"/my-review"* ]]
    _run_hook s3b
    [[ $output == *"/code-review"* ]]
}

@test "REVIEW_GATE_MAX_PROMPTS bounds the review requests of one session" {
    export REVIEW_GATE_MAX_PROMPTS=2
    _dirty
    _run_hook
    [ "$(printf '%s' "$output" | jq -r .decision)" = "block" ]
    _dirty
    _run_hook
    [ "$(printf '%s' "$output" | jq -r .decision)" = "block" ]
    _dirty
    _run_hook
    [ -z "$output" ]
    _run_hook other-session
    [ "$(printf '%s' "$output" | jq -r .decision)" = "block" ]
}

@test "REVIEW_GATE_MAX_PROMPTS is reset by a clean tree and falls back to 3 when not a positive number" {
    export REVIEW_GATE_MAX_PROMPTS=1
    _dirty
    _run_hook
    [ "$(printf '%s' "$output" | jq -r .decision)" = "block" ]
    _dirty
    _run_hook
    [ -z "$output" ]
    git -C "${REPO}" checkout -q -- a.txt
    _run_hook
    [ -z "$output" ]
    _dirty
    _run_hook
    [ "$(printf '%s' "$output" | jq -r .decision)" = "block" ]
    export REVIEW_GATE_MAX_PROMPTS=0
    git -C "${REPO}" checkout -q -- a.txt
    for _ in 1 2 3; do
        _dirty
        _run_hook other
        [ "$(printf '%s' "$output" | jq -r .decision)" = "block" ]
    done
    _dirty
    _run_hook other
    [ -z "$output" ]
}

@test "REVIEW_GATE_MODEL applies to every agent and an empty per-agent value turns it off" {
    _dirty
    _run_copilot s5 "REVIEW_GATE_MODEL=base-m"
    [[ $output == *"with the model base-m"* ]]
    _run_hook s6 false "REVIEW_GATE_MODEL=base-m REVIEW_GATE_MODEL_CLAUDE="
    [[ $output != *"with the model"* ]]
}

@test "REVIEW_GATE_MODEL names the model in the reason, per agent first, and stays silent when empty" {
    _dirty
    _run_hook s4a
    [[ $output != *"with the model"* ]]
    _run_hook s4 false "REVIEW_GATE_MODEL=base-m REVIEW_GATE_MODEL_CLAUDE=claude-m"
    [[ $output == *"claude-m"* && $output != *"base-m"* ]]
}

@test "the reason leaves the review depth and, without REVIEW_GATE_MODEL, the model choice to the agent" {
    _dirty
    _run_hook s4b
    [[ $output == *"different model than this session"* && $output == *"review depth"* ]]
    _run_hook s4c false "REVIEW_GATE_MODEL=base-m"
    [[ $output == *"with the model base-m"* && $output != *"different model than this session"* && $output == *"review depth"* ]]
}

@test "a hand-edited settings file counts as a change but a synced skill file does not" {
    mkdir -p "${REPO}/.claude/skills"
    printf 'x\n' > "${REPO}/.claude/skills/s.md"
    printf '{}\n' > "${REPO}/.claude/settings.json"
    _run_hook
    [[ $output == *".claude/settings.json"* ]]
    [[ $output != *"skills/s.md"* ]]
}

@test "asks for a review of a changed tree, passes for the same state and asks again when it changes" {
    _dirty
    _run_hook
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq -r .decision)" = "block" ]
    [[ $output == *"/code-review"* ]]
    _run_hook
    [ -z "$output" ]
    _dirty
    _run_hook
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

@test "passes in a clean working tree and when disabled, but not for a changed state under stop_hook_active" {
    _run_hook
    [ -z "$output" ]
    _dirty
    _run_hook s1 false "REVIEW_GATE_DISABLED=1"
    [ -z "$output" ]
    _run_hook s1 true
    [ "$(printf '%s' "$output" | jq -r .decision)" = "block" ]
}

@test "the reason lets the agent finish without a second review when the diff was already reviewed" {
    _dirty
    _run_hook
    [[ $output == *"already reviewed"* && $output == *"without reviewing again"* ]]
}
