#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/lib/loop/text.sh
#
# Use cases:
# - text_truncate keeps short text unchanged
# - text_truncate cuts text to the maximum length

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/lib/loop/text.sh"

}

@test "text_truncate cuts text to the maximum length" {
    run text_truncate "abcdefgh" 3
    [ "$status" -eq 0 ]
    [ "$output" = "abc" ]
}

@test "text_truncate keeps short text unchanged" {
    run text_truncate "abc" 10
    [ "$status" -eq 0 ]
    [ "$output" = "abc" ]
}
