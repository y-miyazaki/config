#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

bats_require_minimum_version 1.5.0

# Tests for .github/actions/loop-entity-detect/lib/detect.sh (detect hook invocation)
#
# Use cases:
# - detect.sh runs DETECT_HOOK_SCRIPT when result.dispatch_requested is true, also when skip is true
# - detect.sh does not run the hook when dispatch_requested is absent or only the removed DISPATCH_HOOK_SCRIPT is set
# - the hook always receives the detect token (GITHUB_TOKEN); DISPATCH_HOOK_TOKEN is ignored
# - detect.sh fails when the hook exits non-zero or lives outside GITHUB_WORKSPACE

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

# write_detect_stub writes a detect script that prints the given JSON.
write_detect_stub() {
    printf '%s\n' "$1" > "${BATS_TEST_TMPDIR}/detect_payload.json"
    printf '#!/bin/bash\ncat "%s"\n' "${BATS_TEST_TMPDIR}/detect_payload.json" > "${DETECT_SCRIPT}"
    chmod +x "${DETECT_SCRIPT}"
}

# write_marker_hook writes a hook that records the token it received.
write_marker_hook() {
    cat > "${HOOK_SCRIPT}" << EOF
#!/bin/bash
printf '%s\n' "\${GITHUB_TOKEN:-}" > "${HOOK_MARKER}"
exit 0
EOF
    chmod +x "${HOOK_SCRIPT}"
}

setup() {
    DETECT_SH="$(bats_workspace_root)/.github/actions/loop-entity-detect/lib/detect.sh"
    export GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/github_output"
    export RUNNER_TEMP="${BATS_TEST_TMPDIR}/runner-temp"
    GITHUB_WORKSPACE="$(bats_workspace_root)"
    export GITHUB_WORKSPACE
    mkdir -p "${RUNNER_TEMP}"
    : > "${GITHUB_OUTPUT}"

    export LOOP_NAME="github-issue-triage"
    export AGENT_MAKER_SKILL_NAME="issue-triage"
    export LEVEL="L1"
    export DELIVERY="none"
    export AGENT_MAKER_INSTRUCTIONS=""
    export GITHUB_TOKEN="detect-token"
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
    export DETECT_HOOK_SCRIPT="${HOOK_SCRIPT}"
}

teardown() {
    rm -rf "${HOOK_DIR}"
}

@test "detect.sh fails when hook exits non-zero" {
    write_detect_stub '{"status":"ok","skip":false,"result":{"handoff_key":"entity:issue:1","entity":{"kind":"issue"},"dispatch_requested":true}}'
    printf '#!/bin/bash\nexit 1\n' > "${HOOK_SCRIPT}"
    chmod +x "${HOOK_SCRIPT}"

    run bash "${DETECT_SH}"
    [ "$status" -eq 1 ]
    run grep -c '^should_run=' "${GITHUB_OUTPUT}"
    [ "$output" = "0" ]
}

@test "detect.sh ignores the removed DISPATCH_HOOK_SCRIPT variable" {
    write_detect_stub '{"status":"ok","skip":false,"result":{"handoff_key":"entity:issue:1","entity":{"kind":"issue"},"dispatch_requested":true}}'
    write_marker_hook

    run env -u DETECT_HOOK_SCRIPT DISPATCH_HOOK_SCRIPT="${HOOK_SCRIPT}" bash "${DETECT_SH}"
    [ "$status" -eq 0 ]
    [ ! -f "${HOOK_MARKER}" ]
}

@test "detect.sh invokes hook when dispatch_requested is true" {
    write_detect_stub '{"status":"ok","skip":false,"result":{"handoff_key":"entity:issue:1","entity":{"kind":"issue"},"dispatch_requested":true,"dispatch_event_type":"loop-github-issue-autofix","dispatch_client_payload":{"issue_number":"1"}}}'
    write_marker_hook

    run bash "${DETECT_SH}"
    [ "$status" -eq 0 ]
    [ -f "${HOOK_MARKER}" ]
    run grep -Fx 'should_run=true' "${GITHUB_OUTPUT}"
    [ "$status" -eq 0 ]
}

@test "detect.sh invokes hook when skip is true without entity kind" {
    write_detect_stub '{"status":"ok","skip":true,"result":{"handoff_key":"entity:issue:1","dispatch_requested":true}}'
    write_marker_hook

    run bash "${DETECT_SH}"
    [ "$status" -eq 0 ]
    [ -f "${HOOK_MARKER}" ]
    run grep -Fx 'should_run=false' "${GITHUB_OUTPUT}"
    [ "$status" -eq 0 ]
    run grep -Fx 'skip_reason=detect_skip' "${GITHUB_OUTPUT}"
    [ "$status" -eq 0 ]
}

@test "detect.sh passes the detect token to the hook" {
    write_detect_stub '{"status":"ok","skip":false,"result":{"handoff_key":"entity:issue:1","entity":{"kind":"issue"},"dispatch_requested":true}}'
    write_marker_hook

    run env DISPATCH_HOOK_TOKEN="other-token" bash "${DETECT_SH}"
    [ "$status" -eq 0 ]
    run cat "${HOOK_MARKER}"
    [ "$output" = "detect-token" ]
}

@test "detect.sh rejects dispatch hook outside GITHUB_WORKSPACE" {
    write_detect_stub '{"status":"ok","skip":false,"result":{"handoff_key":"entity:issue:1","entity":{"kind":"issue"},"dispatch_requested":true}}'
    OUTSIDE_HOOK="${BATS_TEST_TMPDIR}/outside/scripts/hooks/on_detect_dispatch.sh"
    mkdir -p "$(dirname "${OUTSIDE_HOOK}")"
    printf '#!/bin/bash\nexit 0\n' > "${OUTSIDE_HOOK}"
    chmod +x "${OUTSIDE_HOOK}"
    export DETECT_HOOK_SCRIPT="${OUTSIDE_HOOK}"

    run --separate-stderr bash "${DETECT_SH}"
    [ "$status" -eq 1 ]
    [ "$stderr" = "::error::DETECT_HOOK_SCRIPT must be under GITHUB_WORKSPACE: $(realpath "${OUTSIDE_HOOK}")" ]
}

@test "detect.sh skips hook when dispatch_requested absent" {
    write_detect_stub '{"status":"ok","skip":false,"result":{"handoff_key":"entity:issue:1","entity":{"kind":"issue"}}}'
    write_marker_hook

    run bash "${DETECT_SH}"
    [ "$status" -eq 0 ]
    [ ! -f "${HOOK_MARKER}" ]
}
