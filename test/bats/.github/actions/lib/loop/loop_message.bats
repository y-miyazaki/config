#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/lib/loop/loop_message.sh
#
# Use cases:
# - loop_message_to_json prints nothing without message.md or with a blank one
# - loop_message_to_json ignores message_labels.json when message.md is absent
# - loop_message_to_json emits body and labels (null when absent)
# - loop_message_to_json drops the whole delivery on malformed or mis-shaped labels
# - loop_message_from_json writes message.md and message_labels.json
# - loop_message_from_json writes nothing for empty input and fails on invalid JSON
# - a message round trip keeps the body byte-identical

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/lib/loop/loop_message.sh"
    MSG_DIR="${BATS_TEST_TMPDIR}/msg"
    mkdir -p "${MSG_DIR}"
}

teardown() {
    rm -rf "${MSG_DIR}"
}

@test "loop_message_from_json fails on invalid JSON" {
    run loop_message_from_json 'not json' "${BATS_TEST_TMPDIR}/out"
    [ "$status" -eq 1 ]
    [[ $output == *"::error::"* ]]
}

@test "loop_message_from_json writes message.md and message_labels.json" {
    local out="${BATS_TEST_TMPDIR}/out/nested"
    run loop_message_from_json '{"body":"hello\n","labels":{"add":["bug"],"remove":[]}}' "${out}"
    [ "$status" -eq 0 ]
    [ "$(cat "${out}/message.md")" = "hello" ]
    [ "$(jq -c . "${out}/message_labels.json")" = '{"add":["bug"],"remove":[]}' ]
}

@test "loop_message_from_json writes nothing for empty input" {
    local out="${BATS_TEST_TMPDIR}/out"
    run loop_message_from_json "" "${out}"
    [ "$status" -eq 0 ]
    [ ! -e "${out}/message.md" ]
    [ ! -e "${out}/message_labels.json" ]
}

@test "loop_message_to_json emits body and null labels" {
    printf 'hello\n' > "${MSG_DIR}/message.md"
    run loop_message_to_json "${MSG_DIR}"
    [ "$status" -eq 0 ]
    [ "$output" = '{"body":"hello\n","labels":null}' ]
}

@test "loop_message_to_json emits labels when valid" {
    printf 'hello\n' > "${MSG_DIR}/message.md"
    printf '{"add":["bug"],"remove":["triage"]}\n' > "${MSG_DIR}/message_labels.json"
    run loop_message_to_json "${MSG_DIR}"
    [ "$status" -eq 0 ]
    [ "$output" = '{"body":"hello\n","labels":{"add":["bug"],"remove":["triage"]}}' ]
}

@test "loop_message_to_json ignores message_labels.json when message.md is absent" {
    printf '{"add":["bug"]}\n' > "${MSG_DIR}/message_labels.json"
    run loop_message_to_json "${MSG_DIR}"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "loop_message_to_json prints nothing and warns on malformed or mis-shaped labels" {
    local bad
    printf 'hello\n' > "${MSG_DIR}/message.md"
    for bad in '{' '{"add":"bug"}' '[1]' '{"remove":[1]}'; do
        printf '%s\n' "${bad}" > "${MSG_DIR}/message_labels.json"
        run loop_message_to_json "${MSG_DIR}"
        [ "$status" -eq 0 ]
        [ "$output" = "::warning::message_labels.json is invalid; nothing is delivered" ]
    done
}

@test "loop_message_to_json prints nothing without message.md or with a blank one" {
    run loop_message_to_json "${MSG_DIR}"
    [ "$status" -eq 0 ]
    [ -z "$output" ]

    printf ' \n\t\n' > "${MSG_DIR}/message.md"
    run loop_message_to_json "${MSG_DIR}"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "round trip keeps the body byte-identical" {
    local out="${BATS_TEST_TMPDIR}/out" json
    printf '## A\n\n`code` and ```fence```\nEOF\n\n' > "${MSG_DIR}/message.md"
    printf '{"add":["bug"],"remove":[]}\n' > "${MSG_DIR}/message_labels.json"
    json="$(loop_message_to_json "${MSG_DIR}")"
    [ -n "${json}" ]
    loop_message_from_json "${json}" "${out}"
    cmp "${MSG_DIR}/message.md" "${out}/message.md"
    [ "$(jq -c . "${out}/message_labels.json")" = '{"add":["bug"],"remove":[]}' ]
}
