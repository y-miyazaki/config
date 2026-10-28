#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for scripts/shell-script/validate.sh (function order validation, G-03)
#
# Use cases:
# - validate_function_order passes show_usage, parse_arguments, a-z functions, then main
# - validate_function_order reports the first out-of-order function with file and line
# - validate_function_order requires main last and show_usage/parse_arguments first
# - validate_function_order ignores heredoc text that looks like a function
# - validate_function_order does not treat a here-string as a heredoc
# - validate_function_order checks sourced libraries for a-z order only
# - validate_function_order is skipped unless CHECK_FUNCTION_DOCS is enabled

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel "scripts/shell-script/validate.sh"
    FIXTURE_DIR="${BATS_TEST_TMPDIR}/validate_function_order"
    mkdir -p "${FIXTURE_DIR}"
    CHECK_FUNCTION_DOCS=true
}

@test "validate_function_order ignores heredoc text that looks like a function" {
    cat > "${FIXTURE_DIR}/heredoc.sh" << 'EOF'
#!/bin/bash
function alpha {
    cat << TXT
zzz {
TXT
}
function beta {
    :
}
EOF
    run validate_function_order "${FIXTURE_DIR}/heredoc.sh"
    [ "$status" -eq 0 ]
}

@test "validate_function_order is skipped unless CHECK_FUNCTION_DOCS is enabled" {
    cat > "${FIXTURE_DIR}/unsorted.sh" << 'EOF'
#!/bin/bash
function zeta {
    :
}
function alpha {
    :
}
EOF
    CHECK_FUNCTION_DOCS=false
    run validate_function_order "${FIXTURE_DIR}/unsorted.sh"
    [ "$status" -eq 0 ]
}

@test "validate_function_order passes show_usage, parse_arguments, a-z functions, then main" {
    cat > "${FIXTURE_DIR}/ok.sh" << 'EOF'
#!/bin/bash
function show_usage {
    :
}
function parse_arguments {
    :
}
function alpha {
    :
}
function beta() {
    :
}
function main {
    :
}
EOF
    run validate_function_order "${FIXTURE_DIR}/ok.sh"
    [ "$status" -eq 0 ]
}

@test "validate_function_order reports the first out-of-order function with file and line" {
    cat > "${FIXTURE_DIR}/bad.sh" << 'EOF'
#!/bin/bash
function zeta {
    :
}
function alpha {
    :
}
EOF
    run validate_function_order "${FIXTURE_DIR}/bad.sh"
    [ "$status" -eq 1 ]
    [[ $output == *"bad.sh:2: function 'zeta' is out of order (expected 'alpha' here"* ]]
}

@test "validate_function_order requires main last and show_usage/parse_arguments first" {
    cat > "${FIXTURE_DIR}/main_first.sh" << 'EOF'
#!/bin/bash
function main {
    :
}
function helper {
    :
}
EOF
    run validate_function_order "${FIXTURE_DIR}/main_first.sh"
    [ "$status" -eq 1 ]
    [[ $output == *"function 'main' is out of order"* ]]

    cat > "${FIXTURE_DIR}/usage_late.sh" << 'EOF'
#!/bin/bash
function helper {
    :
}
function show_usage {
    :
}
EOF
    run validate_function_order "${FIXTURE_DIR}/usage_late.sh"
    [ "$status" -eq 1 ]
    [[ $output == *"function 'helper' is out of order (expected 'show_usage' here"* ]]
}

@test "validate_function_order checks sourced libraries for a-z order only" {
    cat > "${FIXTURE_DIR}/lib.sh" << 'EOF'
#!/bin/bash
function bravo {
    :
}
function alpha {
    :
}
EOF
    run validate_function_order "${FIXTURE_DIR}/lib.sh"
    [ "$status" -eq 1 ]
    [[ $output == *"function 'bravo' is out of order (expected 'alpha' here"* ]]
}

@test "validate_function_order does not treat a here-string as a heredoc" {
    cat > "${FIXTURE_DIR}/herestring.sh" << 'EOF'
#!/bin/bash
function a {
    read -r x <<< foo
}
function c {
    :
}
function b {
    :
}
EOF
    run validate_function_order "${FIXTURE_DIR}/herestring.sh"
    [ "$status" -eq 1 ]
    [[ $output == *"function 'c' is out of order (expected 'b' here"* ]]
}
