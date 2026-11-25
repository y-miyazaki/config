#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2154

# Tests for scripts/go/validate.sh
#
# Use cases:
# - --changed-only needs no golangci-lint when no go file changed
# - without --changed-only a missing golangci-lint is still reported
# - determine_target_pattern fails for a missing directory instead of validating the whole repository
# - determine_target_pattern fails for a scoped directory without Go files
# - determine_target_pattern does not prefix ./ to an absolute directory
# - determine_target_pattern keeps ./... and accepts a scoped directory that contains Go files
# - determine_changed_patterns emits one package pattern per directory with changed .go files, grouped by module
# - determine_changed_patterns honors the scope directory, skips testdata and files without a go.mod
# - determine_changed_patterns emits the module pattern ./... when go.mod or go.sum changed
# - determine_changed_patterns keeps dot-prefixed directories when the module root is .
# - run_changed_modules checks only packages with applicable go files and merges to ./... for a whole-module pattern
# - run_changed_modules skips a module without applicable go files
# - run_changed_modules does not attribute a coverage warning to a later module whose coverage run failed
# - run_changed_modules totals lint and test failures and keeps the lowest coverage across modules
# - run_changed_modules checks the unfiltered patterns when go list fails
# - determine_changed_patterns selects a surviving package for a removed file and the whole module for a removed package
# - run_go_build skips packages with only test files when CHANGED_ONLY is true
# - run_go_build builds the unfiltered patterns and fails when go list fails
# - --changed-only exits 0 without checking when no .go file changed
# - show_usage documents the optional directory argument

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

VALIDATE_SCRIPT="$(bats_workspace_root)/scripts/go/validate.sh"

setup() {
    WORK_DIR="${BATS_TEST_TMPDIR}/work"
    mkdir -p "${WORK_DIR}/empty" "${WORK_DIR}/pkg dir"
    echo 'package x' > "${WORK_DIR}/pkg dir/a.go"
    echo 'package root' > "${WORK_DIR}/root.go"
}

@test "--changed-only exits 0 without checking when no go file changed" {
    bats_git_fresh_repo "${WORK_DIR}/repo"
    echo 'x' > "${WORK_DIR}/repo/readme.md"
    bats_git_commit "${WORK_DIR}/repo" init
    run bash -c "cd '${WORK_DIR}/repo' && '${VALIDATE_SCRIPT}' --changed-only"
    [ "$status" -eq 0 ]
    [[ $output != *"Running go build"* ]]
    [[ $output == *"VALIDATION_RESULT tool=go status=PASS"* ]]
}

@test "--changed-only needs no golangci-lint when no go file changed" {
    bats_git_fresh_repo "${WORK_DIR}/repo"
    echo 'x' > "${WORK_DIR}/repo/readme.md"
    bats_git_commit "${WORK_DIR}/repo" init
    # A system-only PATH models a CI runner without golangci-lint; git and bash must still resolve
    run env PATH=/usr/bin:/bin bash -c "command -v golangci-lint"
    if [[ $status -eq 0 ]]; then
        skip "golangci-lint is installed in a system directory"
    fi
    local tool
    for tool in git bash date; do
        run env PATH=/usr/bin:/bin bash -c "command -v ${tool}"
        [ "$status" -eq 0 ]
    done
    run env PATH=/usr/bin:/bin bash -c "cd '${WORK_DIR}/repo' && '${VALIDATE_SCRIPT}' --changed-only"
    [ "$status" -eq 0 ]
    [[ $output == *"VALIDATION_RESULT tool=go status=PASS"* ]]
}

@test "without --changed-only a missing golangci-lint is still reported" {
    run env PATH=/usr/bin:/bin bash -c "command -v golangci-lint"
    if [[ $status -eq 0 ]]; then
        skip "golangci-lint is installed in a system directory"
    fi
    run env PATH=/usr/bin:/bin bash -c "cd '${WORK_DIR}' && '${VALIDATE_SCRIPT}'"
    [ "$status" -ne 0 ]
    [[ $output == *"Missing required tools"* ]]
}

