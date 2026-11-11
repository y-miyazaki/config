#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

bats_require_minimum_version 1.5.0
# Tests for .github/actions/loop-detect/lib/items.sh

# Use cases:
# - extract_items fails on duplicate keys
# - extract_items fails on invalid key
# - extract_items returns nothing when items absent
# - extract_items returns empty array for empty items
# - extract_items returns compact items array
# - item_result_json keeps only that item's context and adds key
# - item_result_json does not leak other items
# - item_target_key joins branch and key with a hash
# - order_items_by_last_run puts missing state first
# - order_items_by_last_run orders oldest first and is stable
# - validate_item_key accepts valid keys
# - validate_item_key rejects empty / double dot / leading dot / trailing dot / space / hash / over 64 chars

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/loop-detect/lib/_init.sh"
    ITEMS_TMP="$(mktemp -d)"
    export ITEMS_TMP
}

teardown() {
    rm -rf "${ITEMS_TMP}"
}

@test "extract_items fails on duplicate keys" {
    run --separate-stderr extract_items '{"items":[{"key":"issue:1"},{"key":"issue:1"}]}'
    [ "$status" -eq 1 ]
    [[ ${stderr} == *"::error::"* ]]
}

@test "extract_items fails on invalid key" {
    run --separate-stderr extract_items '{"items":[{"key":"a b"}]}'
    [ "$status" -eq 1 ]
    [[ ${stderr} == *"::error::"* ]]

    run --separate-stderr extract_items '{"items":[{"entity":{}}]}'
    [ "$status" -eq 1 ]
}

@test "extract_items returns compact items array" {
    run extract_items '{"items":[{"key":"issue:1","context":{"n":1}},{"key":"issue:2"}]}'
    [ "$status" -eq 0 ]
    [ "$output" = '[{"key":"issue:1","context":{"n":1}},{"key":"issue:2"}]' ]
}

@test "extract_items returns empty array for empty items" {
    run extract_items '{"items":[]}'
    [ "$status" -eq 0 ]
    [ "$output" = '[]' ]
}

@test "extract_items returns nothing when items absent" {
    run extract_items '{"issue_number":1}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "item_result_json does not leak other items" {
    run item_result_json '{"key":"issue:1","context":{"issue_number":1},"items":[{"key":"issue:2"}]}'
    [ "$status" -eq 0 ]
    [[ $output != *"issue:2"* ]]
}

@test "item_result_json keeps only that item's context and adds key" {
    run item_result_json '{"key":"issue:1","entity":{"kind":"issue","number":1},"context":{"issue_number":1}}'
    [ "$status" -eq 0 ]
    [ "$output" = '{"status":"ok","skip":false,"result":{"issue_number":1,"key":"issue:1"}}' ]
}

@test "item_target_key joins branch and key with a hash" {
    run item_target_key main issue:123
    [ "$status" -eq 0 ]
    [ "$output" = 'integration:main#issue:123' ]
}

@test "order_items_by_last_run orders oldest first and is stable" {
    local state="${ITEMS_TMP}/state.json"
    cat > "${state}" << 'JSON'
{"targets":{
"integration:main#a":{"last_run":"2026-01-03T00:00:00Z"},
"integration:main#b":{"last_run":"2026-01-01T00:00:00Z"},
"integration:main#c":{"last_run":"2026-01-03T00:00:00Z"},
"integration:main#d":{"last_run":"2026-01-02T00:00:00Z"}}}
JSON
    run order_items_by_last_run "${state}" main '[{"key":"a"},{"key":"c"},{"key":"d"},{"key":"b"}]'
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.[].key]' <<< "$output")" = '["b","d","a","c"]' ]
}

@test "order_items_by_last_run puts missing state first" {
    local state="${ITEMS_TMP}/state.json"
    echo '{"targets":{"integration:main#a":{"last_run":"2026-01-01T00:00:00Z"}}}' > "${state}"
    run order_items_by_last_run "${state}" main '[{"key":"a"},{"key":"b"},{"key":"c"}]'
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.[].key]' <<< "$output")" = '["b","c","a"]' ]
}

@test "validate_item_key accepts issue:123" {
    run validate_item_key "issue:123"
    [ "$status" -eq 0 ]
    run validate_item_key "a.b-c_d"
    [ "$status" -eq 0 ]
    run validate_item_key "$(printf 'a%.0s' {1..64})"
    [ "$status" -eq 0 ]
}

@test "validate_item_key rejects empty / double dot / leading dot / trailing dot / space / hash / over 64 chars" {
    run validate_item_key ""
    [ "$status" -eq 1 ]
    run validate_item_key "a..b"
    [ "$status" -eq 1 ]
    run validate_item_key ".a"
    [ "$status" -eq 1 ]
    run validate_item_key "a."
    [ "$status" -eq 1 ]
    run validate_item_key "a b"
    [ "$status" -eq 1 ]
    run validate_item_key "a#b"
    [ "$status" -eq 1 ]
    run validate_item_key "$(printf 'a%.0s' {1..65})"
    [ "$status" -eq 1 ]
}
