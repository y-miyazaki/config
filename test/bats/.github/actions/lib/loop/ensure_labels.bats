#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

bats_require_minimum_version 1.5.0

# Tests for .github/actions/lib/loop/ensure_labels.sh
#
# Use cases:
# - ensure_repo_labels creates each label once, in order, without --force
# - ensure_repo_labels treats an already existing label as success
# - ensure_repo_labels stops at the first other failure and reports the label and gh error
# - ensure_repo_labels skips empty names and does nothing without arguments

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

@test "ensure_repo_labels creates each label once in order without --force" {
    run ensure_repo_labels "loop:code-review" "extra label"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "${BATS_TEST_TMPDIR}/gh.log")" -eq 2 ]
    [ "$(sed -n 1p "${BATS_TEST_TMPDIR}/gh.log")" = "label create loop:code-review --repo o/r --description Created by a loop workflow" ]
    [[ "$(sed -n 2p "${BATS_TEST_TMPDIR}/gh.log")" == "label create extra label --repo o/r "* ]]
    run ! grep -q -- '--force' "${BATS_TEST_TMPDIR}/gh.log"
}

@test "ensure_repo_labels skips empty names and does nothing without arguments" {
    run ensure_repo_labels
    [ "$status" -eq 0 ]
    run ensure_repo_labels "" ""
    [ "$status" -eq 0 ]
    [ ! -f "${BATS_TEST_TMPDIR}/gh.log" ]
}

@test "ensure_repo_labels stops at the first other failure and reports the label and gh error" {
    export GH_MOCK_RC="0 1 0"
    export GH_MOCK_ERR="HTTP 403: Resource not accessible by integration"
    run --separate-stderr ensure_repo_labels "a" "b" "c"
    [ "$status" -eq 1 ]
    [ "$stderr" = "Failed to create label b: HTTP 403: Resource not accessible by integration" ]
    [ "$(wc -l < "${BATS_TEST_TMPDIR}/gh.log")" -eq 2 ]
}

@test "ensure_repo_labels treats an already existing label as success" {
    export GH_MOCK_RC="1 0"
    export GH_MOCK_ERR='label already exists'
    run ensure_repo_labels "a" "b"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "${BATS_TEST_TMPDIR}/gh.log")" -eq 2 ]
}
