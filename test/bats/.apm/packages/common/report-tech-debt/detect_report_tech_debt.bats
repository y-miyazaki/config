#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .apm/packages/common/.apm/skills/report-tech-debt/scripts/detect_report_tech_debt.sh
#
# Use cases:
# - detect_report_tech_debt defaults to scope all and skips on empty fixture repo
# - detect_report_tech_debt rejects unknown --scope
# - detect_report_tech_debt range without --since returns error JSON exit 0
# - detect_report_tech_debt emits marker and dependency signals
# - detect_report_tech_debt emits broken_doc_ref via markdown-link-check (node+network on first run)
# - detect_report_tech_debt emits stale_doc when TECH_DEBT_STALE_DAYS is zero
# - detect_report_tech_debt emits churn hotspots for frequently edited files
# - detect_report_tech_debt warns and continues when TECH_DEBT_SKIP_MLC=true
# - detect_report_tech_debt emits report_file and previous_report enrich fields
# - detect_report_tech_debt previous_report excludes today's dated report file
# - detect_report_tech_debt honors REPORT_TECH_DEBT_DIR for report_file path
# - detect_report_tech_debt previous_report falls back to legacy tech-debt directory
# - detect_report_tech_debt accepts --scope staged for loop-detect parity
# - detect_report_tech_debt truncates dependency signals when dep cap is reached

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

DETECT_SCRIPT="$(apm_skill_script_path report-tech-debt detect_report_tech_debt.sh)"

@test "detect_report_tech_debt accepts --scope staged and returns ok JSON" {
    git_test_repo_setup
    mkdir -p "${GIT_TEST_REPO}/src"
    printf 'package main\n// TODO: staged scope\nfunc main() {}\n' > "${GIT_TEST_REPO}/src/app.go"
    git -C "${GIT_TEST_REPO}" add .
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    git_test_repo_run "bash '${DETECT_SCRIPT}' --scope staged"
    [ "$status" -eq 0 ]
    assert_detect_report_tech_debt_ok_json "${output}" "staged" ""
}

@test "detect_report_tech_debt defaults to scope all and skips on empty fixture repo" {
    git_test_repo_setup
    printf 'ok\n' > "${GIT_TEST_REPO}/README.md"
    git -C "${GIT_TEST_REPO}" add README.md
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    git_test_repo_run "bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    assert_detect_report_tech_debt_ok_json "${output}" "all" ""
    [[ $output == *'"skip": true'* ]]
}

@test "detect_report_tech_debt excludes marker signals under report parent directory" {
    git_test_repo_setup
    mkdir -p "${GIT_TEST_REPO}/docs/report/report-tech-debt" "${GIT_TEST_REPO}/src"
    printf 'package main\n// TODO: report noise\nfunc main() {}\n' \
        > "${GIT_TEST_REPO}/docs/report/report-tech-debt/noise.go"
    printf 'package main\n// TODO: app debt\nfunc main() {}\n' \
        > "${GIT_TEST_REPO}/src/app.go"
    git -C "${GIT_TEST_REPO}" add .
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    git_test_repo_run "env TECH_DEBT_SKIP_MLC=true bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    [[ $output == *'"todo_comment"'* ]]
    [[ $output == *'src/app.go'* ]]
    [[ $output != *'docs/report/report-tech-debt/noise.go'* ]]
}

@test "detect_report_tech_debt emits broken_doc_ref for missing relative markdown link" {
    git_test_repo_setup
    mkdir -p "${GIT_TEST_REPO}/docs"
    printf '# Doc\n\nSee [missing](./nope.md)\n' > "${GIT_TEST_REPO}/docs/index.md"
    git -C "${GIT_TEST_REPO}" add .
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    git_test_repo_run "bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    assert_detect_report_tech_debt_ok_json "${output}" "all" ""
    [[ $output == *'"broken_doc_ref"'* ]] || [[ $output == *'docs link sensor skipped'* ]]
}

@test "detect_report_tech_debt emits churn hotspot for frequently edited file" {
    git_test_repo_setup
    printf 'v1\n' > "${GIT_TEST_REPO}/hot.txt"
    git -C "${GIT_TEST_REPO}" add hot.txt
    git -C "${GIT_TEST_REPO}" commit -q -m "c1"
    local i
    for i in 2 3 4 5 6; do
        echo "v${i}" >> "${GIT_TEST_REPO}/hot.txt"
        git -C "${GIT_TEST_REPO}" add hot.txt
        git -C "${GIT_TEST_REPO}" commit -q -m "c${i}"
    done
    git_test_repo_run "env TECH_DEBT_CHURN_MIN=5 TECH_DEBT_CHURN_WINDOW=365d TECH_DEBT_SKIP_MLC=true bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    [[ $output == *'"metric": "churn"'* ]] || [[ $output == *'"metric":"churn"'* ]]
    [[ $output == *'hot.txt'* ]]
}

