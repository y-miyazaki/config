#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .apm/packages/*-hooks-*/.apm/hooks/scripts/*.sh (Stop hooks: blocked-state gate)
#
# Use cases:
# - an unchanged failing state blocks the agent HOOK_BLOCK_LIMIT times (default 2), then is skipped
# - any file change after a block runs the tool again and blocks again
# - HOOK_SESSION_LIMIT bounds the reports per session across changing states
# - stop_hook_active does not stop a hook from reporting a changed state
# - a passing run clears the remembered state so a restored failing state blocks again
# - state is kept per session id, so another session is still told about the failure
# - the session id is read from session_id (Claude, Codex, Kiro, VS Code, Copilot), conversation_id
#   (Cursor), sessionId (Copilot agentStop) or conversationId (Antigravity), falling back to a shared key
# - untracked file content participates in the state hash
# - every Stop hook script in every agent package defines the gate functions
# - report_failure and the event helpers are the same text in every hook script (apm cannot ship a lib)

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    ROOT="$(bats_workspace_root)"
    HOOK="${ROOT}/.apm/packages/common-hooks-claude/.apm/hooks/scripts/gitleaks.sh"
    REPO="${BATS_TEST_TMPDIR}/repo"
    MOCK_BIN="${BATS_TEST_TMPDIR}/bin"
    export TMPDIR="${BATS_TEST_TMPDIR}/state-tmp"
    unset HOOK_BLOCK_LIMIT HOOK_SESSION_LIMIT

    mkdir -p "${REPO}" "${MOCK_BIN}" "${TMPDIR}"
    git -C "${REPO}" init -q
    git -C "${REPO}" config user.email "test@example.com"
    git -C "${REPO}" config user.name "test"
    printf 'one\n' > "${REPO}/a.txt"
    git -C "${REPO}" add a.txt
    git -C "${REPO}" commit -q -m init
    printf 'two\n' > "${REPO}/a.txt"

    cat > "${MOCK_BIN}/gitleaks" << 'EOF'
#!/bin/bash
echo "leak found" >&2
exit "${MOCK_GITLEAKS_RC:-1}"
EOF
    chmod +x "${MOCK_BIN}/gitleaks"
}

run_hook() {
    local rc="${1:-1}"
    local stop_json="{\"hook_event_name\":\"Stop\",\"stop_hook_active\":false,\"session_id\":\"${SESSION:-s1}\"}"
    run bash -c "cd '${REPO}' && PATH='${MOCK_BIN}':\"\$PATH\" MOCK_GITLEAKS_RC=${rc} bash '${HOOK}' <<< '${stop_json}'"
}

@test "HOOK_BLOCK_LIMIT=1 skips from the second identical failure" {
    export HOOK_BLOCK_LIMIT=1
    run_hook 1
    [[ ${output} == *'"decision": "block"'* ]]

    run_hook 1
    [ "$status" -eq 0 ]
    [ -z "${output}" ]
}

@test "stop_hook_active does not stop the hook from reporting" {
    local json='{"hook_event_name":"Stop","stop_hook_active":true,"session_id":"s1"}'
    run bash -c "cd '${REPO}' && PATH='${MOCK_BIN}':\"\$PATH\" bash '${HOOK}' <<< '${json}'"
    [[ ${output} == *'"decision": "block"'* ]]
}

@test "HOOK_SESSION_LIMIT bounds the reports across changing states" {
    export HOOK_SESSION_LIMIT=2
    run_hook 1
    [[ ${output} == *'"decision": "block"'* ]]
    printf 'three\n' > "${REPO}/a.txt"
    run_hook 1
    [[ ${output} == *'"decision": "block"'* ]]
    printf 'four\n' > "${REPO}/a.txt"
    run_hook 1
    [ -z "${output}" ]
}

@test "a changed file after the limit was reached blocks again" {
    run_hook 1
    run_hook 1
    run_hook 1
    [ -z "${output}" ]

    printf 'three\n' > "${REPO}/a.txt"
    run_hook 1
    [[ ${output} == *'"decision": "block"'* ]]
}

@test "a passing run clears the remembered state so a restored failing state blocks again" {
    export HOOK_BLOCK_LIMIT=1
    run_hook 1
    [[ ${output} == *'"decision": "block"'* ]]

    printf 'three\n' > "${REPO}/a.txt"
    run_hook 0
    [ "$status" -eq 0 ]
    [ -z "${output}" ]

    printf 'two\n' > "${REPO}/a.txt"
    run_hook 1
    [[ ${output} == *'"decision": "block"'* ]]
}

