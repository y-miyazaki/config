#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2154

# Tests for scripts/nodejs/validate.sh
#
# Use cases:
# - find_nodejs_projects finds projects whose path contains spaces
# - find_nodejs_projects skips node_modules and build output

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
