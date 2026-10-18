#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-agent-once/lib/run.sh
#
# Use cases:
# - emit_usage_json_output writes empty usage_json when nothing was captured
# - emit_usage_json_output writes measured totals to GITHUB_OUTPUT
# - run_loop_agent_once captures cursor stream-json usage via a mock agent
# - run_loop_agent_once maps AGENT_MAKER_MODEL / AGENT_MAKER_EFFORT /
#   AGENT_MAKER_MAX_TURNS onto the role vars MODEL / EFFORT / MAX_TURNS before
#   run_agent and run_agent_capture (asserted on the stubbed claude CLI args);
#   the legacy MODEL / EFFORT / MAX_TURNS env values do not reach the agent
# - run_loop_agent_once reads AGENT_ENGINE, not the legacy ENGINE name
# - run_loop_agent_once passes the fixed claude permission surface (acceptEdits, read baseline, deny list)
# - run_loop_agent_once appends the message directory to the prompt and creates it
# - run_loop_agent_once emits message_json from message.md and message_labels.json
# - run_loop_agent_once emits an empty message_json when message.md is missing or labels are malformed
# - run_loop_agent_once keeps a multi-line body intact through GITHUB_OUTPUT
# - run_loop_agent_once never calls gh (delivery moved to loop-finalize)

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/loop-agent-once/lib/run.sh"
    reset_usage_totals
    GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/github_output"
    : > "${GITHUB_OUTPUT}"
    export GITHUB_OUTPUT
}

# _stub_claude_cli: Put a claude stub on PATH that records its argument line
#
# Globals:
#   CLAUDE_ARGS_FILE - File that receives the recorded argument line (write)
#   CLAUDE_BASE_ARGS - Arguments run_agent always passes for this prompt (write)
_stub_claude_cli() {
    local bindir="${BATS_TEST_TMPDIR}/bin-claude"
    CLAUDE_ARGS_FILE="${BATS_TEST_TMPDIR}/claude-args.txt"
    mkdir -p "${bindir}" "${BATS_TEST_TMPDIR}/home"
    cat > "${bindir}/claude" << STUB
#!/bin/bash
printf '%s\n' "\$*" > "${CLAUDE_ARGS_FILE}"
STUB
    chmod +x "${bindir}/claude"
    PATH="${bindir}:${PATH}"
    HOME="${BATS_TEST_TMPDIR}/home"
    unset GITHUB_WORKSPACE CLAUDE_CONFIG_DIR AGENT_TOOL_ALLOWLIST DETECT_JSON_FILE LOOP_MESSAGE_DIR
    AGENT_ENGINE="claude"
    AGENT_TOKEN="dummy-token"
    PROMPT="hello"
    WORKING_DIRECTORY="."
    CLAUDE_BASE_ARGS='-p hello --output-format stream-json --verbose --settings {"enableAllProjectMcpServers":true} --setting-sources project --permission-mode acceptEdits --allowedTools Bash(git diff:*) Bash(git log:*) Bash(git show:*) Bash(git status:*) --disallowedTools Bash(curl:*) Bash(gh api *--method*) Bash(gh api *-X DELETE*) Bash(gh api *-X PATCH*) Bash(gh api *-X POST*) Bash(gh api *-X PUT*) Bash(gh issue close:*) Bash(gh issue comment:*) Bash(gh issue create:*) Bash(gh issue delete:*) Bash(gh issue edit:*) Bash(gh label create:*) Bash(gh label delete:*) Bash(gh label edit:*) Bash(gh pr close:*) Bash(gh pr comment:*) Bash(gh pr create:*) Bash(gh pr edit:*) Bash(gh pr merge:*) Bash(gh pr review:*) Bash(gh release create:*) Bash(gh release delete:*) Bash(gh release edit:*) Bash(gh release upload:*) Bash(gh run cancel:*) Bash(gh run rerun:*) Bash(gh secret:*) Bash(gh variable:*) Bash(gh workflow run:*) Bash(git diff *--output*) Bash(git push:*) Bash(printenv:*) Bash(sudo:*) Bash(wget:*)'
}

@test "emit_usage_json_output writes empty usage_json when nothing captured" {
    emit_usage_json_output
    grep -q '^usage_json=$' "${GITHUB_OUTPUT}"
}

