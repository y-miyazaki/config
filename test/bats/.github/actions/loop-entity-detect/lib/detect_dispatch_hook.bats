#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for dispatch hook invocation in loop-entity-detect/lib/detect.sh

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    DETECT_SH="$(bats_workspace_root)/.github/actions/loop-entity-detect/lib/detect.sh"
    export GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/github_output"
    export RUNNER_TEMP="${BATS_TEST_TMPDIR}/runner-temp"
    GITHUB_WORKSPACE="$(bats_workspace_root)"
    export GITHUB_WORKSPACE
    mkdir -p "${RUNNER_TEMP}"
    : > "${GITHUB_OUTPUT}"

    export LOOP_NAME="issue-triage"
    export SKILL_NAME="issue-triage"
    export LEVEL="L1"
    export DELIVERY="none"
    export PROMPT_INSTRUCTIONS=""
    export BUDGET_FILE="${BATS_TEST_TMPDIR}/budget.json"
    export RUN_LOG_FILE="${BATS_TEST_TMPDIR}/run-log.md"
    printf '%s\n' '{}' > "${BUDGET_FILE}"
    : > "${RUN_LOG_FILE}"

    DETECT_SCRIPT="${BATS_TEST_TMPDIR}/detect_stub.sh"
    export DETECT_SCRIPT
    HOOK_DIR="${GITHUB_WORKSPACE}/tmp/bats-dispatch-hook-${BATS_TEST_TMPDIR##*/}"
    mkdir -p "${HOOK_DIR}/scripts/hooks"
    HOOK_SCRIPT="${HOOK_DIR}/scripts/hooks/on_detect_dispatch.sh"
    HOOK_MARKER="${BATS_TEST_TMPDIR}/hook-invoked"
    export DISPATCH_HOOK_SCRIPT="${HOOK_SCRIPT}"
}

@test "detect.sh invokes hook when dispatch_requested is true" {
    cat > "${DETECT_SCRIPT}" << 'EOF'
#!/bin/bash
printf '%s\n' '{"status":"ok","skip":false,"result":{"handoff_key":"entity:issue:1","dispatch_requested":true,"dispatch_event_type":"loop-issue-autofix","dispatch_client_payload":{"issue_number":"1"}}}'
EOF
    chmod +x "${DETECT_SCRIPT}"

    cat > "${HOOK_SCRIPT}" << EOF
#!/bin/bash
printf 'invoked\n' > "${HOOK_MARKER}"
exit 0
EOF
    chmod +x "${HOOK_SCRIPT}"

    run bash "${DETECT_SH}"
    [ "$status" -eq 0 ]
    [ -f "${HOOK_MARKER}" ]
}

@test "detect.sh skips hook when dispatch_requested absent" {
    cat > "${DETECT_SCRIPT}" << 'EOF'
#!/bin/bash
printf '%s\n' '{"status":"ok","skip":false,"result":{"handoff_key":"entity:issue:1"}}'
EOF
    chmod +x "${DETECT_SCRIPT}"

    cat > "${HOOK_SCRIPT}" << EOF
#!/bin/bash
printf 'invoked\n' > "${HOOK_MARKER}"
exit 0
EOF
    chmod +x "${HOOK_SCRIPT}"

    run bash "${DETECT_SH}"
    [ "$status" -eq 0 ]
    [ ! -f "${HOOK_MARKER}" ]
}

@test "detect.sh fails when hook exits non-zero" {
    cat > "${DETECT_SCRIPT}" << 'EOF'
#!/bin/bash
printf '%s\n' '{"status":"ok","skip":false,"result":{"handoff_key":"entity:issue:1","dispatch_requested":true}}'
EOF
    chmod +x "${DETECT_SCRIPT}"

    cat > "${HOOK_SCRIPT}" << 'EOF'
#!/bin/bash
exit 1
EOF
    chmod +x "${HOOK_SCRIPT}"

    run bash "${DETECT_SH}"
    [ "$status" -ne 0 ]
}

@test "detect.sh rejects dispatch hook outside GITHUB_WORKSPACE" {
    cat > "${DETECT_SCRIPT}" << 'EOF'
#!/bin/bash
printf '%s
' '{"status":"ok","skip":false,"result":{"handoff_key":"entity:issue:1","dispatch_requested":true,"dispatch_event_type":"loop-issue-autofix","dispatch_client_payload":{"issue_number":"1"}}}'
EOF
    chmod +x "${DETECT_SCRIPT}"

    OUTSIDE_HOOK="${BATS_TEST_TMPDIR}/outside/scripts/hooks/on_detect_dispatch.sh"
    mkdir -p "$(dirname "${OUTSIDE_HOOK}")"
    cat > "${OUTSIDE_HOOK}" << 'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "${OUTSIDE_HOOK}"
    export DISPATCH_HOOK_SCRIPT="${OUTSIDE_HOOK}"

    run bash "${DETECT_SH}"
    [ "$status" -ne 0 ]
}
