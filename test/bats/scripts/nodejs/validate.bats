#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2154

# Tests for scripts/nodejs/validate.sh
#
# Use cases:
# - find_nodejs_projects finds projects whose path contains spaces
# - find_nodejs_projects skips node_modules and build output
# - filter_changed_projects keeps only projects owning changed files, using the deepest match
# - filter_changed_projects emits nothing when no file changed
# - filter_changed_projects ignores changed files that are not JS TS or JSON
# - filter_changed_projects keeps a project whose file was removed
# - run_security_audit counts a single vulnerability reported as "1 vulnerability"
# - run_npm_install uses npm ci by default
# - run_npm_install uses npm install with --fix
# - run_npm_install dry-run prints the planned command without running npm
# - run_npm_install fails and sets INSTALL_FAILED when npm ci fails

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

VALIDATE_SCRIPT="$(bats_workspace_root)/scripts/nodejs/validate.sh"

@test "find_nodejs_projects finds projects whose path contains spaces" {
    mkdir -p "${BATS_TEST_TMPDIR}/proj one" "${BATS_TEST_TMPDIR}/proj2"
    echo '{}' > "${BATS_TEST_TMPDIR}/proj one/package.json"
    echo '{}' > "${BATS_TEST_TMPDIR}/proj2/package.json"
    run bash -c "source '${VALIDATE_SCRIPT}' && find_nodejs_projects '${BATS_TEST_TMPDIR}'"
    [ "$status" -eq 0 ]
    [[ $output == *"proj one"* ]]
    [[ $output == *"proj2"* ]]
}

@test "find_nodejs_projects skips node_modules and build output" {
    mkdir -p "${BATS_TEST_TMPDIR}/app/node_modules" "${BATS_TEST_TMPDIR}/app/dist"
    echo '{}' > "${BATS_TEST_TMPDIR}/app/package.json"
    echo '{}' > "${BATS_TEST_TMPDIR}/app/node_modules/package.json"
    echo '{}' > "${BATS_TEST_TMPDIR}/app/dist/package.json"
    run bash -c "source '${VALIDATE_SCRIPT}' && find_nodejs_projects '${BATS_TEST_TMPDIR}'"
    [ "$status" -eq 0 ]
    [ "$output" = "${BATS_TEST_TMPDIR}/app" ]
}

@test "run_security_audit counts a single vulnerability reported as 1 vulnerability" {
    mkdir -p "${BATS_TEST_TMPDIR}/bin" "${BATS_TEST_TMPDIR}/app"
    printf '#!/bin/bash\necho "1 vulnerability (1 moderate)"\nexit 1\n' > "${BATS_TEST_TMPDIR}/bin/npm"
    chmod +x "${BATS_TEST_TMPDIR}/bin/npm"
    run bash -c "PATH='${BATS_TEST_TMPDIR}/bin':\$PATH; source '${VALIDATE_SCRIPT}' && run_security_audit '${BATS_TEST_TMPDIR}/app'"
    [ "$status" -ne 0 ]
    [[ $output == *"Security vulnerabilities found: 1"* ]]
}

_mock_npm() {
    mkdir -p "${BATS_TEST_TMPDIR}/bin" "${BATS_TEST_TMPDIR}/app"
    printf '#!/bin/bash\necho "npm $*" >> "%s/npm.log"\nexit %s\n' "${BATS_TEST_TMPDIR}" "${1:-0}" > "${BATS_TEST_TMPDIR}/bin/npm"
    chmod +x "${BATS_TEST_TMPDIR}/bin/npm"
}

@test "run_npm_install uses npm ci by default" {
    _mock_npm 0
    run bash -c "PATH='${BATS_TEST_TMPDIR}/bin':\$PATH; source '${VALIDATE_SCRIPT}' && run_npm_install '${BATS_TEST_TMPDIR}/app'"
    [ "$status" -eq 0 ]
    [ "$(cat "${BATS_TEST_TMPDIR}/npm.log")" = "npm ci" ]
}