@test "determine_changed_patterns emits one package pattern per directory with changed go files, grouped by module" {
    local repo="${WORK_DIR}/repo"
    bats_git_fresh_repo "${repo}"
    mkdir -p "${repo}/cmd/a" "${repo}/pkg dir" "${repo}/other" "${repo}/nested/sub"
    echo 'module m' > "${repo}/go.mod"
    echo 'module n' > "${repo}/nested/go.mod"
    echo 'package a' > "${repo}/cmd/a/a.go"
    echo 'package a' > "${repo}/cmd/a/b.go"
    echo 'package x' > "${repo}/pkg dir/x.go"
    echo 'package r' > "${repo}/root.go"
    echo 'package o' > "${repo}/other/o.go"
    echo 'package s' > "${repo}/nested/sub/s.go"
    echo 'package n' > "${repo}/nested/n.go"
    bats_git_commit "${repo}" init
    for f in cmd/a/a.go cmd/a/b.go "pkg dir/x.go" root.go nested/sub/s.go nested/n.go; do echo '// c' >> "${repo}/${f}"; done
    run bash -c "cd '${repo}' && source '${VALIDATE_SCRIPT}' && determine_changed_patterns"
    [ "$status" -eq 0 ]
    [ "$output" = $'.\t.\n.\t./cmd/a\n.\t./pkg dir\nnested\t.\nnested\t./sub' ]
}

@test "determine_changed_patterns emits the module pattern ./... when go.mod or go.sum changed" {
    local repo="${WORK_DIR}/repo"
    bats_git_fresh_repo "${repo}"
    mkdir -p "${repo}/mod/sub"
    echo 'module m' > "${repo}/go.mod"
    echo 'module n' > "${repo}/mod/go.mod"
    echo 'package s' > "${repo}/mod/sub/s.go"
    bats_git_commit "${repo}" init
    echo '// c' >> "${repo}/mod/go.sum"
    run bash -c "cd '${repo}' && source '${VALIDATE_SCRIPT}' && determine_changed_patterns"
    [ "$status" -eq 0 ]
    [ "$output" = $'mod\t./...' ]
}

@test "determine_changed_patterns honors the scope directory, skips testdata and files without a go.mod" {
    local repo="${WORK_DIR}/repo"
    bats_git_fresh_repo "${repo}"
    mkdir -p "${repo}/cmd/a" "${repo}/cmd/testdata" "${repo}/other" "${repo}/nomod"
    echo 'module m' > "${repo}/go.mod"
    echo 'package a' > "${repo}/cmd/a/a.go"
    echo 'package t' > "${repo}/cmd/testdata/t.go"
    echo 'package o' > "${repo}/other/o.go"
    run bash -c "cd '${repo}' && source '${VALIDATE_SCRIPT}' && determine_changed_patterns ./cmd"
    [ "$status" -eq 0 ]
    [ "$output" = $'.\t./cmd/a' ]

    rm "${repo}/go.mod"
    run bash -c "cd '${repo}' && source '${VALIDATE_SCRIPT}' && determine_changed_patterns 2>/dev/null"
    [ -z "$output" ]
}

@test "determine_changed_patterns keeps dot-prefixed directories when the module root is ." {
    local repo="${WORK_DIR}/repo"
    bats_git_fresh_repo "${repo}"
    mkdir -p "${repo}/.github/tool"
    echo 'module m' > "${repo}/go.mod"
    bats_git_commit "${repo}" init
    echo 'package t' > "${repo}/.github/tool/t.go"
    run bash -c "cd '${repo}' && source '${VALIDATE_SCRIPT}' && determine_changed_patterns"
    [ "$status" -eq 0 ]
    [ "$output" = $'.\t./.github/tool' ]
}

@test "determine_changed_patterns selects a surviving package for a removed file and the whole module for a removed package" {
    local repo="${WORK_DIR}/repo"
    bats_git_fresh_repo "${repo}"
    mkdir -p "${repo}/keep" "${repo}/gone"
    echo 'module m' > "${repo}/go.mod"
    echo 'package k' > "${repo}/keep/k.go"
    echo 'package k' > "${repo}/keep/k_test.go"
    echo 'package g' > "${repo}/gone/g.go"
    bats_git_commit "${repo}" init
    rm "${repo}/keep/k.go"
    run bash -c "cd '${repo}' && source '${VALIDATE_SCRIPT}' && determine_changed_patterns"
    [ "$status" -eq 0 ]
    [ "$output" = $'.\t./keep' ]
    rm -r "${repo}/gone"
    run bash -c "cd '${repo}' && source '${VALIDATE_SCRIPT}' && determine_changed_patterns"
    [ "$output" = $'.\t./...\n.\t./keep' ]
}

