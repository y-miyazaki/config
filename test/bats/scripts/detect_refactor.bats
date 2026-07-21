#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .apm/packages/common/.apm/skills/refactor/scripts/detect_refactor.sh
#
# Use cases:
# - detect_refactor.sh emits valid ok JSON with skip when no scan targets match
# - detect_refactor.sh ignores comment-only duplicate blocks (function doc templates)
# - detect_refactor.sh reports duplication_block for repeated line blocks in one file
# - detect_refactor.sh reports duplication_block across files in the scan set
# - detect_refactor.sh reports physical line ranges when blank lines separate blocks
# - detect_refactor.sh prioritizes duplication_block hints before oversized_unit cap
# - detect_refactor.sh reports oversized_unit when file exceeds line threshold
# - detect_refactor.sh scans changed files for range scope with --since
# - detect_refactor.sh returns error JSON for invalid range scope

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    TARGET_SCRIPT="$(apm_skill_script_path refactor detect_refactor.sh)"
    git_test_repo_setup
}

@test "detect_refactor.sh emits valid ok JSON with skip when no scan targets match" {
    git_test_repo_commit "init"

    git_test_repo_run "REFACTOR_SCAN_GLOBS='docs/**' bash '${TARGET_SCRIPT}' --scope all"
    [ "$status" -eq 0 ]
    assert_detect_refactor_ok_json "${output}" "all"
    run jq -e '.skip == true and (.hints | length) == 0' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_refactor.sh ignores comment-only duplicate blocks" {
    mkdir -p "${GIT_TEST_REPO}/scripts"
    cat > "${GIT_TEST_REPO}/scripts/a.sh" << 'EOF'
#!/bin/bash
#######################################
# show_usage: Display script usage information
#
# Arguments:
#   None
#
# Global Variables:
#   None
#
# Returns:
#   Exits with code 0
#
# Usage:
#   show_usage
#
#######################################
function show_usage {
    echo usage_a
}

#######################################
# output_json: Print structured JSON result
#
# Arguments:
#   None
#
# Global Variables:
#   None
#
# Returns:
#   None
#
# Usage:
#   output_json
#
#######################################
function output_json {
    echo json_a
}
EOF
    cat > "${GIT_TEST_REPO}/scripts/b.sh" << 'EOF'
#!/bin/bash
#######################################
# show_usage: Display script usage information
#
# Arguments:
#   None
#
# Global Variables:
#   None
#
# Returns:
#   Exits with code 0
#
# Usage:
#   show_usage
#
#######################################
function show_usage {
    echo usage_b
}

#######################################
# output_json: Print structured JSON result
#
# Arguments:
#   None
#
# Global Variables:
#   None
#
# Returns:
#   None
#
# Usage:
#   output_json
#
#######################################
function output_json {
    echo json_b
}
EOF
    git -C "${GIT_TEST_REPO}" add -A
    git -C "${GIT_TEST_REPO}" commit -q -m "add scripts with identical function doc templates"

    git_test_repo_run "REFACTOR_SCAN_GLOBS='scripts/**' REFACTOR_DUP_MIN_LINES='4' bash '${TARGET_SCRIPT}' --scope all"
    [ "$status" -eq 0 ]
    assert_detect_refactor_ok_json "${output}" "all"
    run jq -e '.skip == true or ([.hints[] | select(.kind == "duplication_block")] | length) == 0' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_refactor.sh reports duplication_block for repeated line blocks in one file" {
    mkdir -p "${GIT_TEST_REPO}/scripts"
    cat > "${GIT_TEST_REPO}/scripts/a.sh" << 'EOF'
#!/bin/bash
run_block() {
    echo one
    echo two
    echo three
    echo four
    echo one
    echo two
    echo three
    echo four
}
EOF
    git -C "${GIT_TEST_REPO}" add -A
    git -C "${GIT_TEST_REPO}" commit -q -m "add duplicate block script"

    git_test_repo_run "REFACTOR_SCAN_GLOBS='scripts/**' REFACTOR_DUP_MIN_LINES='4' bash '${TARGET_SCRIPT}' --scope all"
    [ "$status" -eq 0 ]
    assert_detect_refactor_ok_json "${output}" "all"
    run jq -e '.skip == false and ([.hints[] | select(.kind == "duplication_block")] | length) >= 1' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_refactor.sh reports duplication_block across files in the scan set" {
    mkdir -p "${GIT_TEST_REPO}/scripts"
    cat > "${GIT_TEST_REPO}/scripts/a.sh" << 'EOF'
#!/bin/bash
echo block_line_1
echo block_line_2
echo block_line_3
echo block_line_4
EOF
    cat > "${GIT_TEST_REPO}/scripts/b.sh" << 'EOF'
#!/bin/bash
echo other
echo block_line_1
echo block_line_2
echo block_line_3
echo block_line_4
EOF
    git -C "${GIT_TEST_REPO}" add -A
    git -C "${GIT_TEST_REPO}" commit -q -m "add cross-file duplicate scripts"

    git_test_repo_run "REFACTOR_SCAN_GLOBS='scripts/**' REFACTOR_DUP_MIN_LINES='4' bash '${TARGET_SCRIPT}' --scope all"
    [ "$status" -eq 0 ]
    assert_detect_refactor_ok_json "${output}" "all"
    run jq -e '
        .skip == false
        and ([.hints[] | select(.kind == "duplication_block")] | length) >= 1
        and ([.hints[] | select(.detail | contains("scripts/b.sh"))] | length) >= 1
    ' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_refactor.sh reports physical line ranges when blank lines separate blocks" {
    mkdir -p "${GIT_TEST_REPO}/scripts"
    cat > "${GIT_TEST_REPO}/scripts/a.sh" << 'EOF'
#!/bin/bash
echo one
echo two

echo three
echo four
echo five
echo six
echo seven
echo eight
echo one
echo two

echo three
echo four
echo five
echo six
echo seven
echo eight
EOF
    git -C "${GIT_TEST_REPO}" add -A
    git -C "${GIT_TEST_REPO}" commit -q -m "add duplicate block with blank lines"

    git_test_repo_run "REFACTOR_SCAN_GLOBS='scripts/**' REFACTOR_DUP_MIN_LINES='8' bash '${TARGET_SCRIPT}' --scope all"
    [ "$status" -eq 0 ]
    assert_detect_refactor_ok_json "${output}" "all"
    run jq -e '
        .skip == false
        and ([.hints[] | select(.kind == "duplication_block")] | length) >= 1
        and ([.hints[] | select(.detail | test("lines 2-10 duplicate scripts/a.sh:11-19"))] | length) >= 1
    ' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_refactor.sh prioritizes duplication_block hints before oversized_unit cap" {
    local i
    mkdir -p "${GIT_TEST_REPO}/scripts"
    for i in $(seq 1 25); do
        {
            echo '#!/bin/bash'
            seq 1 15 | sed 's/^/echo line_/'
        } > "${GIT_TEST_REPO}/scripts/big_${i}.sh"
    done
    cat > "${GIT_TEST_REPO}/scripts/dup_a.sh" << 'EOF'
#!/bin/bash
echo shared_1
echo shared_2
echo shared_3
echo shared_4
EOF
    cat > "${GIT_TEST_REPO}/scripts/dup_b.sh" << 'EOF'
#!/bin/bash
echo shared_1
echo shared_2
echo shared_3
echo shared_4
EOF
    git -C "${GIT_TEST_REPO}" add -A
    git -C "${GIT_TEST_REPO}" commit -q -m "add oversized files and cross-file duplication"

    git_test_repo_run "REFACTOR_SCAN_GLOBS='scripts/**' REFACTOR_DUP_MIN_LINES='4' REFACTOR_OVERSIZED_FILE_LINES='10' REFACTOR_MAX_HINTS='5' bash '${TARGET_SCRIPT}' --scope all"
    [ "$status" -eq 0 ]
    assert_detect_refactor_ok_json "${output}" "all"
    run jq -e '
        .skip == false
        and ([.hints[] | select(.kind == "duplication_block")] | length) >= 1
        and ([.hints[0].kind] | index("duplication_block")) != null
    ' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_refactor.sh reports oversized_unit when file exceeds line threshold" {
    mkdir -p "${GIT_TEST_REPO}/scripts"
    {
        echo '#!/bin/bash'
        for i in $(seq 1 20); do
            echo "echo unique_line_${i}"
        done
    } > "${GIT_TEST_REPO}/scripts/big.sh"
    git -C "${GIT_TEST_REPO}" add -A
    git -C "${GIT_TEST_REPO}" commit -q -m "add big script"

    git_test_repo_run "REFACTOR_SCAN_GLOBS='scripts/**' REFACTOR_OVERSIZED_FILE_LINES='10' REFACTOR_DUP_MIN_LINES='50' bash '${TARGET_SCRIPT}' --scope all"
    [ "$status" -eq 0 ]
    assert_detect_refactor_ok_json "${output}" "all"
    run jq -e '.skip == false and ([.hints[] | select(.kind == "oversized_unit")] | length) >= 1' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_refactor.sh scans changed files for range scope with --since" {
    git_test_repo_commit "init"
    local since_sha
    since_sha="$(git -C "${GIT_TEST_REPO}" rev-parse HEAD)"

    mkdir -p "${GIT_TEST_REPO}/scripts"
    cat > "${GIT_TEST_REPO}/scripts/range.sh" << 'EOF'
#!/bin/bash
echo range_1
echo range_2
echo range_3
echo range_4
EOF
    git -C "${GIT_TEST_REPO}" add -A
    git -C "${GIT_TEST_REPO}" commit -q -m "add range script"

    git_test_repo_run "REFACTOR_SCAN_GLOBS='scripts/**' REFACTOR_DUP_MIN_LINES='50' REFACTOR_OVERSIZED_FILE_LINES='2' bash '${TARGET_SCRIPT}' --scope range --since '${since_sha}'"
    [ "$status" -eq 0 ]
    assert_detect_refactor_ok_json "${output}" "range" "${since_sha}"
    run jq -e '
        .skip == false
        and (.commit_range | startswith("'"${since_sha}"'"))
        and ([.hints[] | select(.path == "scripts/range.sh" and .kind == "oversized_unit")] | length) == 1
    ' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_refactor.sh returns error JSON for invalid range scope" {
    git_test_repo_commit "init"

    git_test_repo_run "bash '${TARGET_SCRIPT}' --scope range"
    [ "$status" -eq 0 ]
    assert_detect_refactor_error_json "${output}" "range scope requires --since"
}