@test "detect_report_tech_debt emits eol_hint when TECH_DEBT_EOL_MODULES matches go.mod require" {
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

@test "detect_report_tech_debt emits stale_doc when TECH_DEBT_STALE_DAYS is zero" {
    git_test_repo_setup
    mkdir -p "${GIT_TEST_REPO}/docs"
    printf '# Old\n' > "${GIT_TEST_REPO}/docs/old.md"
    git -C "${GIT_TEST_REPO}" add .
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    git_test_repo_run "env TECH_DEBT_STALE_DAYS=0 TECH_DEBT_SKIP_MLC=true bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    [[ $output == *'"stale_doc"'* ]]
}

@test "detect_report_tech_debt emits todo_comment and fixme marker signals" {
    git_test_repo_setup
    mkdir -p "${GIT_TEST_REPO}/src"
    printf 'package main\n// TODO: extract helper\n// FIXME: handle nil\nfunc main() {}\n' \
        > "${GIT_TEST_REPO}/src/main.go"
    git -C "${GIT_TEST_REPO}" add .
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    git_test_repo_run "bash '${DETECT_SCRIPT}' --scope all"
    [ "$status" -eq 0 ]
    assert_detect_report_tech_debt_ok_json "${output}" "all" ""
    [[ $output == *'"skip": false'* ]]
    [[ $output == *'"todo_comment"'* ]]
    [[ $output == *'"fixme"'* ]]
}

@test "detect_report_tech_debt emits version_range for caret dependency in package.json" {
    git_test_repo_setup
    printf '%s\n' '{"name":"x","dependencies":{"leftpad":"^1.0.0"}}' \
        > "${GIT_TEST_REPO}/package.json"
    git -C "${GIT_TEST_REPO}" add package.json
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    git_test_repo_run "bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    [[ $output == *'"version_range"'* ]]
}

@test "detect_report_tech_debt keeps dependency signals when marker cap is reached" {
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

@test "detect_report_tech_debt previous_report empty on fresh repo" {
    git_test_repo_setup
    printf 'ok\n' > "${GIT_TEST_REPO}/README.md"
    git -C "${GIT_TEST_REPO}" add README.md
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    git_test_repo_run "bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    assert_detect_report_tech_debt_ok_json "${output}" "all" ""
    [[ $output == *'"previous_report": ""'* ]] || [[ $output == *'"previous_report":""'* ]]
}

@test "detect_report_tech_debt honors REPORT_TECH_DEBT_DIR for report_file path" {
    git_test_repo_setup
    local today_date
    today_date="$(date -u +%Y-%m-%d)"
    mkdir -p "${GIT_TEST_REPO}/reports/custom-debt" "${GIT_TEST_REPO}/src"
    printf 'package main\n// TODO: debt\nfunc main() {}\n' > "${GIT_TEST_REPO}/src/app.go"
    git -C "${GIT_TEST_REPO}" add .
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    git_test_repo_run "env REPORT_TECH_DEBT_DIR='reports/custom-debt' REPORT_TECH_DEBT_LEGACY_SEARCH_DIRS='' TECH_DEBT_SKIP_MLC=true bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    [[ $output == *"\"report_file\": \"reports/custom-debt/${today_date}.md\""* ]] \
        || [[ $output == *"\"report_file\":\"reports/custom-debt/${today_date}.md\""* ]]
}

@test "detect_report_tech_debt previous_report excludes today's dated report file" {
    git_test_repo_setup
    local today_date older_report
    today_date="$(date -u +%Y-%m-%d)"
    older_report="docs/report/report-tech-debt/2020-01-01.md"
    mkdir -p "${GIT_TEST_REPO}/docs/report/report-tech-debt"
    printf '# today\n' > "${GIT_TEST_REPO}/docs/report/report-tech-debt/${today_date}.md"
    printf '# older\n' > "${GIT_TEST_REPO}/${older_report}"
    printf 'ok\n' > "${GIT_TEST_REPO}/README.md"
    git -C "${GIT_TEST_REPO}" add .
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    git_test_repo_run "bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    assert_detect_report_tech_debt_ok_json "${output}" "all" ""
    [[ $output == *"\"previous_report\": \"${older_report}\""* ]] \
        || [[ $output == *"\"previous_report\":\"${older_report}\""* ]]
    [[ $output != *"\"previous_report\": \"docs/report/report-tech-debt/${today_date}.md\""* ]]
    [[ $output != *"\"previous_report\":\"docs/report/report-tech-debt/${today_date}.md\""* ]]
}

@test "detect_report_tech_debt previous_report falls back to legacy tech-debt directory" {
    git_test_repo_setup
    local today_date legacy_report
    today_date="$(date -u +%Y-%m-%d)"
    legacy_report="docs/report/tech-debt/2020-06-01.md"
    mkdir -p "${GIT_TEST_REPO}/docs/report/tech-debt"
    printf '# legacy\n' > "${GIT_TEST_REPO}/${legacy_report}"
    printf 'ok\n' > "${GIT_TEST_REPO}/README.md"
    git -C "${GIT_TEST_REPO}" add .
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    git_test_repo_run "bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    assert_detect_report_tech_debt_ok_json "${output}" "all" ""
    [[ $output == *"\"previous_report\": \"${legacy_report}\""* ]] \
        || [[ $output == *"\"previous_report\":\"${legacy_report}\""* ]]
    [[ $output == *"\"report_file\": \"docs/report/report-tech-debt/${today_date}.md\""* ]] \
        || [[ $output == *"\"report_file\":\"docs/report/report-tech-debt/${today_date}.md\""* ]]
}

