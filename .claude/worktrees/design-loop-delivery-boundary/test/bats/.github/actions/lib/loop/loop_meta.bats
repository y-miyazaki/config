#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/lib/loop/loop_meta.sh
#
# Use cases:
# - build_loop_meta_block carries engine model and tokens
# - build_loop_meta_block renders caller rows above the engine rows
# - build_loop_meta_block returns empty when nothing is known
# - build_loop_meta_block blockquotes every line of a multi-line reason
# - build_loop_meta_block emits the idempotency marker
# - loop_meta_icon maps outcome and verdict to a status emoji
# - loop_meta_reset clears queued caller rows
# - loop_meta_row skips empty labels and values

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/lib/loop/created_by.sh"
    bats_source_rel ".github/actions/lib/loop/loop_meta.sh"
    loop_meta_reset
}

usage_fixture() {
    printf '%s' '{"total_input_tokens":58,"total_output_tokens":15000,"models":["claude-opus-5","claude-sonnet-5"],"sessions":[{"role":"maker","model":"claude-sonnet-5","input":40,"output":12000},{"role":"checker","model":"claude-opus-5","input":18,"output":3000}]}'
}

@test "build_loop_meta_block blockquotes every line of a multi-line reason" {
    run build_loop_meta_block "push" "APPROVE" "$(printf 'first line\nsecond line')" "" "" ""
    [ "$status" -eq 0 ]
    [[ $output == *"> first line"* ]]
    [[ $output == *"> second line"* ]]
}

@test "build_loop_meta_block carries engine model and tokens" {
    run build_loop_meta_block "pr-created" "APPROVE" "" "claude" "$(usage_fixture)" "https://x/run/1"
    [ "$status" -eq 0 ]
    [[ $output == *"<summary>✅ <code>pr-created</code> · Loop details</summary>"* ]]
    [[ $output == *"| Verdict | \`APPROVE\` |"* ]]
    [[ $output == *"| Engine | \`claude\` |"* ]]
    [[ $output == *"| Model | \`maker=claude-sonnet-5 checker=claude-opus-5\` |"* ]]
    [[ $output == *"| Tokens | In/Out 58/15K |"* ]]
    [[ $output == *"| Run | [View run](https://x/run/1) |"* ]]
}

@test "build_loop_meta_block emits the idempotency marker" {
    run build_loop_meta_block "push" "" "" "claude" "" ""
    [ "$status" -eq 0 ]
    [[ $output == *"<!-- loop-meta:v1 -->"* ]]
}

@test "build_loop_meta_block renders caller rows above the engine rows" {
    local level_line engine_line
    loop_meta_row "Level" "L2"
    loop_meta_row "Target" '`integration:main`'
    run build_loop_meta_block "push" "" "" "claude" "" ""
    [ "$status" -eq 0 ]
    level_line="$(grep -n "| Level | L2 |" <<< "${output}" | head -1 | cut -d: -f1)"
    engine_line="$(grep -n "| Engine |" <<< "${output}" | head -1 | cut -d: -f1)"
    [ "${level_line}" -lt "${engine_line}" ]
    [[ $output == *"| Target | \`integration:main\` |"* ]]
}

@test "build_loop_meta_block returns empty when nothing is known" {
    run build_loop_meta_block "" "" "" "" "" ""
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "loop_meta_icon maps outcome and verdict to a status emoji" {
    run loop_meta_icon "pr-created" "APPROVE"
    [ "$output" = "✅" ]
    run loop_meta_icon "rejected" "REJECT"
    [ "$output" = "❌" ]
    run loop_meta_icon "error" ""
    [ "$output" = "❌" ]
    run loop_meta_icon "no-changes" "APPROVE"
    [ "$output" = "ℹ️" ]
    run loop_meta_icon "" ""
    [ "$output" = "ℹ️" ]
}

@test "loop_meta_reset clears queued caller rows" {
    loop_meta_row "Level" "L2"
    loop_meta_reset
    run build_loop_meta_block "push" "" "" "claude" "" ""
    [ "$status" -eq 0 ]
    [[ $output != *"| Level |"* ]]
}

@test "loop_meta_row skips empty labels and values" {
    loop_meta_row "" "L2"
    loop_meta_row "Level" ""
    run build_loop_meta_block "push" "" "" "claude" "" ""
    [ "$status" -eq 0 ]
    [[ $output != *"| Level |"* ]]
    [[ $output != *"|  |"* ]]
}