@test "all Stop hook scripts define the blocked-state gate functions" {
    local script count=0
    local -a names=(actionlint ghalint gitleaks markdown_link_check markdownlint_cli2 zizmor golangci_lint go_test shellcheck tflint)
    for script in "${ROOT}"/.apm/packages/*-hooks-*/.apm/hooks/scripts/*.sh; do
        [[ " ${names[*]} " == *" $(basename "${script}" .sh) "* ]] || continue
        count=$((count + 1))
        grep -q '^function blocked_state_file' "${script}"
        grep -q '^function is_blocked_state' "${script}"
        grep -q '^function record_blocked_state' "${script}"
        grep -q '^function clear_blocked_state' "${script}"
        grep -q '^function compute_state_hash' "${script}"
        grep -q '    record_blocked_state$' "${script}"
        grep -q '    clear_blocked_state$' "${script}"
    done
    [ "${count}" -eq 30 ]
}

@test "an unchanged failing state blocks twice by default and is then skipped" {
    run_hook 1
    [ "$status" -eq 0 ]
    [[ ${output} == *'"decision": "block"'* ]]
    [[ ${output} == *'leak found'* ]]

    run_hook 1
    [[ ${output} == *'"decision": "block"'* ]]

    run_hook 1
    [ "$status" -eq 0 ]
    [ -z "${output}" ]
}

@test "an invalid HOOK_BLOCK_LIMIT falls back to the default of 2" {
    export HOOK_BLOCK_LIMIT=abc
    run_hook 1
    run_hook 1
    [[ ${output} == *'"decision": "block"'* ]]

    run_hook 1
    [ -z "${output}" ]
}

@test "another session is still told about an already reported failure" {
    SESSION=a run_hook 1
    SESSION=a run_hook 1
    SESSION=a run_hook 1
    [ -z "${output}" ]

    SESSION=b run_hook 1
    [[ ${output} == *'"decision": "block"'* ]]
}

@test "blocked_state_file keys on the session id field of each agent" {
    local payload expected
    while IFS='|' read -r payload expected; do
        run bash -c "source '${HOOK}' < /dev/null; HOOK_STDIN_DATA='${payload}'; blocked_state_file"
        [ "$status" -eq 0 ]
        [[ ${output} == *"/${expected}__gitleaks" ]]
    done << 'EOF'
{"hook_event_name":"Stop","session_id":"claude-1"}|claude-1
{"hook_event_name":"stop","conversation_id":"cursor-1","generation_id":"g1"}|cursor-1
{"sessionId":"copilot-1","stopReason":"end_turn"}|copilot-1
{"executionNum":5,"terminationReason":"task_complete","conversationId":"antigravity-1"}|antigravity-1
{"hook_event_name":"Stop","stop_hook_active":false}|nosession
EOF
}

@test "compute_state_hash is empty-safe outside git and differs for untracked content" {
    run bash -c "cd '${BATS_TEST_TMPDIR}' && source '${HOOK}' < /dev/null && compute_state_hash"
    [ "$status" -eq 0 ]

    printf 'x\n' > "${REPO}/new.txt"
    run bash -c "cd '${REPO}' && source '${HOOK}' < /dev/null && compute_state_hash"
    local before="${output}"
    [ -n "${before}" ]

    printf 'y\n' > "${REPO}/new.txt"
    run bash -c "cd '${REPO}' && source '${HOOK}' < /dev/null && compute_state_hash"
    [ -n "${output}" ]
    [ "${output}" != "${before}" ]
}

@test "report_failure and the event helpers are the same text in every hook script" {
    local fn f body want name
    for fn in report_failure truncate_reason_text collapse_reason_for_cursor_display emit_json_with_reason; do
        want=""
        for f in "${ROOT}"/.apm/packages/*-hooks-*/.apm/hooks/scripts/*.sh; do
            name=$(basename "$f")
            body=$(awk -v s="function ${fn} " 'index($0,s)==1{p=1} p{print} p&&/^}/{exit}' "$f")
            if [ -z "$body" ]; then
                # the prompt hook and terraform_fmt have no event helpers
                [[ $name == gitleaks_prompt.sh || $name == terraform_fmt.sh ]] || {
                    echo "${fn} missing in ${f}"
                    return 1
                }
                continue
            fi
            # the PostToolUse formatters have no blocked-state gate and so no record_blocked_state call
            [[ $name == prettier.sh || $name == shfmt.sh ]] && body=$(printf '%s\n' "$body" | sed '/^    record_blocked_state$/d')
            if [[ $fn == report_failure && $name != prettier.sh && $name != shfmt.sh ]]; then
                printf '%s\n' "$body" | grep -q '^    record_blocked_state$' || {
                    echo "record_blocked_state missing in ${f}"
                    return 1
                }
                body=$(printf '%s\n' "$body" | sed '/^    record_blocked_state$/d')
            fi
            [ -z "$want" ] && want="$body"
            [ "$body" = "$want" ] || {
                echo "${fn} differs in ${f}"
                return 1
            }
        done
        [ -n "$want" ]
    done
}