@test "run_npm_install uses npm install with --fix" {
    _mock_npm 0
    run bash -c "PATH='${BATS_TEST_TMPDIR}/bin':\$PATH; source '${VALIDATE_SCRIPT}' && FIX_MODE=true && run_npm_install '${BATS_TEST_TMPDIR}/app'"
    [ "$status" -eq 0 ]
    [ "$(cat "${BATS_TEST_TMPDIR}/npm.log")" = "npm install" ]
}

@test "run_npm_install dry-run prints the planned command without running npm" {
    _mock_npm 0
    run bash -c "PATH='${BATS_TEST_TMPDIR}/bin':\$PATH; source '${VALIDATE_SCRIPT}' && DRY_RUN=true && VERBOSE=true && run_npm_install '${BATS_TEST_TMPDIR}/app'"
    [ "$status" -eq 0 ]
    [[ $output == *"Would run: npm ci"* ]]
    [ ! -f "${BATS_TEST_TMPDIR}/npm.log" ]
}

@test "run_npm_install fails and sets INSTALL_FAILED when npm ci fails" {
    _mock_npm 1
    run bash -c "PATH='${BATS_TEST_TMPDIR}/bin':\$PATH; source '${VALIDATE_SCRIPT}' && (run_npm_install '${BATS_TEST_TMPDIR}/app' || echo \"rc=\$? failed=\$INSTALL_FAILED\")"
    [[ $output == *"rc=1 failed=1"* ]]
}

@test "filter_changed_projects emits nothing when no file changed" {
    local repo="${BATS_TEST_TMPDIR}/repo"
    bats_git_fresh_repo "${repo}"
    mkdir -p "${repo}/p1"
    echo '{}' > "${repo}/p1/package.json"
    bats_git_commit "${repo}" init
    run bash -c "cd '${repo}' && source '${VALIDATE_SCRIPT}' && filter_changed_projects '${repo}/p1'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "filter_changed_projects keeps only projects owning changed files, using the deepest match" {
    local repo="${BATS_TEST_TMPDIR}/repo"
    bats_git_fresh_repo "${repo}"
    mkdir -p "${repo}/p1" "${repo}/p2" "${repo}/p1/sub"
    echo '{}' > "${repo}/package.json"
    echo '{}' > "${repo}/p1/package.json"
    echo '{}' > "${repo}/p2/package.json"
    echo '{}' > "${repo}/p1/sub/package.json"
    bats_git_commit "${repo}" init
    echo '// c' > "${repo}/p1/sub/index.js"
    echo '// c' > "${repo}/p2/index.js"
    run bash -c "cd '${repo}' && source '${VALIDATE_SCRIPT}' && filter_changed_projects '${repo}' '${repo}/p1' '${repo}/p2' '${repo}/p1/sub'"
    [ "$status" -eq 0 ]
    [ "$output" = "${repo}/p2"$'\n'"${repo}/p1/sub" ]
}

@test "filter_changed_projects keeps a project whose file was removed" {
    local repo="${BATS_TEST_TMPDIR}/repo"
    bats_git_fresh_repo "${repo}"
    mkdir -p "${repo}/p1"
    echo '{}' > "${repo}/p1/package.json"
    echo '// c' > "${repo}/p1/index.js"
    bats_git_commit "${repo}" init
    rm "${repo}/p1/index.js"
    run bash -c "cd '${repo}' && source '${VALIDATE_SCRIPT}' && filter_changed_projects '${repo}/p1'"
    [ "$status" -eq 0 ]
    [ "$output" = "${repo}/p1" ]
}

@test "filter_changed_projects ignores changed files that are not JS TS or JSON" {
    local repo="${BATS_TEST_TMPDIR}/repo"
    bats_git_fresh_repo "${repo}"
    mkdir -p "${repo}/p1"
    echo '{}' > "${repo}/package.json"
    echo '{}' > "${repo}/p1/package.json"
    bats_git_commit "${repo}" init
    echo 'x' > "${repo}/README.md"
    echo 'x' > "${repo}/tool.sh"
    run bash -c "cd '${repo}' && source '${VALIDATE_SCRIPT}' && filter_changed_projects '${repo}' '${repo}/p1'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
