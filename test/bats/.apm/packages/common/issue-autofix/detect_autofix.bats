#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

DETECT_SCRIPT="$(apm_skill_script_path issue-autofix detect_autofix.sh)"

@test "detect_autofix skips when ISSUE_NUMBER empty" {
    run env -u ISSUE_NUMBER -u GITHUB_EVENT_PATH bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '.skip == true and .status == "ok"' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_autofix skips when open PR already Fixes same issue" {
    MOCK_BIN="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${MOCK_BIN}"
    cat > "${MOCK_BIN}/gh" << 'EOF'
#!/bin/bash
if [[ "$1" == "pr" && "$2" == "list" ]]; then
    printf '%s\n' '[{"number":7,"title":"fix crash","body":"Fixes #12","isDraft":true}]'
    exit 0
fi
printf 'unexpected gh: %s\n' "$*" >&2
exit 1
EOF
    chmod +x "${MOCK_BIN}/gh"
    PATH="${MOCK_BIN}:${PATH}"
    export PATH ISSUE_NUMBER=12 GITHUB_REPOSITORY=owner/repo GH_TOKEN=unit-test-token
    run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '.skip == true and .status == "ok"' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_autofix errors when PR scan prerequisites are missing" {
    run env -u GITHUB_REPOSITORY -u GH_TOKEN -u GITHUB_TOKEN ISSUE_NUMBER=12 bash "${DETECT_SCRIPT}"
    [ "$status" -eq 1 ]
    run jq -e '.status == "error" and .skip == true' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_autofix errors when gh pr list fails" {
    MOCK_BIN="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${MOCK_BIN}"
    cat > "${MOCK_BIN}/gh" << 'EOF'
#!/bin/bash
if [[ "$1" == "pr" && "$2" == "list" ]]; then
    exit 1
fi
printf 'unexpected gh: %s\n' "$*" >&2
exit 1
EOF
    chmod +x "${MOCK_BIN}/gh"
    PATH="${MOCK_BIN}:${PATH}"
    export PATH ISSUE_NUMBER=12 GITHUB_REPOSITORY=owner/repo GH_TOKEN=unit-test-token
    run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 1 ]
    run jq -e '.status == "error" and .skip == true' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_autofix errors when ISSUE_NUMBER is not numeric" {
    run env ISSUE_NUMBER='12abc' GITHUB_REPOSITORY=owner/repo GH_TOKEN=unit-test-token bash "${DETECT_SCRIPT}"
    [ "$status" -eq 1 ]
    run jq -e '.status == "error" and .skip == true' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_autofix proceeds when no matching Fixes PR" {
    MOCK_BIN="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${MOCK_BIN}"
    cat > "${MOCK_BIN}/gh" << 'EOF'
#!/bin/bash
if [[ "$1" == "pr" && "$2" == "list" ]]; then
    printf '%s\n' '[]'
    exit 0
fi
printf 'unexpected gh: %s\n' "$*" >&2
exit 1
EOF
    chmod +x "${MOCK_BIN}/gh"
    PATH="${MOCK_BIN}:${PATH}"
    export PATH ISSUE_NUMBER=12 GITHUB_REPOSITORY=owner/repo GH_TOKEN=unit-test-token
    run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '.skip == false and .status == "ok" and .result.issue_number == "12"' <<< "${output}"
    [ "$status" -eq 0 ]
}