@test "detect_report_tech_debt previous_report picks latest dated md when older reports exist" {
    git_test_repo_setup
    mkdir -p "${GIT_TEST_REPO}/docs/report/report-tech-debt"
    printf '# older\n' > "${GIT_TEST_REPO}/docs/report/report-tech-debt/2020-01-01.md"
    printf '# newer\n' > "${GIT_TEST_REPO}/docs/report/report-tech-debt/2021-06-15.md"
    printf 'ok\n' > "${GIT_TEST_REPO}/README.md"
    git -C "${GIT_TEST_REPO}" add .
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    git_test_repo_run "bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    assert_detect_report_tech_debt_ok_json "${output}" "all" ""
    [[ $output == *'"previous_report": "docs/report/report-tech-debt/2021-06-15.md"'* ]] \
        || [[ $output == *'"previous_report":"docs/report/report-tech-debt/2021-06-15.md"'* ]]
}

@test "detect_report_tech_debt range without --since returns error JSON exit 0" {
    git_test_repo_setup
    touch "${GIT_TEST_REPO}/file.txt"
    git -C "${GIT_TEST_REPO}" add file.txt
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    git_test_repo_run "bash '${DETECT_SCRIPT}' --scope range"
    [ "$status" -eq 0 ]
    assert_detect_report_tech_debt_error_json "${output}" "requires --since"
}

@test "detect_report_tech_debt rejects unknown --scope" {
    git_test_repo_setup
    touch "${GIT_TEST_REPO}/file.txt"
    git -C "${GIT_TEST_REPO}" add file.txt
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    git_test_repo_run "bash '${DETECT_SCRIPT}' --scope weird"
    [ "$status" -eq 0 ]
    assert_detect_report_tech_debt_error_json "${output}" "scope"
}

@test "detect_report_tech_debt report_file matches UTC date pattern" {
    git_test_repo_setup
    printf 'ok\n' > "${GIT_TEST_REPO}/README.md"
    git -C "${GIT_TEST_REPO}" add README.md
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    local expected_date
    expected_date="$(date -u +%Y-%m-%d)"
    git_test_repo_run "bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    assert_detect_report_tech_debt_ok_json "${output}" "all" ""
    [[ $output == *"\"report_file\": \"docs/report/report-tech-debt/${expected_date}.md\""* ]] \
        || [[ $output == *"\"report_file\":\"docs/report/report-tech-debt/${expected_date}.md\""* ]]
}

@test "detect_report_tech_debt returns error when not inside a git repository" {
    local no_git_dir="${BATS_TEST_TMPDIR}/no-git"
    mkdir -p "${no_git_dir}"
    run bash -c "cd '${no_git_dir}' && bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    assert_detect_report_tech_debt_error_json "${output}" "Not a git repository"
}

@test "detect_report_tech_debt stale_doc uses mtime source when only mtime exceeds threshold" {
    git_test_repo_setup
    mkdir -p "${GIT_TEST_REPO}/docs"
    printf '# Old\n' > "${GIT_TEST_REPO}/docs/old.md"
    git -C "${GIT_TEST_REPO}" add .
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    touch -d "2 years ago" "${GIT_TEST_REPO}/docs/old.md"
    git_test_repo_run "env TECH_DEBT_STALE_DAYS=30 TECH_DEBT_SKIP_MLC=true bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    [[ $output == *'"stale_doc"'* ]]
    [[ $output == *'"source": "mtime"'* ]] || [[ $output == *'"source":"mtime"'* ]]
    [[ $output == *'(mtime)'* ]]
}

@test "detect_report_tech_debt truncates dependency signals when dep cap is reached" {
    git_test_repo_setup
    local dep_idx
    {
        printf '{\n  "name": "dep-cap-test",\n  "dependencies": {\n'
        for dep_idx in $(seq 0 54); do
            printf '    "pkg%d": "^1.0.0"' "${dep_idx}"
            if [[ ${dep_idx} -lt 54 ]]; then
                printf ',\n'
            else
                printf '\n'
            fi
        done
        printf '  }\n}\n'
    } > "${GIT_TEST_REPO}/package.json"
    git -C "${GIT_TEST_REPO}" add package.json
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    git_test_repo_run "env TECH_DEBT_SKIP_MLC=true bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    [[ $output == *'"dependency signals truncated"'* ]]
    [[ $output == *'"version_range"'* ]]
}

@test "detect_report_tech_debt warns and continues when TECH_DEBT_SKIP_MLC=true" {
    git_test_repo_setup
    printf '# x\n' > "${GIT_TEST_REPO}/README.md"
    git -C "${GIT_TEST_REPO}" add .
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    git_test_repo_run "env TECH_DEBT_SKIP_MLC=true bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    [[ $output == *'"warnings"'* ]]
}
