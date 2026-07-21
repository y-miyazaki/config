#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .apm/packages/shell-script/.apm/skills/shell-script-validation/scripts/validate.sh
#
# Use cases:
# - --check-function-docs passes a Google-style function doc block with explicit None
# - --check-function-docs fails when Outputs section is missing

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    TARGET_SCRIPT="$(bats_workspace_root)/.apm/packages/shell-script/.apm/skills/shell-script-validation/scripts/validate.sh"
    FIXTURE_DIR="${BATS_TEST_TMPDIR}/validate_function_docs"
    mkdir -p "${FIXTURE_DIR}"
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

    run bash "${TARGET_SCRIPT}" --check-function-docs "${FIXTURE_DIR}/ok.sh" -q
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

    run bash "${TARGET_SCRIPT}" --check-function-docs "${FIXTURE_DIR}/bad.sh" -q
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

    run bash "${TARGET_SCRIPT}" --check-function-docs "${FIXTURE_DIR}/order.sh" -q
    [ "$status" -eq 1 ]
    [[ $output == *":9:"* ]] || [[ $output == *"sections out of order"* ]]
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

    run bash "${TARGET_SCRIPT}" -f --check-function-docs "${FIXTURE_DIR}/reorder.sh" -q
    [ "$status" -eq 0 ]
    globals_line=$(grep -n '^# Globals:' "${FIXTURE_DIR}/reorder.sh" | head -1 | cut -d: -f1)
    arguments_line=$(grep -n '^# Arguments:' "${FIXTURE_DIR}/reorder.sh" | head -1 | cut -d: -f1)
    [ "$globals_line" -lt "$arguments_line" ]
}
