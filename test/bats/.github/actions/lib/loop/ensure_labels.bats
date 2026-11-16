#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

bats_require_minimum_version 1.5.0

# Tests for .github/actions/lib/loop/ensure_labels.sh
#
# Use cases:
# - ensure_labels_repo creates each label once, in order, without --force
# - ensure_labels_repo treats an already existing label as success
# - ensure_labels_repo stops at the first other failure and reports the label and gh error
# - ensure_labels_repo skips empty names and does nothing without arguments
# - ensure_labels_parse_list trims names, drops empty entries, and splits on newlines or a given separator

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/lib/loop/ensure_labels.sh"
    export GITHUB_REPOSITORY="o/r"
    export GH_TOKEN="dummy"
    local mock_bin="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${mock_bin}"
    cat > "${mock_bin}/gh" << 'EOF2'
#!/bin/bash
printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/gh.log"
count=$(($(wc -l < "${BATS_TEST_TMPDIR}/gh.log")))
read -r -a rcs <<< "${GH_MOCK_RC:-0}"
rc="${rcs[$((count - 1))]:-0}"
if [[ ${rc} != 0 ]]; then
    printf '%s\n' "${GH_MOCK_ERR:-gh: error}" >&2
fi
exit "${rc}"
EOF2
    chmod +x "${mock_bin}/gh"
    PATH="${mock_bin}:${PATH}"
}

teardown() {
    rm -f "${BATS_TEST_TMPDIR}/gh.log"
}

@test "ensure_labels_parse_list splits on newlines by default, trims names and drops empty entries" {
    run ensure_labels_parse_list $'  loop:code-review \n\n\textra label\t\n   \n'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "loop:code-review" ]
    [ "${lines[1]}" = "extra label" ]
    [ "${#lines[@]}" -eq 2 ]
}

@test "ensure_labels_parse_list splits on the given separator and keeps newlines out of names" {
    run ensure_labels_parse_list "a, b ,, needs review" ","
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "a" ]
    [ "${lines[1]}" = "b" ]
    [ "${lines[2]}" = "needs review" ]
    [ "${#lines[@]}" -eq 3 ]
}

@test "ensure_labels_parse_list prints nothing for an empty or blank list" {
    run ensure_labels_parse_list ""
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    run ensure_labels_parse_list $' \n \n'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "ensure_labels_repo creates each label once in order without --force" {
    run ensure_labels_repo "loop:code-review" "extra label"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "${BATS_TEST_TMPDIR}/gh.log")" -eq 2 ]
    [ "$(sed -n 1p "${BATS_TEST_TMPDIR}/gh.log")" = "label create loop:code-review --repo o/r --description Created by a loop workflow" ]
    [[ "$(sed -n 2p "${BATS_TEST_TMPDIR}/gh.log")" == "label create extra label --repo o/r "* ]]
    run ! grep -q -- '--force' "${BATS_TEST_TMPDIR}/gh.log"
}

@test "ensure_labels_repo skips empty names and does nothing without arguments" {
    run ensure_labels_repo
    [ "$status" -eq 0 ]
    run ensure_labels_repo "" ""
    [ "$status" -eq 0 ]
    [ ! -f "${BATS_TEST_TMPDIR}/gh.log" ]
}

@test "ensure_labels_repo stops at the first other failure and reports the label and gh error" {
    export GH_MOCK_RC="0 1 0"
    export GH_MOCK_ERR="HTTP 403: Resource not accessible by integration"
    run --separate-stderr ensure_labels_repo "a" "b" "c"
    [ "$status" -eq 1 ]
    [ "$stderr" = "Failed to create label b: HTTP 403: Resource not accessible by integration" ]
    [ "$(wc -l < "${BATS_TEST_TMPDIR}/gh.log")" -eq 2 ]
}

@test "ensure_labels_repo treats an already existing label as success" {
    export GH_MOCK_RC="1 0"
    export GH_MOCK_ERR='label already exists'
    run ensure_labels_repo "a" "b"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "${BATS_TEST_TMPDIR}/gh.log")" -eq 2 ]
}
