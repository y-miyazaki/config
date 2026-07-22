#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for scripts/shell-script/validate.sh

# Use cases:
# - print_summary_overall_result prints success and failure outcomes
# - print_summary_statistics prints validation counters
# - record_script_validation_result updates pass counters
# - record_script_validation_result logs shellcheck failures only on failure
# - record_script_validation_result does not log generic failure for other errors
# - run_script_validation_steps records failure when auto_fix_function_doc_order fails
# - run_script_validation_steps returns validation flags for a minimal script
# - validate_function_docs skips when CHECK_FUNCTION_DOCS is false
# - validate_function_docs fails on missing/out-of-order sections when enabled
# - validate_function_docs passes a well-documented function when enabled
# - validate_script_accessible accepts readable files
# - validate_script_accessible rejects missing files
# - validate_script_accessible skips directories without counting failures
# - collect_bats_failures_from_tap records failing tests and summary
# - print_summary_bats_results reports incomplete bats runs
# - print_summary_overall_result reports mixed script and bats failures
# - print_summary_overall_result reports incomplete bats when no failures recorded

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    WORKSPACE_ROOT="$(bats_workspace_root)"
    export WORKSPACE_ROOT
    export VERBOSE=false
    export AUTO_FIX=false
    export CHECK_FUNCTION_DOCS=false
    TOTAL_SCRIPTS=0
    PASSED_SCRIPTS=0
    FAILED_SCRIPTS=0
    WARNINGS_COUNT=0
    PASSED_SCRIPTS_LIST=()
    FAILED_SCRIPTS_LIST=()
    WARNING_SCRIPTS_LIST=()
    BATS_FAILED_TESTS=()
    BATS_EXIT_CODE=0
    BATS_SUMMARY=""

    bats_source_rel "scripts/shell-script/validate.sh"
    FIXTURE_DIR="${BATS_TEST_TMPDIR}/shell-script-validate"
    mkdir -p "${FIXTURE_DIR}"
}

@test "print_summary_overall_result prints failure when scripts failed" {
    FAILED_SCRIPTS=2
    BATS_FAILED_TESTS=()
    BATS_EXIT_CODE=0

    run print_summary_overall_result
    [ "$status" -eq 0 ]
    [[ $output == *"Validation failed: 2 script(s)"* ]]
}

@test "print_summary_overall_result prints success when all validations passed" {
    FAILED_SCRIPTS=0
    BATS_FAILED_TESTS=()
    BATS_EXIT_CODE=0
    WARNINGS_COUNT=0

    run print_summary_overall_result
    [ "$status" -eq 0 ]
    [[ $output == *"All scripts passed validation with no warnings"* ]]
}

@test "print_summary_statistics prints validation counters" {
    TOTAL_SCRIPTS=3
    PASSED_SCRIPTS=2
    FAILED_SCRIPTS=1
    WARNINGS_COUNT=0

    run print_summary_statistics
    [ "$status" -eq 0 ]
    [[ $output == *"Total scripts validated: 3"* ]]
    [[ $output == *"Scripts passed: 2"* ]]
    [[ $output == *"Scripts failed: 1"* ]]
}

@test "record_script_validation_result does not log generic failure for other validation errors" {
    FAILED_SCRIPTS=0
    FAILED_SCRIPTS_LIST=()
    local script="${FIXTURE_DIR}/doc-fail.sh"
    local log_file="${BATS_TEST_TMPDIR}/doc-fail.log"

    record_script_validation_result "${script}" "doc-fail.sh" "tmp/doc-fail.sh" false true 2> "${log_file}"

    [ "${FAILED_SCRIPTS}" -eq 1 ]
    [ "${#FAILED_SCRIPTS_LIST[@]}" -eq 1 ]
    [ ! -s "${log_file}" ]
}

@test "record_script_validation_result logs shellcheck failure only for shellcheck errors" {
    FAILED_SCRIPTS=0
    FAILED_SCRIPTS_LIST=()
    local script="${FIXTURE_DIR}/shellcheck-fail.sh"
    local log_file="${BATS_TEST_TMPDIR}/shellcheck-fail.log"

    record_script_validation_result "${script}" "shellcheck-fail.sh" "tmp/shellcheck-fail.sh" false false 2> "${log_file}"

    [ "${FAILED_SCRIPTS}" -eq 1 ]
    [ "${#FAILED_SCRIPTS_LIST[@]}" -eq 1 ]
    run grep -q "Shellcheck failed" "${log_file}"
    [ "$status" -eq 0 ]
    run grep -q "Validation failed" "${log_file}"
    [ "$status" -eq 1 ]
}

@test "record_script_validation_result updates pass counters" {
    PASSED_SCRIPTS=0
    PASSED_SCRIPTS_LIST=()
    local script="${FIXTURE_DIR}/passed.sh"

    record_script_validation_result "${script}" "passed.sh" "tmp/passed.sh" true true

    [ "${PASSED_SCRIPTS}" -eq 1 ]
    [ "${PASSED_SCRIPTS_LIST[0]}" = "tmp/passed.sh" ]
}

@test "run_script_validation_steps records failure when auto_fix_function_doc_order fails" {
    local script="${FIXTURE_DIR}/doc-fix-fail.sh"
    local validation_passed=true
    local shellcheck_passed=true

    cat > "${script}" << 'EOF'
#!/bin/bash
set -euo pipefail
echo ok
EOF
    chmod +x "${script}"

    auto_fix_function_doc_order() {
        return 1
    }

    run_script_validation_steps "${script}" validation_passed shellcheck_passed
    [ "${validation_passed}" = "false" ]
    [ "${shellcheck_passed}" = "true" ]
}

