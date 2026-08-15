#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/lib/loop/created_by.sh
#
# Use cases:
# - format_compact_tokens formats small, K, and M scales
# - render_created_by_line omits output when all fields empty
# - render_created_by_line includes engine model and In/Out
# - render_created_by_line omits In/Out when usage absent
# - render_created_by_line uses model and tokens from usage_json alone
# - render_created_by_line keeps engine only when usage_json is invalid
# - render_created_by_line uses em dash for missing In or Out side
# - render_created_by_line emits In/Out without model when engine empty

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/lib/loop/created_by.sh"
}

@test "format_compact_tokens formats small K and M scales" {
    run format_compact_tokens 17
    [ "$status" -eq 0 ]
    [ "$output" = "17" ]
    run format_compact_tokens 100000
    [ "$status" -eq 0 ]
    [ "$output" = "100K" ]
    run format_compact_tokens 1200000
    [ "$status" -eq 0 ]
    [ "$output" = "1.2M" ]
}

@test "render_created_by_line emits In/Out without model when engine empty" {
    run render_created_by_line '' '{"total_input_tokens":100000,"total_output_tokens":100000}'
    [ "$status" -eq 0 ]
    [ "$output" = "Created By In/Out: 100K/100K" ]
}

@test "render_created_by_line includes engine model and In/Out" {
    run render_created_by_line cursor '{"total_input_tokens":100000,"total_output_tokens":100000,"model":"Composer-2.5"}'
    [ "$status" -eq 0 ]
    [ "$output" = "Created By cursor Composer-2.5 In/Out: 100K/100K" ]
}

@test "render_created_by_line keeps engine only when usage_json is invalid" {
    run render_created_by_line cursor 'not-json'
    [ "$status" -eq 0 ]
    [ "$output" = "Created By cursor" ]
}

@test "render_created_by_line omits In/Out when usage absent" {
    run render_created_by_line cursor ''
    [ "$status" -eq 0 ]
    [ "$output" = "Created By cursor" ]
}

@test "render_created_by_line omits output when all fields empty" {
    run render_created_by_line '' ''
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "render_created_by_line uses em dash for missing In or Out side" {
    run render_created_by_line cursor '{"total_input_tokens":100}'
    [ "$status" -eq 0 ]
    [ "$output" = "Created By cursor In/Out: 100/—" ]
    run render_created_by_line cursor '{"total_output_tokens":100}'
    [ "$status" -eq 0 ]
    [ "$output" = "Created By cursor In/Out: —/100" ]
}

@test "render_created_by_line uses model and tokens from usage_json alone" {
    run render_created_by_line '' '{"total_input_tokens":1842,"total_output_tokens":17,"model":"composer-2.5"}'
    [ "$status" -eq 0 ]
    [ "$output" = "Created By composer-2.5 In/Out: 2K/17" ]
}
