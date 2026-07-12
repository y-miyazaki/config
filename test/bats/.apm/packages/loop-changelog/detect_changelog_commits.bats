#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .apm/packages/loop-changelog/.apm/skills/loop-changelog/scripts/detect_changelog_commits.sh

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

DETECT_SCRIPT="$(apm_skill_script_path loop-changelog detect_changelog_commits.sh)"

setup() {
    bats_source_apm_skill loop-changelog detect_changelog_commits.sh
}

@test "parse_commit_subject accepts conventional feat commit" {
    local commit_type="" scope="" breaking="" rest=""
    parse_commit_subject "feat(api): add endpoint" commit_type scope breaking rest
    [ "${commit_type}" = "feat" ]
    [ "${scope}" = "api" ]
    [ "${rest}" = "add endpoint" ]
    [ "${breaking}" = "false" ]
}

@test "parse_commit_subject accepts renovate prefix" {
    local commit_type="" scope="" breaking="" rest=""
    parse_commit_subject "renovate(mise): update pnpm" commit_type scope breaking rest
    [ "${commit_type}" = "renovate" ]
    [ "${scope}" = "mise" ]
}

@test "parse_commit_subject accepts chore deps scope" {
    local commit_type="" scope="" breaking="" rest=""
    parse_commit_subject "chore(deps): bump lodash" commit_type scope breaking rest
    [ "${commit_type}" = "chore" ]
    [ "${scope}" = "deps" ]
}

@test "parse_commit_subject rejects plain message" {
    local commit_type="" scope="" breaking="" rest=""
    run parse_commit_subject "update something" commit_type scope breaking rest
    [ "$status" -eq 1 ]
}

@test "parse_commit_subject marks breaking header" {
    local commit_type="" scope="" breaking="" rest=""
    parse_commit_subject "feat!: drop legacy api" commit_type scope breaking rest
    [ "${commit_type}" = "feat" ]
    [ "${breaking}" = "true" ]
}

@test "is_loop_maintenance_commit skips chore changelog scope" {
    run is_loop_maintenance_commit "chore" "changelog" "update CHANGELOG.md (loop-changelog)"
    [ "$status" -eq 0 ]
}

@test "is_loop_maintenance_commit skips subject with loop-changelog marker" {
    run is_loop_maintenance_commit "fix" "docs" "tweak wording (loop-changelog)"
    [ "$status" -eq 0 ]
}

@test "is_loop_maintenance_commit allows regular feat commits" {
    run is_loop_maintenance_commit "feat" "api" "add endpoint"
    [ "$status" -eq 1 ]
}

@test "detect_changelog_commits range scope returns feat commit" {
    git_test_repo_setup
    touch "${GIT_TEST_REPO}/file.txt"
    git_test_repo_commit "chore: init"
    local base
    base="$(git -C "${GIT_TEST_REPO}" rev-parse HEAD)"
    git_test_repo_commit "feat(api): add endpoint"
    git_test_repo_run "bash '${DETECT_SCRIPT}' --scope range --since '${base}'"
    [ "$status" -eq 0 ]
    [[ $output == *'"status": "ok"'* ]]
    [[ $output == *'"type": "feat"'* ]]
    [[ $output == *"add endpoint"* ]]
    [[ $output == *'"skip": false'* ]]
}

@test "detect_changelog_commits skips loop maintenance commit in range" {
    git_test_repo_setup
    touch "${GIT_TEST_REPO}/file.txt"
    git_test_repo_commit "chore: init"
    local base
    base="$(git -C "${GIT_TEST_REPO}" rev-parse HEAD)"
    git_test_repo_commit "chore(changelog): update CHANGELOG.md (loop-changelog)"
    git_test_repo_run "bash '${DETECT_SCRIPT}' --scope range --since '${base}'"
    [ "$status" -eq 0 ]
    [[ $output == *'"skip": true'* ]]
    [[ $output == *'"commits": []'* ]]
}

@test "detect_changelog_commits reports changelog_exists false when missing" {
    git_test_repo_setup
    touch "${GIT_TEST_REPO}/file.txt"
    git_test_repo_commit "chore: init"
    local base
    base="$(git -C "${GIT_TEST_REPO}" rev-parse HEAD)"
    git_test_repo_commit "fix: repair parser"
    git_test_repo_run "bash '${DETECT_SCRIPT}' --scope range --since '${base}'"
    [ "$status" -eq 0 ]
    [[ $output == *'"changelog_exists": false'* ]]
}

@test "detect_changelog_commits reports changelog_exists true when present" {
    git_test_repo_setup
    printf '# Changelog\n\n## [Unreleased]\n' > "${GIT_TEST_REPO}/CHANGELOG.md"
    touch "${GIT_TEST_REPO}/file.txt"
    git -C "${GIT_TEST_REPO}" add CHANGELOG.md file.txt
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    local base
    base="$(git -C "${GIT_TEST_REPO}" rev-parse HEAD)"
    git_test_repo_commit "fix: repair parser"
    git_test_repo_run "bash '${DETECT_SCRIPT}' --scope range --since '${base}'"
    [ "$status" -eq 0 ]
    [[ $output == *'"changelog_exists": true'* ]]
}

@test "detect_changelog_commits all scope is bounded by CHANGELOG_MAX_COMMITS" {
    git_test_repo_setup
    touch "${GIT_TEST_REPO}/file.txt"
    local i
    for i in $(seq 1 5); do
        git_test_repo_commit "chore: seed ${i}"
    done
    git_test_repo_run "env CHANGELOG_MAX_COMMITS=2 bash '${DETECT_SCRIPT}' --scope all"
    [ "$status" -eq 0 ]
    [[ $output == *'"commit_range": "HEAD~2..HEAD"'* ]]
}

@test "detect_changelog_commits includes repository_url from GitHub Actions env" {
    git_test_repo_setup
    touch "${GIT_TEST_REPO}/file.txt"
    git_test_repo_commit "chore: init"
    local base
    base="$(git -C "${GIT_TEST_REPO}" rev-parse HEAD)"
    git_test_repo_commit "feat(api): add endpoint"
    git_test_repo_run "env GITHUB_SERVER_URL='https://github.com' GITHUB_REPOSITORY='octocat/hello' bash '${DETECT_SCRIPT}' --scope range --since '${base}'"
    [ "$status" -eq 0 ]
    [[ $output == *'"repository": "octocat/hello"'* ]]
    [[ $output == *'"repository_url": "https://github.com/octocat/hello"'* ]]
    [[ $output == *'"compare_url": "https://github.com/octocat/hello/compare/'* ]]
}

@test "detect_changelog_commits rejects staged scope" {
    git_test_repo_setup
    touch "${GIT_TEST_REPO}/file.txt"
    git_test_repo_commit "chore: init"
    git_test_repo_run "bash '${DETECT_SCRIPT}' --scope staged"
    [ "$status" -eq 0 ]
    [[ $output == *'"status": "error"'* ]]
    [[ $output == *'must be all or range'* ]]
}