@test "determine_target_pattern fails for a missing directory instead of validating the whole repository" {
    run bash -c "cd '${WORK_DIR}' && source '${VALIDATE_SCRIPT}' && determine_target_pattern missing"
    [ "$status" -ne 0 ]
    [[ $output == *"Directory not found: missing"* ]]
}

@test "determine_target_pattern fails for a scoped directory without Go files" {
    run bash -c "cd '${WORK_DIR}' && source '${VALIDATE_SCRIPT}' && determine_target_pattern empty"
    [ "$status" -ne 0 ]
    [[ $output == *"No Go files found in empty"* ]]
}

@test "determine_target_pattern keeps ./... and accepts a scoped directory that contains Go files" {
    run bash -c "cd '${WORK_DIR}' && source '${VALIDATE_SCRIPT}' && determine_target_pattern './...'"
    [ "$status" -eq 0 ]
    [ "$output" = "./..." ]

    run bash -c "cd '${WORK_DIR}' && source '${VALIDATE_SCRIPT}' && determine_target_pattern 'pkg dir'"
    [ "$status" -eq 0 ]
    [ "$output" = "./pkg dir/..." ]
}

@test "run_changed_modules checks only packages with applicable go files and merges to ./... for a whole-module pattern" {
    local repo="${WORK_DIR}/repo"
    mkdir -p "${repo}/a" "${repo}/ign" "${repo}/only_test" "${repo}/nested/b"
    printf 'module m\n\ngo 1.21\n' > "${repo}/go.mod"
    printf 'module n\n\ngo 1.21\n' > "${repo}/nested/go.mod"
    printf 'package a\n' > "${repo}/a/a.go"
    printf '//go:build ignore\n\npackage ign\n' > "${repo}/ign/i.go"
    printf 'package ot\n' > "${repo}/only_test/o_test.go"
    printf 'package b\n' > "${repo}/nested/b/b.go"
    run bash -c "cd '${repo}' && source '${VALIDATE_SCRIPT}' && run_checks() { echo \"RUN \$PWD :: \${TARGET_PATTERNS[*]}\"; } && run_changed_modules \$'.\t./a' \$'.\t./ign' \$'.\t./only_test' \$'nested\t./...'"
    [ "$status" -eq 0 ]
    [[ $output == *"RUN ${repo} :: ./a ./only_test"* ]]
    [[ $output == *"RUN ${repo}/nested :: ./..."* ]]
    [[ $output != *"ign"* ]]
}

@test "run_changed_modules checks the unfiltered patterns when go list fails" {
    local repo="${WORK_DIR}/repo"
    mkdir -p "${repo}/a"
    printf 'this is not a go.mod\n' > "${repo}/go.mod"
    printf 'package a\n' > "${repo}/a/a.go"
    run bash -c "cd '${repo}' && source '${VALIDATE_SCRIPT}' && run_checks() { echo \"RUN \${TARGET_PATTERNS[*]}\"; } && run_changed_modules \$'.\t./a'"
    [ "$status" -eq 0 ]
    [[ $output == *"RUN ./a"* ]]
}

@test "run_changed_modules does not attribute a coverage warning to a later module whose coverage run failed" {
    local repo="${WORK_DIR}/repo"
    mkdir -p "${repo}/a" "${repo}/nested/b"
    printf 'module m\n\ngo 1.21\n' > "${repo}/go.mod"
    printf 'module n\n\ngo 1.21\n' > "${repo}/nested/go.mod"
    printf 'package a\n' > "${repo}/a/a.go"
    printf 'package b\n' > "${repo}/nested/b/b.go"
    run bash -c "cd '${repo}' && source '${VALIDATE_SCRIPT}' && n=0 && run_checks() { n=\$((n+1)); if [ \$n = 1 ]; then COVERAGE_PERCENT=50; COVERAGE_FAILED=1; fi; } && run_changed_modules \$'.\t./a' \$'nested\t./b' && echo \"C=[\$COVERAGE_PERCENT] F=\$COVERAGE_FAILED\""
    [ "$status" -eq 0 ]
    [[ $output == *"C=[50] F=1"* ]]
}

