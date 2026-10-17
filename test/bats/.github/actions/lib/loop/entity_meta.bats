#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/lib/loop/entity_meta.sh
#
# Use cases:
# - entity_issue_number extracts the number from an entity issue key
# - entity_issue_number returns empty for non-issue keys
# - append_entity_meta no-ops for a non-numeric issue number
# - append_entity_meta reports when no marker comment exists
# - entity_pr_number extracts the number from an entity pr key
# - append_pr_review_meta no-ops for a non-numeric pr number
# - append_pr_review_meta reports when no marker review exists
# - append_pr_review_meta updates the newest marker review once
# - append_pr_review_meta skips a review that already carries meta
# - append_pr_review_meta skips older reviews when the newest marker review carries meta
# - append_pr_review_meta updates the newest review across paginated pages

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

# Install a gh mock: list GET prints $1 (one or more concatenated review arrays), by-id GET prints that review body; PUT records args to put.log and body to put.body
mock_gh_reviews() {
    local mock_bin="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${mock_bin}"
    printf '%s' "$1" > "${BATS_TEST_TMPDIR}/reviews.json"
    cat > "${mock_bin}/gh" << 'EOF'
#!/bin/bash
for a in "$@"; do
    if [[ $a == PUT ]]; then
        printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/put.log"
        for b in "$@"; do
            if [[ $b == body=@* ]]; then
                cat "${b#body=@}" >> "${BATS_TEST_TMPDIR}/put.body"
            fi
        done
        exit 0
    fi
done
for a in "$@"; do
    if [[ $a =~ /reviews/([0-9]+)$ ]]; then
        jq -rs --argjson id "${BASH_REMATCH[1]}" '[.[][]? | select(.id == $id)][0].body // ""' "${BATS_TEST_TMPDIR}/reviews.json"
        exit 0
    fi
done
cat "${BATS_TEST_TMPDIR}/reviews.json"
exit 0
EOF
    chmod +x "${mock_bin}/gh"
    PATH="${mock_bin}:${PATH}"
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

@test "append_pr_review_meta no-ops for a non-numeric pr number" {
    run append_pr_review_meta "x" "<!-- m -->" "pr-created" claude "$(usage_fixture)" "https://x/run/1"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "append_pr_review_meta reports when no marker review exists" {
    mock_gh_reviews '[]'
    run append_pr_review_meta 77 "<!-- github-pr-review:v1 -->" pr-created claude "$(usage_fixture)" "https://x/run/1"
    [ "$status" -eq 0 ]
    [[ $output == *"meta not appended"* ]]
    [ ! -f "${BATS_TEST_TMPDIR}/put.log" ]
}

@test "append_pr_review_meta skips a review that already carries meta" {
    mock_gh_reviews '[{"id":1,"body":"<!-- github-pr-review:v1 -->\nhi\n<!-- loop-meta:v1 -->"}]'
    run append_pr_review_meta 77 "<!-- github-pr-review:v1 -->" pr-created claude "$(usage_fixture)" "https://x/run/1"
    [ "$status" -eq 0 ]
    [ ! -f "${BATS_TEST_TMPDIR}/put.log" ]
}

@test "append_pr_review_meta skips older reviews when the newest marker review carries meta" {
    mock_gh_reviews '[{"id":1,"body":"<!-- github-pr-review:v1 -->\nold"},{"id":2,"body":"<!-- github-pr-review:v1 -->\nnew\n<!-- loop-meta:v1 -->"}]'
    run append_pr_review_meta 77 "<!-- github-pr-review:v1 -->" pr-created claude "$(usage_fixture)" "https://x/run/1"
    [ "$status" -eq 0 ]
    [[ $output == *"already carries loop meta"* ]]
    [ ! -f "${BATS_TEST_TMPDIR}/put.log" ]
}

@test "append_pr_review_meta updates the newest marker review once" {
    mock_gh_reviews '[{"id":1,"body":"<!-- github-pr-review:v1 -->\nold"},{"id":2,"body":"<!-- github-pr-review:v1 -->\nnew"}]'
    run append_pr_review_meta 77 "<!-- github-pr-review:v1 -->" pr-created claude "$(usage_fixture)" "https://x/run/1"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "${BATS_TEST_TMPDIR}/put.log")" -eq 1 ]
    [[ $(cat "${BATS_TEST_TMPDIR}/put.log") == *"repos/o/r/pulls/77/reviews/2"* ]]
    local expected
    loop_meta_reset
    expected="<!-- github-pr-review:v1 -->"$'\n'"new"$'\n\n'"$(build_loop_meta_block pr-created "" "" claude "$(usage_fixture)" "https://x/run/1")"
    [ "$(cat "${BATS_TEST_TMPDIR}/put.body")" = "${expected}" ]
}

@test "append_pr_review_meta updates the newest review across paginated pages" {
    mock_gh_reviews '[{"id":1,"body":"<!-- github-pr-review:v1 -->\nold"},{"id":2,"body":"other"}][{"id":3,"body":"<!-- github-pr-review:v1 -->\nmid"},{"id":4,"body":"<!-- github-pr-review:v1 -->\nlast"}]'
    run append_pr_review_meta 77 "<!-- github-pr-review:v1 -->" pr-created claude "$(usage_fixture)" "https://x/run/1"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "${BATS_TEST_TMPDIR}/put.log")" -eq 1 ]
    [[ $(cat "${BATS_TEST_TMPDIR}/put.log") == *"repos/o/r/pulls/77/reviews/4 "* ]]
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

@test "entity_pr_number extracts the number from an entity pr key" {
    run entity_pr_number "entity:pr:77"
    [ "$status" -eq 0 ]
    [ "$output" = "77" ]
    run entity_pr_number "entity:issue:77"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