@test "run_script_validation_steps returns validation flags for a minimal script" {
    local script="${FIXTURE_DIR}/minimal.sh"
    local validation_passed=true
    local shellcheck_passed=true

    cat > "${script}" << 'EOF'
#!/bin/bash
set -euo pipefail
echo "ok"
EOF
    chmod +x "${script}"

    run_script_validation_steps "${script}" validation_passed shellcheck_passed
    [ "${validation_passed}" = "true" ]
    [ "${shellcheck_passed}" = "true" ]
}

@test "validate_script_accessible accepts readable files" {
    local script="${FIXTURE_DIR}/readable.sh"
    printf '%s\n' '#!/bin/bash' 'echo ok' > "${script}"
    chmod +r "${script}"

    run validate_script_accessible "${script}" "readable.sh" "tmp/readable.sh"
    [ "$status" -eq 0 ]
}

@test "validate_script_accessible rejects missing files" {
    FAILED_SCRIPTS=0
    FAILED_SCRIPTS_LIST=()

    validate_script_accessible "${FIXTURE_DIR}/missing.sh" "missing.sh" "tmp/missing.sh" || true
    [ "${FAILED_SCRIPTS}" -eq 1 ]
    [ "${#FAILED_SCRIPTS_LIST[@]}" -eq 1 ]
}

@test "validate_script_accessible skips directories without counting failures" {
    local dir="${FIXTURE_DIR}/dir-target"
    mkdir -p "${dir}"
    TOTAL_SCRIPTS=1
    FAILED_SCRIPTS=0

    validate_script_accessible "${dir}" "dir-target" "tmp/dir-target" || true

    [ "${TOTAL_SCRIPTS}" -eq 0 ]
    [ "${FAILED_SCRIPTS}" -eq 0 ]
}

@test "validate_function_docs fails on missing and out-of-order sections when enabled" {
    local script="${FIXTURE_DIR}/bad-docs.sh"
    CHECK_FUNCTION_DOCS=true

    cat > "${script}" << 'EOF'
#!/bin/bash
set -euo pipefail

#######################################
# Arguments:
#   None
#
# Globals:
#   None
#
#######################################
function bad_docs {
    echo ok
}
EOF

    run validate_function_docs "${script}"
    [ "$status" -eq 1 ]
    [[ $output == *"Function doc block validation failed"* || $output == *"out of order"* || $output == *"missing"* ]]
}

@test "validate_function_docs passes a well-documented function when enabled" {
    local script="${FIXTURE_DIR}/good-docs.sh"
    CHECK_FUNCTION_DOCS=true

    cat > "${script}" << 'EOF'
#!/bin/bash
set -euo pipefail

#######################################
# good_docs: Example documented function
#
# Globals:
#   None
#
# Arguments:
#   None
#
# Outputs:
#   Writes ok to stdout
#
# Returns:
#   0
#
#######################################
function good_docs {
    echo ok
}
EOF

    run validate_function_docs "${script}"
    [ "$status" -eq 0 ]
}

@test "validate_function_docs skips when CHECK_FUNCTION_DOCS is false" {
    local script="${FIXTURE_DIR}/undocumented.sh"
    CHECK_FUNCTION_DOCS=false

    cat > "${script}" << 'EOF'
#!/bin/bash
set -euo pipefail
function undocumented {
    echo ok
}
EOF

    run validate_function_docs "${script}"
    [ "$status" -eq 0 ]
}

@test "collect_bats_failures_from_tap records failing tests and summary" {
    local tap_file="${BATS_TEST_TMPDIR}/failures.tap"
    cat > "${tap_file}" << 'TAP'
1..2
not ok 1 broken case
# (in test file scripts/demo.bats, line 10)
ok 2 passes
TAP

    collect_bats_failures_from_tap "${tap_file}"
    [ "${#BATS_FAILED_TESTS[@]}" -eq 1 ]
    [[ ${BATS_FAILED_TESTS[0]} == *"scripts/demo.bats"* ]]
    [[ ${BATS_FAILED_TESTS[0]} == *"broken case"* ]]
    [[ ${BATS_SUMMARY} == *"2 tests, 1 failures"* ]]
}

@test "print_summary_bats_results reports incomplete bats runs" {
    BATS_FAILED_TESTS=()
    BATS_EXIT_CODE=2
    BATS_SUMMARY=""

    run print_summary_bats_results
    [ "$status" -eq 0 ]
    [[ $output == *"did not complete successfully (exit 2)"* ]]
    [[ $output == *"no TAP summary captured"* ]]
}

@test "print_summary_overall_result reports mixed script and bats failures" {
    FAILED_SCRIPTS=1
    BATS_FAILED_TESTS=("scripts/demo.bats: broken")
    BATS_EXIT_CODE=1
    WARNINGS_COUNT=0
    WARNING_SCRIPTS_LIST=()

    run print_summary_overall_result
    [ "$status" -eq 0 ]
    [[ $output == *"Validation failed: 1 script(s) and 1 bats test(s)"* ]]
}

@test "print_summary_overall_result reports incomplete bats when no failures recorded" {
    FAILED_SCRIPTS=0
    BATS_FAILED_TESTS=()
    BATS_EXIT_CODE=3
    WARNINGS_COUNT=0
    WARNING_SCRIPTS_LIST=()

    run print_summary_overall_result
    [ "$status" -eq 0 ]
    [[ $output == *"incomplete bats run (exit 3)"* ]]
}
