#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/lib/loop/loop_meta.sh
#
# Use cases:
# - build_loop_meta_block carries engine model and tokens
# - build_loop_meta_block reports prompt-cache counts beside In/Out when measured
# - build_loop_meta_block reports maker/checker rounds and rejections
# - build_loop_meta_block renders caller rows above the engine rows
# - build_loop_meta_block ends with the one shared footer after the Meta details
# - build_loop_meta_block still renders Meta and the footer when nothing is known
# - build_loop_meta_block blockquotes every line of a multi-line reason
# - build_loop_meta_block emits the idempotency marker
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
    run build_loop_meta_block "pr_created" "APPROVE" "" "claude" "$(usage_fixture)" "https://x/run/1"
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

@test "build_loop_meta_block emits the idempotency marker" {
    run build_loop_meta_block "push" "" "" "claude" "" ""
    [ "$status" -eq 0 ]
    [[ $output == *"<!-- loop-meta:v1 -->"* ]]
}

@test "build_loop_meta_block renders caller rows above the engine rows" {
    local level_line engine_line
    loop_meta_row "Level" "L2"
    loop_meta_row "Target" "integration:main"
    loop_meta_row "Skip reason" "none"
    run build_loop_meta_block "push" "" "" "claude" "" ""
    [ "$status" -eq 0 ]
    level_line="$(grep -n '| level | L2 |' <<< "${output}" | head -1 | cut -d: -f1)"
    engine_line="$(grep -n '| engine |' <<< "${output}" | head -1 | cut -d: -f1)"
    [ "${level_line}" -lt "${engine_line}" ]
    [[ $output == *"| target | integration:main |"* ]]
    [[ $output == *"| skip_reason | none |"* ]]
}

@test "build_loop_meta_block still renders Meta and the footer when nothing is known" {
    run build_loop_meta_block "" "" "" "" "" ""
    [ "$status" -eq 0 ]
    [[ $output == *"<summary>Meta</summary>"* ]]
    [[ $output == *"| outcome | unknown |"* ]]
    [[ $output == *"${LOOP_META_FOOTER}" ]]
}

@test "build_loop_meta_block ends with the one shared footer after the Meta details" {
    run build_loop_meta_block "push" "" "" "claude" "" ""
    [ "$status" -eq 0 ]
    [[ $LOOP_META_FOOTER == "<sub>Written by Loop Engineering (LE)"* ]]
    [[ $output == *"</details>"$'\n\n'"${LOOP_META_FOOTER}" ]]
    [ "$(grep -c 'Written by Loop Engineering' <<< "${output}")" -eq 1 ]
}

@test "loop_meta_reset clears queued caller rows" {
    loop_meta_row "Level" "L2"
    loop_meta_reset
    run build_loop_meta_block "push" "" "" "claude" "" ""
    [ "$status" -eq 0 ]
    [[ $output != *"| level |"* ]]
}

@test "loop_meta_row skips empty labels and values" {
    loop_meta_row "" "L2"
    loop_meta_row "Level" ""
    run build_loop_meta_block "push" "" "" "claude" "" ""
    [ "$status" -eq 0 ]
    [[ $output != *"| level |"* ]]
    [[ $output != *"|  |"* ]]
}

@test "build_loop_meta_block reports prompt-cache counts beside In/Out when measured" {
    local usage='{"total_input_tokens":44,"total_output_tokens":7000,"cache_read_tokens":250000,"cache_write_tokens":30000}'
    run build_loop_meta_block "pr_reviewed" "APPROVE" "" "claude" "${usage}" ""
    [ "$status" -eq 0 ]
    [[ $output == *"| tokens | In/Out 44/7K (cache read 250K, write 30K) |"* ]]
}

@test "build_loop_meta_block omits the cache note when no cache traffic was measured" {
    local usage='{"total_input_tokens":44,"total_output_tokens":7000,"cache_read_tokens":0,"cache_write_tokens":0}'
    run build_loop_meta_block "pr_reviewed" "APPROVE" "" "claude" "${usage}" ""
    [[ $output == *"| tokens | In/Out 44/7K |"* ]]
    [[ $output != *"cache"* ]]
}

@test "build_loop_meta_block reports maker/checker rounds and rejections" {
    local usage='{"total_input_tokens":10,"total_output_tokens":10,"sessions":[{"role":"maker","attempt":1},{"role":"checker","attempt":1},{"role":"maker","attempt":2},{"role":"checker","attempt":2},{"role":"maker","attempt":3},{"role":"checker","attempt":3}]}'
    run build_loop_meta_block "pr_created" "APPROVE" "" "claude" "${usage}" ""
    [[ $output == *"| rounds | maker 3, checker 3, rejected 2 |"* ]]
    run build_loop_meta_block "rejected" "REJECT" "" "claude" "${usage}" ""
    [[ $output == *"| rounds | maker 3, checker 3, rejected 3 |"* ]]
}

@test "build_loop_meta_block omits rounds when no session was recorded" {
    run build_loop_meta_block "push" "" "" "claude" "" ""
    [[ $output != *"| rounds |"* ]]
}
