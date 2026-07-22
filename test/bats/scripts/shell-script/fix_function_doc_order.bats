#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for scripts/shell-script/fix_function_doc_order.sh

# Use cases:
# - block_needs_reorder detects non-canonical section order
# - dry-run leaves file unchanged when reorder is needed
# - expand_target_paths finds shell scripts in a directory
# - process_file leaves canonical docs unchanged
# - process_file reorders function doc sections in place
# - script exits with error for missing file path
# - quiet mode suppresses info logs while reordering
# - process_file reorders multiple function doc blocks
# - process_file preserves non-section comment lines
# - script exits with error for unknown options

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

FIX_SCRIPT="$(bats_workspace_root)/scripts/shell-script/fix_function_doc_order.sh"

setup() {
    FIXTURE_DIR="${BATS_TEST_TMPDIR}/fix-function-doc-order"
    mkdir -p "${FIXTURE_DIR}"
}

@test "block_needs_reorder detects non-canonical section order" {
    local block_file="${BATS_TEST_TMPDIR}/block.txt"

    cat > "${block_file}" << 'EOF'
# Returns:
#   None
#
# Arguments:
#   $1 - path
#
# Globals:
#   None
EOF

    bats_source_rel "scripts/shell-script/fix_function_doc_order.sh"
    run block_needs_reorder "${block_file}"
    [ "$status" -eq 0 ]
}

@test "dry-run leaves file unchanged when reorder is needed" {
    local script="${FIXTURE_DIR}/reorder-me.sh"
    local before after

    cat > "${script}" << 'EOF'
#!/bin/bash
#######################################
# sample
#
# Returns:
#   None
#
# Arguments:
#   $1 - path
#
# Globals:
#   None
#######################################
function sample() {
    :
}
EOF

    before="$(cat "${script}")"
    run bash "${FIX_SCRIPT}" --dry-run "${script}"
    [ "$status" -eq 0 ]
    after="$(cat "${script}")"
    [ "${before}" = "${after}" ]
}

@test "expand_target_paths finds shell scripts in a directory" {
    local dir="${FIXTURE_DIR}/tree"
    mkdir -p "${dir}/nested"
    printf '%s\n' '#!/bin/bash' 'echo nested' > "${dir}/nested/child.sh"

    bats_source_rel "scripts/shell-script/fix_function_doc_order.sh"
    run bash -c "source '${FIX_SCRIPT}'; expand_target_paths '${dir}' | tr '\0' '\n'"
    [ "$status" -eq 0 ]
    [[ $output == *"child.sh"* ]]
}

@test "process_file leaves canonical docs unchanged" {
    local script="${FIXTURE_DIR}/canonical.sh"

    cat > "${script}" << 'EOF'
#!/bin/bash
#######################################
# sample
#
# Globals:
#   None
#
# Arguments:
#   $1 - path
#
# Outputs:
#   None
#
# Returns:
#   None
#######################################
function sample() {
    :
}
EOF

    bats_source_rel "scripts/shell-script/fix_function_doc_order.sh"
    run process_file "${script}"
    [ "$status" -eq 0 ]
    run grep -q '# Globals:' "${script}"
    [ "$status" -eq 0 ]
    run awk '/# Globals:/{g=NR} /# Arguments:/{a=NR} /# Outputs:/{o=NR} /# Returns:/{r=NR} END{exit !(g<a && a<o && o<r)}' "${script}"
    [ "$status" -eq 0 ]
}

@test "process_file reorders function doc sections in place" {
    local script="${FIXTURE_DIR}/needs-reorder.sh"

    cat > "${script}" << 'EOF'
#!/bin/bash
#######################################
# sample
#
# Returns:
#   None
#
# Arguments:
#   $1 - path
#
# Globals:
#   None
#
# Outputs:
#   None
#######################################
function sample() {
    :
}
EOF

    run bash "${FIX_SCRIPT}" -q "${script}"
    [ "$status" -eq 0 ]
    run awk '/# Globals:/{g=NR} /# Arguments:/{a=NR} /# Outputs:/{o=NR} /# Returns:/{r=NR} END{exit !(g<a && a<o && o<r)}' "${script}"
    [ "$status" -eq 0 ]
}

@test "script exits with error for missing file path" {
    run bash "${FIX_SCRIPT}" "${FIXTURE_DIR}/missing.sh"
    [ "$status" -eq 1 ]
    [[ $output == *"File not found"* ]]
}

@test "process_file preserves non-section comment lines inside doc blocks" {
    local script="${FIXTURE_DIR}/preserve-comments.sh"

    cat > "${script}" << 'SCRIPT'
#!/bin/bash
#######################################
# sample
#
# Returns:
#   None
#
# Note: keep this note
#
# Arguments:
#   $1 - path
#
# Globals:
#   None
#
# Outputs:
#   None
#######################################
function sample() {
    :
}
SCRIPT

    run bash "${FIX_SCRIPT}" -q "${script}"
    [ "$status" -eq 0 ]
    run grep -q 'Note: keep this note' "${script}"
    [ "$status" -eq 0 ]
    run awk '/# Globals:/{g=NR} /# Arguments:/{a=NR} /# Outputs:/{o=NR} /# Returns:/{r=NR} END{exit !(g<a && a<o && o<r)}' "${script}"
    [ "$status" -eq 0 ]
}

@test "process_file reorders multiple function doc blocks" {
    local script="${FIXTURE_DIR}/multi-fn.sh"

    cat > "${script}" << 'SCRIPT'
#!/bin/bash
#######################################
# first
#
# Returns:
#   None
#
# Globals:
#   None
#
# Arguments:
#   None
#
# Outputs:
#   None
#######################################
function first() {
    :
}

#######################################
# second
#
# Outputs:
#   None
#
# Returns:
#   None
#
# Arguments:
#   None
#
# Globals:
#   None
#######################################
function second() {
    :
}
SCRIPT

    run bash "${FIX_SCRIPT}" -q "${script}"
    [ "$status" -eq 0 ]
    run awk '
      /function first/ { in_first=0 }
      /# first/ { in_first=1 }
      in_first && /# Globals:/{g1=NR}
      in_first && /# Arguments:/{a1=NR}
      in_first && /# Outputs:/{o1=NR}
      in_first && /# Returns:/{r1=NR}
      /# second/ { in_second=1; in_first=0 }
      in_second && /# Globals:/{g2=NR}
      in_second && /# Arguments:/{a2=NR}
      in_second && /# Outputs:/{o2=NR}
      in_second && /# Returns:/{r2=NR}
      END { exit !(g1<a1 && a1<o1 && o1<r1 && g2<a2 && a2<o2 && o2<r2) }
    ' "${script}"
    [ "$status" -eq 0 ]
}

@test "quiet mode suppresses info logs while reordering" {
    local script="${FIXTURE_DIR}/quiet-reorder.sh"

    cat > "${script}" << 'SCRIPT'
#!/bin/bash
#######################################
# sample
#
# Returns:
#   None
#
# Globals:
#   None
#
# Arguments:
#   None
#
# Outputs:
#   None
#######################################
function sample() {
    :
}
SCRIPT

    run bash "${FIX_SCRIPT}" -q "${script}"
    [ "$status" -eq 0 ]
    [[ $output != *"Reordered function docs"* ]]
    [[ $output != *"INFO"* ]]
}

@test "script exits with error for unknown options" {
    run bash "${FIX_SCRIPT}" --unknown-flag
    [ "$status" -eq 1 ]
    [[ $output == *"Unknown option"* ]]
}
