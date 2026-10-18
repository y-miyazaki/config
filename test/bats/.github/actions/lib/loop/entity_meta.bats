#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/lib/loop/entity_meta.sh
#
# Use cases:
# - entity_issue_number extracts the number from an entity issue key
# - entity_issue_number returns empty for non-issue keys
# - post_entity_comment posts the agent text, Meta and the footer as one Issue comment
# - post_entity_comment puts the skill marker first and does not duplicate one the text already has
# - post_entity_comment posts nothing when the agent text is empty
# - post_entity_comment no-ops for a non-numeric issue number
# - post_entity_comment warns and returns 0 when gh fails

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
    MARKER="<!-- github-issue-triage:v1 -->"
}

# Install a gh mock: records args to gh.log and the --body-file content to gh.body; exits $1 (default 0)
mock_gh() {
    local mock_bin="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${mock_bin}"
    cat > "${mock_bin}/gh" << EOF2
#!/bin/bash
printf '%s\n' "\$*" >> "\${BATS_TEST_TMPDIR}/gh.log"
while [[ \$# -gt 0 ]]; do
    if [[ \$1 == --body-file ]]; then
        cat "\$2" >> "\${BATS_TEST_TMPDIR}/gh.body"
    fi
    shift
done
exit ${1:-0}
EOF2
    chmod +x "${mock_bin}/gh"
    PATH="${mock_bin}:${PATH}"
}

usage_fixture() {
    printf '%s' '{"total_input_tokens":58,"total_output_tokens":15000,"models":["claude-opus-5","claude-sonnet-5"],"sessions":[{"role":"maker","model":"claude-sonnet-5","input":40,"output":12000},{"role":"checker","model":"claude-opus-5","input":18,"output":3000}]}'
}

@test "entity_issue_number extracts the number from an entity issue key" {
    run entity_issue_number "entity:issue:936"
    [ "$status" -eq 0 ]
    [ "$output" = "936" ]
}

@test "entity_issue_number returns empty for non-issue keys" {
    run entity_issue_number "entity:pr:77"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "post_entity_comment no-ops for a non-numeric issue number" {
    mock_gh
    printf 'text' > "${BATS_TEST_TMPDIR}/body.md"
    run post_entity_comment "x" "${MARKER}" "${BATS_TEST_TMPDIR}/body.md" "unchanged" "claude" "$(usage_fixture)" "https://x/run/1"
    [ "$status" -eq 0 ]
    [ ! -e "${BATS_TEST_TMPDIR}/gh.log" ]
}

@test "post_entity_comment posts nothing when the agent text is empty" {
    mock_gh
    printf '  \n\n' > "${BATS_TEST_TMPDIR}/body.md"
    run post_entity_comment "1014" "${MARKER}" "${BATS_TEST_TMPDIR}/body.md" "unchanged" "claude" "$(usage_fixture)" "https://x/run/1"
    [ "$status" -eq 0 ]
    [[ $output == *"nothing to post"* ]]
    [ ! -e "${BATS_TEST_TMPDIR}/gh.log" ]
}

@test "post_entity_comment posts the agent text, Meta and the footer as one Issue comment" {
    mock_gh
    printf 'Triage: documentation.\n\nNext step: add autofix.\n' > "${BATS_TEST_TMPDIR}/body.md"
    run post_entity_comment "1014" "${MARKER}" "${BATS_TEST_TMPDIR}/body.md" "unchanged" "claude" "$(usage_fixture)" "https://x/run/1"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "${BATS_TEST_TMPDIR}/gh.log")" -eq 1 ]
    [[ "$(cat "${BATS_TEST_TMPDIR}/gh.log")" == "issue comment 1014 --repo o/r --body-file "* ]]
    body="$(cat "${BATS_TEST_TMPDIR}/gh.body")"
    [[ ${body} == "${MARKER}"$'\n'"Triage: documentation."* ]]
    [[ ${body} == *"Next step: add autofix."$'\n\n'"${LOOP_META_MARKER}"* ]]
    [[ ${body} == *"| outcome | unchanged |"* ]]
    [[ ${body} == *"| engine | claude |"* ]]
    [[ ${body} == *"</details>"$'\n\n'"${LOOP_META_FOOTER}" ]]
}

@test "post_entity_comment puts the skill marker first and does not duplicate one the text already has" {
    mock_gh
    printf '%s\nAlready marked.\n' "${MARKER}" > "${BATS_TEST_TMPDIR}/body.md"
    run post_entity_comment "1014" "${MARKER}" "${BATS_TEST_TMPDIR}/body.md" "unchanged" "claude" "" ""
    [ "$status" -eq 0 ]
    body="$(cat "${BATS_TEST_TMPDIR}/gh.body")"
    [[ ${body} == "${MARKER}"$'\n'"Already marked."* ]]
    [ "$(grep -cF -- "${MARKER}" <<< "${body}")" -eq 1 ]
}

@test "post_entity_comment warns and returns 0 when gh fails" {
    mock_gh 1
    printf 'text' > "${BATS_TEST_TMPDIR}/body.md"
    run post_entity_comment "1014" "${MARKER}" "${BATS_TEST_TMPDIR}/body.md" "unchanged" "claude" "" ""
    [ "$status" -eq 0 ]
    [[ $output == *"::warning::"* ]]
}
