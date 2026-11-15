#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .apm/packages/common-hooks-*/.apm/hooks/scripts/gitleaks_prompt.sh
#
# Use cases:
# - Claude Code (UserPromptSubmit) blocks a prompt with a secret via exit 2 and stderr
# - Cursor (beforeSubmitPrompt) blocks via {"continue": false, "user_message": ...} and exit 0
# - Copilot (userPromptSubmitted) only warns: exit 2 with a rotate-the-secret notice
# - the matched secret value is never echoed, only rule id and line number
# - a clean or empty prompt passes silently
# - missing gitleaks, gitleaks failure, and missing jq all fail open
# - every hook script is byte-identical across the claude, copilot, and cursor packages of each family
# - each agent package ships a hook definition for its prompt event

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    ROOT="$(bats_workspace_root)"
    HOOK="${ROOT}/.apm/packages/common-hooks-claude/.apm/hooks/scripts/gitleaks_prompt.sh"
    # Placeholder AWS access key id assembled at runtime so no literal secret is committed
    SECRET="AKIA$(printf 'QYLPMN5HHHFPZAM2')"
    WORK="${BATS_TEST_TMPDIR}/work"
    mkdir -p "${WORK}"
}

run_hook() {
    local json="$1"
    run bash -c "cd '${WORK}' && bash '${HOOK}' <<< '${json}'"
}

@test "hook scripts are identical across agent packages of each family" {
    local fam f name t
    for fam in common go shell-script terraform; do
        for f in "${ROOT}/.apm/packages/${fam}-hooks-claude/.apm/hooks/scripts/"*.sh; do
            name="$(basename "${f}")"
            for t in copilot cursor; do
                cmp "${f}" "${ROOT}/.apm/packages/${fam}-hooks-${t}/.apm/hooks/scripts/${name}"
            done
        done
    done
}

@test "each agent package ships a prompt hook definition" {
    jq -e '.hooks.UserPromptSubmit[0].hooks[0].command == "./scripts/gitleaks_prompt.sh"' \
        "${ROOT}/.apm/packages/common-hooks-claude/.apm/hooks/gitleaks-prompt.json"
    jq -e '.version == 1 and .hooks.beforeSubmitPrompt[0].command == "./scripts/gitleaks_prompt.sh"' \
        "${ROOT}/.apm/packages/common-hooks-cursor/.apm/hooks/gitleaks-prompt.json"
    jq -e '.version == 1 and .hooks.userPromptSubmitted[0].bash == "./scripts/gitleaks_prompt.sh"' \
        "${ROOT}/.apm/packages/common-hooks-copilot/.apm/hooks/gitleaks-prompt.json"
}

@test "claude blocks a prompt containing a secret with exit 2" {
    run_hook "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"s\",\"prompt\":\"key ${SECRET}\"}"
    [ "$status" -eq 2 ]
    [[ ${output} == *"aws-access-token (line 1)"* ]]
}

@test "clean prompt passes silently" {
    run_hook '{"hook_event_name":"UserPromptSubmit","prompt":"hello world"}'
    [ "$status" -eq 0 ]
    [ -z "${output}" ]
}

@test "copilot only warns and tells the user to rotate the secret" {
    run_hook "{\"sessionId\":\"s\",\"prompt\":\"key ${SECRET}\"}"
    [ "$status" -eq 2 ]
    [[ ${output} == *"cannot block"* ]]
}

@test "cursor blocks via continue false JSON with exit 0" {
    run_hook "{\"hook_event_name\":\"beforeSubmitPrompt\",\"cursor_version\":\"1\",\"prompt\":\"key ${SECRET}\"}"
    [ "$status" -eq 0 ]
    [ "$(jq -r .continue <<< "${output}")" = "false" ]
    [[ $(jq -r .user_message <<< "${output}") == *"aws-access-token"* ]]
}

@test "empty prompt passes silently" {
    run_hook '{"hook_event_name":"UserPromptSubmit","prompt":""}'
    [ "$status" -eq 0 ]
    [ -z "${output}" ]
}

@test "gitleaks failure fails open" {
    mkdir -p "${BATS_TEST_TMPDIR}/bin"
    printf '#!/bin/bash\nexit 1\n' > "${BATS_TEST_TMPDIR}/bin/gitleaks"
    chmod +x "${BATS_TEST_TMPDIR}/bin/gitleaks"
    run bash -c "cd '${WORK}' && PATH='${BATS_TEST_TMPDIR}/bin':\"\$PATH\" bash '${HOOK}' <<< '{\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"key ${SECRET}\"}'"
    [ "$status" -eq 0 ]
}

@test "missing gitleaks fails open" {
    mkdir -p "${BATS_TEST_TMPDIR}/nogl"
    ln -s "$(command -v jq)" "${BATS_TEST_TMPDIR}/nogl/jq"
    run bash -c "cd '${WORK}' && PATH='${BATS_TEST_TMPDIR}/nogl' '$(command -v bash)' '${HOOK}' <<< '{\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"key ${SECRET}\"}'"
    [ "$status" -eq 0 ]
}

@test "secret value is never echoed" {
    run_hook "{\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"key ${SECRET}\"}"
    [[ ${output} != *"${SECRET}"* ]]
}
