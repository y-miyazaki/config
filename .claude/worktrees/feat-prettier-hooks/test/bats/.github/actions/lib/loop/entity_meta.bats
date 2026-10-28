#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/lib/loop/entity_meta.sh
#
# Use cases:
# - entity_issue_number extracts the number from an entity issue key
# - entity_issue_number returns empty for non-issue keys
# - append_entity_meta no-ops for a non-numeric issue number
# - append_entity_meta reports when no marker comment exists

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/lib/loop/created_by.sh"
    bats_source_rel ".github/actions/lib/loop/loop_meta.sh"
    bats_source_rel ".github/actions/lib/loop/entity_meta.sh"
    REPOSITORY="o/r"
}

usage_fixture() {
    printf '%s' '{"total_input_tokens":58,"total_output_tokens":15000,"models":["claude-opus-5","claude-sonnet-5"],"sessions":[{"role":"maker","model":"claude-sonnet-5","input":40,"output":12000},{"role":"checker","model":"claude-opus-5","input":18,"output":3000}]}'
}

@test "append_entity_meta no-ops for a non-numeric issue number" {
    run append_entity_meta "not-a-number" "<!-- m -->" "no-changes" "claude" "$(usage_fixture)" "https://x/run/1"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "append_entity_meta reports when no marker comment exists" {
    local mock_bin
    mock_bin="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${mock_bin}"
    cat > "${mock_bin}/gh" << 'EOF'
#!/bin/bash
printf '%s\n' '[]'
exit 0
EOF
    chmod +x "${mock_bin}/gh"
    PATH="${mock_bin}:${PATH}"
    run append_entity_meta "936" "<!-- github-issue-triage:v1 -->" "no-changes" "claude" "$(usage_fixture)" "https://x/run/1"
    [ "$status" -eq 0 ]
    [[ $output == *"meta not appended"* ]]
}

@test "entity_issue_number extracts the number from an entity issue key" {
    run entity_issue_number "entity:issue:936"
    [ "$status" -eq 0 ]
    [ "$output" = "936" ]
}

@test "entity_issue_number returns empty for non-issue keys" {
    run entity_issue_number "integration:main"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
