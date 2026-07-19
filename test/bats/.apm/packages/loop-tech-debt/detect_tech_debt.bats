#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .apm/packages/loop-tech-debt/.apm/skills/loop-tech-debt/scripts/detect_tech_debt.sh
#
# Use cases:
# - detect_tech_debt defaults to scope all and skips on empty fixture repo
# - detect_tech_debt rejects unknown --scope
# - detect_tech_debt range without --since returns error JSON exit 0
# - detect_tech_debt emits marker and dependency signals

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

DETECT_SCRIPT="$(apm_skill_script_path loop-tech-debt detect_tech_debt.sh)"

@test "detect_tech_debt defaults to scope all and skips on empty fixture repo" {
    git_test_repo_setup
    printf 'ok\n' > "${GIT_TEST_REPO}/README.md"
    git -C "${GIT_TEST_REPO}" add README.md
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    git_test_repo_run "bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    assert_detect_tech_debt_ok_json "${output}" "all" ""
    [[ $output == *'"skip": true'* ]]
}

@test "detect_tech_debt emits eol_hint when TECH_DEBT_EOL_MODULES matches go.mod require" {
    git_test_repo_setup
    cat > "${GIT_TEST_REPO}/go.mod" << 'EOF'
module example.com/app

go 1.22

require github.com/old/lib v1.2.3
EOF
    git -C "${GIT_TEST_REPO}/" add go.mod
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    git_test_repo_run "env TECH_DEBT_EOL_MODULES='github.com/old/lib' bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    [[ $output == *'"eol_hint"'* ]]
}

@test "detect_tech_debt emits todo_comment and fixme marker signals" {
    git_test_repo_setup
    mkdir -p "${GIT_TEST_REPO}/src"
    printf 'package main\n// TODO: extract helper\n// FIXME: handle nil\nfunc main() {}\n' \
        > "${GIT_TEST_REPO}/src/main.go"
    git -C "${GIT_TEST_REPO}" add .
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    git_test_repo_run "bash '${DETECT_SCRIPT}' --scope all"
    [ "$status" -eq 0 ]
    assert_detect_tech_debt_ok_json "${output}" "all" ""
    [[ $output == *'"skip": false'* ]]
    [[ $output == *'"todo_comment"'* ]]
    [[ $output == *'"fixme"'* ]]
}

@test "detect_tech_debt emits version_range for caret dependency in package.json" {
    git_test_repo_setup
    printf '%s\n' '{"name":"x","dependencies":{"leftpad":"^1.0.0"}}' \
        > "${GIT_TEST_REPO}/package.json"
    git -C "${GIT_TEST_REPO}" add package.json
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    git_test_repo_run "bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    [[ $output == *'"version_range"'* ]]
}

@test "detect_tech_debt range without --since returns error JSON exit 0" {
    git_test_repo_setup
    touch "${GIT_TEST_REPO}/file.txt"
    git -C "${GIT_TEST_REPO}" add file.txt
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    git_test_repo_run "bash '${DETECT_SCRIPT}' --scope range"
    [ "$status" -eq 0 ]
    assert_detect_tech_debt_error_json "${output}" "requires --since"
}

@test "detect_tech_debt rejects unknown --scope" {
    git_test_repo_setup
    touch "${GIT_TEST_REPO}/file.txt"
    git -C "${GIT_TEST_REPO}" add file.txt
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    git_test_repo_run "bash '${DETECT_SCRIPT}' --scope weird"
    [ "$status" -eq 0 ]
    assert_detect_tech_debt_error_json "${output}" "scope"
}

@test "detect_tech_debt keeps dependency signals when marker cap is reached" {
    git_test_repo_setup
    mkdir -p "${GIT_TEST_REPO}/src"
    local file_idx todo_idx
    for file_idx in $(seq 1 6); do
        {
            printf 'package main\n'
            for todo_idx in $(seq 1 10); do
                printf '// TODO: marker %s-%s\n' "${file_idx}" "${todo_idx}"
            done
            printf 'func main() {}\n'
        } > "${GIT_TEST_REPO}/src/file${file_idx}.go"
    done
    cat > "${GIT_TEST_REPO}/go.mod" << 'EOF'
module example.com/app

go 1.22

require github.com/old/lib v1.2.3
EOF
    git -C "${GIT_TEST_REPO}" add .
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    git_test_repo_run "env TECH_DEBT_EOL_MODULES='github.com/old/lib' bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    [[ $output == *'"marker signals truncated"'* ]]
    [[ $output == *'"eol_hint"'* ]]
}