@test "run_changed_modules skips a module without applicable go files" {
    local repo="${WORK_DIR}/repo"
    mkdir -p "${repo}/ign"
    printf 'module m\n\ngo 1.21\n' > "${repo}/go.mod"
    printf '//go:build ignore\n\npackage ign\n' > "${repo}/ign/i.go"
    run bash -c "cd '${repo}' && source '${VALIDATE_SCRIPT}' && run_checks() { echo RAN; } && run_changed_modules \$'.\t./ign'"
    [ "$status" -eq 0 ]
    [[ $output != *"RAN"* ]]
}

@test "run_changed_modules totals lint and test failures and keeps the lowest coverage across modules" {
    local repo="${WORK_DIR}/repo"
    mkdir -p "${repo}/a" "${repo}/nested/b"
    printf 'module m\n\ngo 1.21\n' > "${repo}/go.mod"
    printf 'module n\n\ngo 1.21\n' > "${repo}/nested/go.mod"
    printf 'package a\n' > "${repo}/a/a.go"
    printf 'package b\n' > "${repo}/nested/b/b.go"
    run bash -c "cd '${repo}' && source '${VALIDATE_SCRIPT}' && n=0 && run_checks() { n=\$((n+1)); if [ \$n = 1 ]; then LINT_ISSUES_COUNT=2; TEST_FAIL_COUNT=3; COVERAGE_PERCENT=50; COVERAGE_FAILED=1; else LINT_ISSUES_COUNT=1; TEST_FAIL_COUNT=0; COVERAGE_PERCENT=95; fi; } && run_changed_modules \$'.\t./a' \$'nested\t./b' && echo \"L=\$LINT_ISSUES_COUNT T=\$TEST_FAIL_COUNT C=\$COVERAGE_PERCENT\""
    [ "$status" -eq 0 ]
    [[ $output == *"L=3 T=3 C=50"* ]]
}

@test "run_go_build builds the unfiltered patterns and fails when go list fails" {
    local repo="${WORK_DIR}/repo"
    mkdir -p "${repo}/a"
    printf 'this is not a go.mod\n' > "${repo}/go.mod"
    printf 'package a\n' > "${repo}/a/a.go"
    run bash -c "cd '${repo}' && source '${VALIDATE_SCRIPT}' && CHANGED_ONLY=true && TARGET_PATTERNS=(./a) && run_go_build 2>/dev/null; echo \"FAILED=\$GO_BUILD_FAILED\""
    [[ $output == *"FAILED=1"* ]]
}

@test "run_go_build skips packages with only test files when CHANGED_ONLY is true" {
    local repo="${WORK_DIR}/repo"
    mkdir -p "${repo}/onlytest" "${repo}/real"
    printf 'module m\n\ngo 1.21\n' > "${repo}/go.mod"
    printf 'package onlytest\n' > "${repo}/onlytest/a_test.go"
    printf 'package real\n' > "${repo}/real/r.go"
    run bash -c "cd '${repo}' && source '${VALIDATE_SCRIPT}' && CHANGED_ONLY=true && TARGET_PATTERNS=(./onlytest) && run_go_build && [ \"\$GO_BUILD_FAILED\" = 0 ]"
    [ "$status" -eq 0 ]
    run bash -c "cd '${repo}' && source '${VALIDATE_SCRIPT}' && CHANGED_ONLY=true && TARGET_PATTERNS=(./onlytest ./real) && run_go_build && [ \"\$GO_BUILD_FAILED\" = 0 ]"
    [ "$status" -eq 0 ]
}

@test "show_usage documents the optional directory argument" {
    run bash "${VALIDATE_SCRIPT}" --help
    [ "$status" -eq 0 ]
    [[ $output == *"[options] [directory]"* ]]
}

@test "determine_target_pattern does not prefix ./ to an absolute directory" {
    run bash -c "cd '${WORK_DIR}' && source '${VALIDATE_SCRIPT}' && determine_target_pattern '${WORK_DIR}/pkg dir'"
    [ "$status" -eq 0 ]
    [ "$output" = "${WORK_DIR}/pkg dir/..." ]
}
