#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for scripts/shell-script/validate.sh (function doc validation)
#
# Use cases:
# - validate_function_docs passes a Google-style function doc block with explicit None
# - validate_function_docs fails when Outputs section is missing
# - validate_function_docs fails when canonical sections are out of order
# - auto_fix_function_doc_order reorders function doc sections when AUTO_FIX is enabled

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel "scripts/shell-script/validate.sh"
    FIXTURE_DIR="${BATS_TEST_TMPDIR}/validate_function_docs"
    mkdir -p "${FIXTURE_DIR}"
    AUTO_FIX=false
    CHECK_FUNCTION_DOCS=false
}

@test "--check-function-docs passes Google-style block with explicit None sections" {
    cat > "${FIXTURE_DIR}/ok.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

#######################################
# Echo a greeting.
# Globals:
#   None
# Arguments:
#   $1 - name to greet
# Outputs:
#   Writes greeting to stdout
# Returns:
#   0 on success
#######################################
function greet() {
    echo "hello $1"
}
EOF
    chmod +x "${FIXTURE_DIR}/ok.sh"

    CHECK_FUNCTION_DOCS=true
    run validate_function_docs "${FIXTURE_DIR}/ok.sh"
    [ "$status" -eq 0 ]
}

@test "--check-function-docs fails when Outputs section is missing" {
    cat > "${FIXTURE_DIR}/bad.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

#######################################
# Echo a greeting.
# Globals:
#   None
# Arguments:
#   $1 - name to greet
# Returns:
#   0 on success
#######################################
function greet() {
    echo "hello $1"
}
EOF
    chmod +x "${FIXTURE_DIR}/bad.sh"

    CHECK_FUNCTION_DOCS=true
    run validate_function_docs "${FIXTURE_DIR}/bad.sh"
    [ "$status" -eq 1 ]
}

@test "--check-function-docs fails when canonical sections are out of order" {
    cat > "${FIXTURE_DIR}/order.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

#######################################
# Echo a greeting.
# Arguments:
#   $1 - name to greet
# Globals:
#   None
# Outputs:
#   None
# Returns:
#   0 on success
#######################################
function greet() {
    echo "hello $1"
}
EOF
    chmod +x "${FIXTURE_DIR}/order.sh"

    CHECK_FUNCTION_DOCS=true
    run validate_function_docs "${FIXTURE_DIR}/order.sh"
    [ "$status" -eq 1 ]
    [[ $output == *"sections out of order"* ]]
    [[ $output == *"${FIXTURE_DIR}/order.sh:"* ]]
}

@test "-f --check-function-docs reorders function doc sections" {
    cat > "${FIXTURE_DIR}/reorder.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

#######################################
# Echo a greeting.
# Arguments:
#   $1 - name to greet
# Globals:
#   None
# Outputs:
#   None
# Returns:
#   0 on success
#######################################
function greet() {
    echo "hello $1"
}
EOF
    chmod +x "${FIXTURE_DIR}/reorder.sh"

    AUTO_FIX=true
    CHECK_FUNCTION_DOCS=true
    auto_fix_function_doc_order "${FIXTURE_DIR}/reorder.sh"
    run validate_function_docs "${FIXTURE_DIR}/reorder.sh"
    [ "$status" -eq 0 ]
    globals_line=$(grep -n '^# Globals:' "${FIXTURE_DIR}/reorder.sh" | head -1 | cut -d: -f1)
    arguments_line=$(grep -n '^# Arguments:' "${FIXTURE_DIR}/reorder.sh" | head -1 | cut -d: -f1)
    [ "$globals_line" -lt "$arguments_line" ]
}
