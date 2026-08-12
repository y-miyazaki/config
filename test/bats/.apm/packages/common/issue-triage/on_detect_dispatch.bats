#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

HOOK_SCRIPT="$(apm_skill_script_path issue-triage hooks/on_detect_dispatch.sh)"

@test "on_detect_dispatch no-ops when dispatch_requested absent" {
    printf '%s' '{"status":"ok","skip":false,"result":{}}' > "${BATS_TEST_TMPDIR}/d.json"
    run bash "${HOOK_SCRIPT}" "${BATS_TEST_TMPDIR}/d.json"
    [ "$status" -eq 0 ]
}

@test "on_detect_dispatch dry-run logs event type when dispatch_requested true" {
    printf '%s' '{"status":"ok","skip":false,"result":{"dispatch_requested":true,"dispatch_event_type":"loop-issue-autofix","dispatch_client_payload":{"issue_number":"12"}}}' \
        > "${BATS_TEST_TMPDIR}/d.json"
    run env DISPATCH_DRY_RUN=1 bash "${HOOK_SCRIPT}" "${BATS_TEST_TMPDIR}/d.json"
    [ "$status" -eq 0 ]
    [[ ${output} == *"loop-issue-autofix"* ]] || [[ ${stderr} == *"loop-issue-autofix"* ]]
}

@test "on_detect_dispatch rejects disallowed event_type" {
    printf '%s' '{"status":"ok","skip":false,"result":{"dispatch_requested":true,"dispatch_event_type":"evil-event"}}' \
        > "${BATS_TEST_TMPDIR}/d.json"
    run bash "${HOOK_SCRIPT}" "${BATS_TEST_TMPDIR}/d.json"
    [ "$status" -ne 0 ]
}

@test "on_detect_dispatch live path calls gh api dispatches" {
    MOCK_BIN="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${MOCK_BIN}"
    cat > "${MOCK_BIN}/gh" << 'GHEOF'
#!/bin/bash
printf '%s\n' "$*" > "${GH_ARGV_FILE}"
if [[ "$*" == *"/dispatches"* ]]; then
    exit 0
fi
printf 'unexpected gh: %s\n' "$*" >&2
exit 1
GHEOF
    chmod +x "${MOCK_BIN}/gh"
    printf '%s' '{"status":"ok","skip":false,"result":{"dispatch_requested":true,"dispatch_event_type":"loop-issue-autofix","dispatch_client_payload":{"issue_number":"12"}}}' \
        > "${BATS_TEST_TMPDIR}/d.json"
    export PATH="${MOCK_BIN}:${PATH}"
    export GH_ARGV_FILE="${BATS_TEST_TMPDIR}/gh-argv"
    export GITHUB_REPOSITORY="owner/repo"
    export GITHUB_TOKEN="unit-test-token"
    unset DISPATCH_DRY_RUN || true
    run bash "${HOOK_SCRIPT}" "${BATS_TEST_TMPDIR}/d.json"
    [ "$status" -eq 0 ]
    grep -q 'dispatches' "${GH_ARGV_FILE}"
}

@test "on_detect_dispatch rejects invalid dispatch_client_payload" {
    printf '%s' '{"status":"ok","skip":false,"result":{"dispatch_requested":true,"dispatch_event_type":"loop-issue-autofix","dispatch_client_payload":{"issue_number":"0","extra":"x"}}}' > "${BATS_TEST_TMPDIR}/d.json"
    run bash "${HOOK_SCRIPT}" "${BATS_TEST_TMPDIR}/d.json"
    [ "$status" -ne 0 ]
}
