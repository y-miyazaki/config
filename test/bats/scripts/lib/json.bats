#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

bats_require_minimum_version 1.5.0

# Tests for scripts/lib/json.sh

# Use cases:
# - json_object builds objects with inferred bool/null/number types and optional key omission
# - json_object keeps numeric-looking ID strings as JSON strings
# - json_object escapes multiline and control-character string values
# - json_object rejects odd argument counts and unsafe keys via jq --arg
# - json_array joins encoded values and raw JSON fragments
# - json_object requires jq at runtime
# - json_string_array omits empty elements
# - json_number marks values for numeric JSON encoding

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel "scripts/lib/json.sh"
}

@test "json_object builds objects with inferred types and optional key omission" {
    local obj

    obj="$(json_object --skip-empty \
        status "ok" \
        skip "false" \
        line "$(json_number 42)" \
        hint "")"

    run jq -e '
        .status == "ok"
        and .skip == false
        and .line == 42
        and (has("hint") | not)
    ' <<< "${obj}"
    [ "$status" -eq 0 ]
}

@test "json_object keeps numeric-looking ID strings as JSON strings" {
    local obj

    obj="$(json_object workflow_run_id "12345")"

    run jq -e '.workflow_run_id == "12345" and (.workflow_run_id | type == "string")' <<< "${obj}"
    [ "$status" -eq 0 ]
}

@test "json_object escapes multiline and control-character string values" {
    local obj

    obj="$(json_object message $'line1\r\nline2' token $'\x01secret')"

    run jq -e '.message == "line1\r\nline2" and .token == "\u0001secret"' <<< "${obj}"
    [ "$status" -eq 0 ]
}

@test "json_object rejects odd argument counts" {
    run json_object status "ok" extra
    [ "$status" -eq 1 ]
    [[ ${output} == *"expected even number"* ]]
}

@test "json_object encodes keys with embedded quotes safely" {
    local obj

    obj="$(json_object 'key"quote' "value")"

    run jq -e '.["key\"quote"] == "value"' <<< "${obj}"
    [ "$status" -eq 0 ]
}

@test "json_array joins encoded values and raw JSON fragments" {
    local fragment obj

    fragment="$(json_object kind "todo_comment" path "src/a.go" line "$(json_number 1)" snippet "x" source "test")"
    obj="$(json_array "${fragment}" "warn")"

    run jq -e '
        length == 2
        and .[0].kind == "todo_comment"
        and .[1] == "warn"
    ' <<< "${obj}"
    [ "$status" -eq 0 ]
}

@test "json_string_array omits empty elements" {
    local obj

    obj="$(json_string_array "a" "" "b")"

    run jq -e '. == ["a","b"]' <<< "${obj}"
    [ "$status" -eq 0 ]
}

@test "json_number rejects invalid number literals" {
    run json_number "01"
    [ "$status" -eq 1 ]
}

@test "json_escape_string escapes quotes and control characters without jq" {
    local escaped

    escaped="$(json_escape_string $'quote"and\nline')"

    [ "${escaped}" = 'quote\"and\nline' ]
}

@test "json_escape_string escapes other control bytes as unicode escapes" {
    local escaped

    escaped="$(json_escape_string $'\x07')"

    [[ ${escaped} =~ ^\\u0007$ ]]
}

@test "json_emit_minimal_error emits valid JSON for control-byte messages" {
    local obj

    obj="$(json_emit_minimal_error $'bad\x07byte')"

    run jq -e '.status == "error" and .skip == true and .message == "bad\u0007byte"' <<< "${obj}"
    [ "$status" -eq 0 ]
}

@test "json_object encodes json_number fields as JSON numbers" {
    local obj

    obj="$(json_object line "$(json_number 42)" count "$(json_number 3)")"

    run jq -e '.line == 42 and .count == 3 and (.line | type) == "number"' <<< "${obj}"
    [ "$status" -eq 0 ]
}

@test "json_object requires jq at runtime" {
    local fakebin exe base dir json_lib

    fakebin="${BATS_TEST_TMPDIR}/fakebin"
    mkdir -p "${fakebin}"
    for dir in /usr/bin /bin; do
        for exe in "${dir}"/*; do
            base="$(basename "${exe}")"
            [[ ${base} == "jq" ]] && continue
            [[ -e "${fakebin}/${base}" ]] && continue
            ln -sf "${exe}" "${fakebin}/${base}"
        done
    done

    json_lib="$(bats_workspace_root)/scripts/lib/json.sh"
    run -127 env PATH="${fakebin}" bash -c "source '${json_lib}'; json_object status ok"
    [ "$status" -eq 127 ]
}
