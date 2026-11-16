#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/lib/loop/loop_meta.sh
#
# Use cases:
# - loop_meta_build_block carries engine model and tokens
# - loop_meta_build_block reports prompt-cache counts beside In/Out when measured
# - loop_meta_build_block reports maker/checker rounds and rejections
# - loop_meta_build_block renders caller rows above the engine rows
# - loop_meta_build_block ends with the one shared footer after the Meta details
# - loop_meta_build_block still renders Meta and the footer when nothing is known
# - loop_meta_build_block blockquotes every line of a multi-line reason
# - loop_meta_build_block emits the idempotency marker
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

@test "loop_meta_build_block blockquotes every line of a multi-line reason" {
    run loop_meta_build_block "push" "APPROVE" "$(printf 'first line\nsecond line')" "" "" ""
    [ "$status" -eq 0 ]
    [[ $output == *"> first line"* ]]
    [[ $output == *"> second line"* ]]
}

@test "loop_meta_build_block carries engine model and tokens" {
    run loop_meta_build_block "pr_created" "APPROVE" "" "claude" "$(usage_fixture)" "https://x/run/1"
    [ "$status" -eq 0 ]
    [[ $output == *"<summary>Meta</summary>"* ]]
    [[ $output == *"| Key | Value |"* ]]
    [[ $output == *"| outcome | pr_created |"* ]]
    [[ $output == *"| verdict | APPROVE |"* ]]
    [[ $output == *"| engine | claude |"* ]]
    [[ $output == *"| model | maker=claude-sonnet-5 checker=claude-opus-5 |"* ]]
    [[ $output == *"| tokens | In/Out 58/15K |"* ]]
    [[ $output == *"| rounds | maker 1, checker 1, rejected 0 |"* ]]
    [[ $output == *"| run | [View run](https://x/run/1) |"* ]]
    [[ $output != *"Loop details"* ]]
}

@test "loop_meta_build_block emits the idempotency marker" {
    run loop_meta_build_block "push" "" "" "claude" "" ""
    [ "$status" -eq 0 ]
    [[ $output == *"<!-- loop-meta:v1 -->"* ]]
}

@test "loop_meta_build_block renders caller rows above the engine rows" {
    local level_line engine_line
    loop_meta_row "Level" "L2"
    loop_meta_row "Target" "integration:main"
    loop_meta_row "Skip reason" "none"
    run loop_meta_build_block "push" "" "" "claude" "" ""
    [ "$status" -eq 0 ]
    level_line="$(grep -n '| level | L2 |' <<< "${output}" | head -1 | cut -d: -f1)"
    engine_line="$(grep -n '| engine |' <<< "${output}" | head -1 | cut -d: -f1)"
    [ "${level_line}" -lt "${engine_line}" ]
    [[ $output == *"| target | integration:main |"* ]]
    [[ $output == *"| skip_reason | none |"* ]]
}

@test "loop_meta_build_block still renders Meta and the footer when nothing is known" {
    run loop_meta_build_block "" "" "" "" "" ""
    [ "$status" -eq 0 ]
    [[ $output == *"<summary>Meta</summary>"* ]]
    [[ $output == *"| outcome | unknown |"* ]]
    [[ $output == *"${LOOP_META_FOOTER}" ]]
}

@test "loop_meta_build_block ends with the one shared footer after the Meta details" {
    run loop_meta_build_block "push" "" "" "claude" "" ""
    [ "$status" -eq 0 ]
    [[ $LOOP_META_FOOTER == "<sub>Written by Loop Engineering (LE)"* ]]
    [[ $output == *"</details>"$'\n\n'"${LOOP_META_FOOTER}" ]]
    [ "$(grep -c 'Written by Loop Engineering' <<< "${output}")" -eq 1 ]
}

@test "loop_meta_reset clears queued caller rows" {
    loop_meta_row "Level" "L2"
    loop_meta_reset
    run loop_meta_build_block "push" "" "" "claude" "" ""
    [ "$status" -eq 0 ]
    [[ $output != *"| level |"* ]]
}

@test "loop_meta_row skips empty labels and values" {
    loop_meta_row "" "L2"
    loop_meta_row "Level" ""
    run loop_meta_build_block "push" "" "" "claude" "" ""
    [ "$status" -eq 0 ]
    [[ $output != *"| level |"* ]]
    [[ $output != *"|  |"* ]]
}

@test "loop_meta_build_block reports prompt-cache counts beside In/Out when measured" {
    local usage='{"total_input_tokens":44,"total_output_tokens":7000,"cache_read_tokens":250000,"cache_write_tokens":30000}'
    run loop_meta_build_block "pr_reviewed" "APPROVE" "" "claude" "${usage}" ""
    [ "$status" -eq 0 ]
    [[ $output == *"| tokens | In/Out 44/7K (cache read 250K, write 30K) |"* ]]
}

@test "loop_meta_build_block omits the cache note when no cache traffic was measured" {
    local usage='{"total_input_tokens":44,"total_output_tokens":7000,"cache_read_tokens":0,"cache_write_tokens":0}'
    run loop_meta_build_block "pr_reviewed" "APPROVE" "" "claude" "${usage}" ""
    [[ $output == *"| tokens | In/Out 44/7K |"* ]]
    [[ $output != *"cache"* ]]
}

@test "loop_meta_build_block reports maker/checker rounds and rejections" {
    local usage='{"total_input_tokens":10,"total_output_tokens":10,"sessions":[{"role":"maker","attempt":1},{"role":"checker","attempt":1},{"role":"maker","attempt":2},{"role":"checker","attempt":2},{"role":"maker","attempt":3},{"role":"checker","attempt":3}]}'
    run loop_meta_build_block "pr_created" "APPROVE" "" "claude" "${usage}" ""
    [[ $output == *"| rounds | maker 3, checker 3, rejected 2 |"* ]]
    run loop_meta_build_block "rejected" "REJECT" "" "claude" "${usage}" ""
    [[ $output == *"| rounds | maker 3, checker 3, rejected 3 |"* ]]
}

@test "loop_meta_build_block omits rounds when no session was recorded" {
    run loop_meta_build_block "push" "" "" "claude" "" ""
    [[ $output != *"| rounds |"* ]]
}
