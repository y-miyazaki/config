#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .apm/packages/shell-script/.apm/skills/shell-script-validation/scripts/fix_function_doc_order.sh
#
# Use cases:
# - reorder function doc sections to Globals before Arguments
# - leave already-canonical blocks unchanged

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    TARGET_SCRIPT="$(bats_workspace_root)/.apm/packages/shell-script/.apm/skills/shell-script-validation/scripts/fix_function_doc_order.sh"
    FIXTURE_DIR="${BATS_TEST_TMPDIR}/fix_function_doc_order"
    mkdir -p "${FIXTURE_DIR}"
}

@test "fix_function_doc_order moves Globals before Arguments" {
    cat > "${FIXTURE_DIR}/reorder.sh" << 'EOF'
#!/bin/bash
#######################################
# Echo a greeting.
# Arguments:
#   $1 - name
# Globals:
#   None
# Outputs:
#   None
# Returns:
#   0 on success
#######################################
function greet() {
    echo "$1"
}
EOF

    run bash "${TARGET_SCRIPT}" "${FIXTURE_DIR}/reorder.sh"
    [ "$status" -eq 0 ]
    globals_line=$(grep -n '^# Globals:' "${FIXTURE_DIR}/reorder.sh" | head -1 | cut -d: -f1)
    arguments_line=$(grep -n '^# Arguments:' "${FIXTURE_DIR}/reorder.sh" | head -1 | cut -d: -f1)
    [ "$globals_line" -lt "$arguments_line" ]
}

@test "fix_function_doc_order leaves canonical blocks unchanged" {
    cat > "${FIXTURE_DIR}/ok.sh" << 'EOF'
#!/bin/bash
#######################################
# Echo a greeting.
# Globals:
#   None
# Arguments:
#   $1 - name
# Outputs:
#   None
# Returns:
#   0 on success
#######################################
function greet() {
    echo "$1"
}
EOF
    cp "${FIXTURE_DIR}/ok.sh" "${FIXTURE_DIR}/ok.before"

    run bash "${TARGET_SCRIPT}" "${FIXTURE_DIR}/ok.sh"
    [ "$status" -eq 0 ]
    diff -u "${FIXTURE_DIR}/ok.before" "${FIXTURE_DIR}/ok.sh"
}