@test "emit_usage_json_output writes measured totals" {
    USAGE_INPUT_TOTAL=1842
    USAGE_OUTPUT_TOTAL=17
    USAGE_MODEL="composer-2.5"
    emit_usage_json_output
    grep -q 'total_input_tokens' "${GITHUB_OUTPUT}"
    grep -q '"total_input_tokens":1842' "${GITHUB_OUTPUT}" || grep -q '1842' "${GITHUB_OUTPUT}"
}

@test "run_loop_agent_once captures cursor stream-json usage from mock agent" {
    local bindir fixture
    fixture="$(bats_workspace_root)/test/fixtures/loop-execute/cursor-stream-json-usage.ndjson"
    [ -f "${fixture}" ]
    bindir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${bindir}"
    cat > "${bindir}/agent" << EOF
#!/bin/bash
cat "${fixture}"
EOF
    chmod +x "${bindir}/agent"
    export PATH="${bindir}:${PATH}"
    export AGENT_ENGINE="cursor"
    export AGENT_TOKEN="test-token"
    export PROMPT="hello"
    export WORKING_DIRECTORY="."
    export AGENT_MAKER_MAX_TURNS=""
    export AGENT_MAKER_MODEL=""
    export OUTPUT_FILE=""
    run run_loop_agent_once
    [ "$status" -eq 0 ]
    grep -q '1842' "${GITHUB_OUTPUT}"
    grep -q '17' "${GITHUB_OUTPUT}"
}

@test "run_loop_agent_once fails without AGENT_ENGINE even when legacy ENGINE is set" {
    local bindir
    bindir="${BATS_TEST_TMPDIR}/bin-legacy"
    mkdir -p "${bindir}"
    printf '#!/bin/bash\necho agent-ran\n' > "${bindir}/agent"
    chmod +x "${bindir}/agent"
    export PATH="${bindir}:${PATH}"
    unset AGENT_ENGINE
    export ENGINE="cursor"
    export AGENT_TOKEN="test-token"
    export PROMPT="hello"
    export OUTPUT_FILE=""
    run run_loop_agent_once
    [ "$status" -ne 0 ]
    [[ ${output} != *"agent-ran"* ]]
}

@test "run_loop_agent_once maps AGENT_MAKER_* onto the role vars before run_agent" {
    _stub_claude_cli
    MODEL="legacy-model"
    EFFORT="legacy-effort"
    MAX_TURNS="99"
    AGENT_MAKER_MODEL="claude-sonnet-5"
    AGENT_MAKER_EFFORT="high"
    AGENT_MAKER_MAX_TURNS="7"
    OUTPUT_FILE=""
    run run_loop_agent_once
    [ "$status" -eq 0 ]
    [ "$(cat "${CLAUDE_ARGS_FILE}")" = "${CLAUDE_BASE_ARGS} --effort high --max-turns 7 --model claude-sonnet-5" ]
}

@test "run_loop_agent_once maps AGENT_MAKER_* onto the role vars before run_agent_capture" {
    _stub_claude_cli
    MODEL="legacy-model"
    EFFORT="legacy-effort"
    MAX_TURNS="99"
    AGENT_MAKER_MODEL="claude-opus-5"
    AGENT_MAKER_EFFORT="low"
    AGENT_MAKER_MAX_TURNS="3"
    OUTPUT_FILE="${BATS_TEST_TMPDIR}/agent-out.txt"
    run run_loop_agent_once
    [ "$status" -eq 0 ]
    [ -f "${OUTPUT_FILE}" ]
    [ "$(cat "${CLAUDE_ARGS_FILE}")" = "${CLAUDE_BASE_ARGS} --effort low --max-turns 3 --model claude-opus-5" ]
}

@test "run_loop_agent_once clears legacy role values when AGENT_MAKER_* are empty" {
    _stub_claude_cli
    MODEL="legacy-model"
    EFFORT="legacy-effort"
    MAX_TURNS="99"
    unset AGENT_MAKER_MODEL AGENT_MAKER_EFFORT AGENT_MAKER_MAX_TURNS
    OUTPUT_FILE=""
    run run_loop_agent_once
    [ "$status" -eq 0 ]
    [ "$(cat "${CLAUDE_ARGS_FILE}")" = "${CLAUDE_BASE_ARGS}" ]
}

