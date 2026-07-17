#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for scripts/lib/json.sh

# Use cases:
# - json_escape escapes carriage returns and other control characters
# - json_escape preserves printable characters and standard escapes
# - json_field_string emits valid JSON for multiline values

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel "scripts/lib/json.sh"
}

@test "json_escape escapes carriage returns and other control characters" {
    local raw escaped obj

    raw=$'\r\nline\rwith\x01control'
    escaped="$(json_escape "${raw}")"
    obj=$(printf '{"value":"%s"}' "${escaped}")

    run jq -e . <<< "${obj}"
    [ "$status" -eq 0 ]
    run jq -e --arg expected "${raw}" '.value == $expected' <<< "${obj}"
    [ "$status" -eq 0 ]
}

@test "json_escape preserves printable characters and standard escapes" {
    local escaped obj

    escaped="$(json_escape 'path\to "file"')"
    obj=$(printf '{"value":"%s"}' "${escaped}")

    run jq -e '.value == "path\\to \"file\""' <<< "${obj}"
    [ "$status" -eq 0 ]
}

@test "json_field_string emits valid JSON for multiline values" {
    local obj

    obj="$({
        json_object_start
        json_field_string "message" $'line1\r\nline2' ""
        json_object_end
    })"

    run jq -e '.message == "line1\r\nline2"' <<< "${obj}"
    [ "$status" -eq 0 ]
}
