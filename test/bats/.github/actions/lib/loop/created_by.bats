#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/lib/loop/created_by.sh
#
# Use cases:
# - created_by_format_compact_tokens formats small, K, and M scales
# - created_by_render_line omits output when all fields empty
# - created_by_render_line includes engine model and In/Out
# - created_by_render_line omits In/Out when usage absent
# - created_by_render_line uses model and tokens from usage_json alone
# - created_by_render_line labels each role when maker and checker models differ
# - created_by_render_line falls back to the models array when sessions are absent
# - created_by_usage_cache_label reports cache read and write counts and stays empty without cache traffic
# - created_by_usage_rounds_label counts maker and checker sessions and rejections from the final verdict

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/lib/loop/created_by.sh"
}

@test "created_by_format_compact_tokens formats small K and M scales" {
    run created_by_format_compact_tokens 17
    [ "$status" -eq 0 ]
    [ "$output" = "17" ]
    run created_by_format_compact_tokens 100000
    [ "$status" -eq 0 ]
    [ "$output" = "100K" ]
    run created_by_format_compact_tokens 1200000
    [ "$status" -eq 0 ]
    [ "$output" = "1.2M" ]
}

@test "created_by_render_line includes engine model and In/Out" {
    run created_by_render_line cursor '{"total_input_tokens":100000,"total_output_tokens":100000,"model":"Composer-2.5"}'
    [ "$status" -eq 0 ]
    [ "$output" = "Created By cursor Composer-2.5 In/Out: 100K/100K" ]
}

@test "created_by_render_line omits In/Out when usage absent" {
    run created_by_render_line cursor ''
    [ "$status" -eq 0 ]
    [ "$output" = "Created By cursor" ]
}

@test "created_by_render_line omits output when all fields empty" {
    run created_by_render_line '' ''
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "created_by_render_line uses model and tokens from usage_json alone" {
    run created_by_render_line '' '{"total_input_tokens":1842,"total_output_tokens":17,"model":"composer-2.5"}'
    [ "$status" -eq 0 ]
    [ "$output" = "Created By composer-2.5 In/Out: 2K/17" ]
}

@test "created_by_render_line labels each role when maker and checker models differ" {
    local usage
    usage='{"total_input_tokens":58,"total_output_tokens":15000,"models":["claude-opus-5","claude-sonnet-5"],"sessions":[{"role":"maker","model":"claude-sonnet-5","input":40,"output":12000},{"role":"checker","model":"claude-opus-5","input":18,"output":3000}]}'
    run created_by_render_line "claude" "${usage}"
    [ "$status" -eq 0 ]
    [ "$output" = "Created By claude maker=claude-sonnet-5 checker=claude-opus-5 In/Out: 58/15K" ]
}

@test "created_by_render_line falls back to the models array when sessions are absent" {
    local usage
    usage='{"total_input_tokens":58,"total_output_tokens":15000,"models":["claude-opus-5","claude-sonnet-5"]}'
    run created_by_render_line "claude" "${usage}"
    [ "$status" -eq 0 ]
    [ "$output" = "Created By claude claude-opus-5, claude-sonnet-5 In/Out: 58/15K" ]
}

@test "created_by_render_line keeps engine only when usage_json is invalid" {
    run created_by_render_line cursor 'not-json'
    [ "$status" -eq 0 ]
    [ "$output" = "Created By cursor" ]
}

@test "created_by_render_line uses em dash for missing In or Out side" {
    run created_by_render_line cursor '{"total_output_tokens":100}'
    [ "$status" -eq 0 ]
    [ "$output" = "Created By cursor In/Out: —/100" ]
}

@test "created_by_render_line emits In/Out without model when engine empty" {
    run created_by_render_line '' '{"total_input_tokens":100,"total_output_tokens":50}'
    [ "$status" -eq 0 ]
    [ "$output" = "Created By In/Out: 100/50" ]
}

@test "created_by_usage_cache_label reports cache read and write counts" {
    run created_by_usage_cache_label '{"cache_read_tokens":250000,"cache_write_tokens":30000}'
    [ "$status" -eq 0 ]
    [ "$output" = "read 250K, write 30K" ]
}

@test "created_by_usage_cache_label stays empty without cache traffic or valid json" {
    run created_by_usage_cache_label '{"cache_read_tokens":0,"cache_write_tokens":0}'
    [ -z "$output" ]
    run created_by_usage_cache_label 'not json'
    [ -z "$output" ]
    run created_by_usage_cache_label ''
    [ -z "$output" ]
}

@test "created_by_usage_rounds_label counts rejections from the final verdict" {
    local usage='{"sessions":[{"role":"maker"},{"role":"checker"},{"role":"maker"},{"role":"checker"}]}'
    run created_by_usage_rounds_label "${usage}" "APPROVE"
    [ "$output" = "maker 2, checker 2, rejected 1" ]
    run created_by_usage_rounds_label "${usage}" "REJECT"
    [ "$output" = "maker 2, checker 2, rejected 2" ]
}

@test "created_by_usage_rounds_label stays empty without maker or checker sessions" {
    run created_by_usage_rounds_label '{"sessions":[]}' "APPROVE"
    [ -z "$output" ]
    run created_by_usage_rounds_label '' "APPROVE"
    [ -z "$output" ]
}