# _stub_claude_writing_message: claude stub that records args and writes message files
#
# Arguments:
#   $1 - message.md content (printf format)
#   $2 - message_labels.json content (empty = no file)
_stub_claude_writing_message() {
    _stub_claude_cli
    printf '%s' "$1" > "${BATS_TEST_TMPDIR}/stub-message.md"
    printf '%s' "${2:-}" > "${BATS_TEST_TMPDIR}/stub-labels.json"
    cat > "${BATS_TEST_TMPDIR}/bin-claude/claude" << STUB
#!/bin/bash
printf '%s\n' "\$*" > "${CLAUDE_ARGS_FILE}"
cp "${BATS_TEST_TMPDIR}/stub-message.md" "\${LOOP_MESSAGE_DIR}/message.md"
[[ -s "${BATS_TEST_TMPDIR}/stub-labels.json" ]] && cp "${BATS_TEST_TMPDIR}/stub-labels.json" "\${LOOP_MESSAGE_DIR}/message_labels.json"
exit 0
STUB
    export LOOP_MESSAGE_DIR="${BATS_TEST_TMPDIR}/loop-message"
    OUTPUT_FILE=""
}

@test "run_loop_agent_once appends the message directory to the prompt and creates it" {
    _stub_claude_cli
    LOOP_MESSAGE_DIR="${BATS_TEST_TMPDIR}/loop-message"
    OUTPUT_FILE=""
    run run_loop_agent_once
    [ "$status" -eq 0 ]
    [ -d "${LOOP_MESSAGE_DIR}" ]
    grep -qF -- "Loop message directory: ${LOOP_MESSAGE_DIR} --output-format" "${CLAUDE_ARGS_FILE}"
    grep -qxF -- "-p hello" "${CLAUDE_ARGS_FILE}"
}

@test "run_loop_agent_once emits an empty message_json when message.md is missing or labels are malformed" {
    _stub_claude_cli
    LOOP_MESSAGE_DIR="${BATS_TEST_TMPDIR}/loop-message"
    OUTPUT_FILE=""
    run run_loop_agent_once
    [ "$status" -eq 0 ]
    grep -q '^message_json=$' "${GITHUB_OUTPUT}"

    : > "${GITHUB_OUTPUT}"
    _stub_claude_writing_message $'body\n' '{"add": "not-an-array"}'
    run run_loop_agent_once
    [ "$status" -eq 0 ]
    grep -q '^message_json=$' "${GITHUB_OUTPUT}"
}

@test "run_loop_agent_once emits message_json from message.md and message_labels.json" {
    local delim value
    _stub_claude_writing_message $'Triage: docs.\n' '{"add":["documentation"]}'
    run run_loop_agent_once
    [ "$status" -eq 0 ]
    delim="$(sed -n 's/^message_json<<//p' "${GITHUB_OUTPUT}")"
    [[ ${delim} == MESSAGE_JSON_* ]]
    value="$(awk -v d="${delim}" '$0==d{f=0} f{print} $0=="message_json<<" d{f=1}' "${GITHUB_OUTPUT}")"
    [ "$(jq -r '.body' <<< "${value}")" = "Triage: docs." ]
    [ "$(jq -c '.labels' <<< "${value}")" = '{"add":["documentation"]}' ]
}

@test "run_loop_agent_once keeps a multi-line body intact through GITHUB_OUTPUT" {
    local delim value body
    body=$'line one\n\n```\ncode "quoted" \\ back\n```\nMESSAGE_JSON_ not a delimiter\n'
    _stub_claude_writing_message "${body}" ''
    run run_loop_agent_once
    [ "$status" -eq 0 ]
    delim="$(sed -n 's/^message_json<<//p' "${GITHUB_OUTPUT}")"
    # JSON encoding keeps the value on one line, so exactly one delimiter pair exists
    [ "$(grep -c "^${delim}$" "${GITHUB_OUTPUT}")" -eq 1 ]
    value="$(awk -v d="${delim}" '$0==d{f=0} f{print} $0=="message_json<<" d{f=1}' "${GITHUB_OUTPUT}")"
    [ "$(jq -j '.body' <<< "${value}"; echo x)" = "${body}x" ]
}

@test "run_loop_agent_once never calls gh" {
    local bindir="${BATS_TEST_TMPDIR}/bin-gh"
    mkdir -p "${bindir}"
    printf '#!/bin/bash\necho called >> "%s/gh.log"\n' "${BATS_TEST_TMPDIR}" > "${bindir}/gh"
    chmod +x "${bindir}/gh"
    _stub_claude_writing_message $'text\n' ''
    PATH="${bindir}:${PATH}"
    AGENT_ENGINE=claude
    run run_loop_agent_once
    [ "$status" -eq 0 ]
    [ ! -e "${BATS_TEST_TMPDIR}/gh.log" ]
}
