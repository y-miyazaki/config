#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for scripts/self/apm/sync_skill_lib.sh
#
# Use cases:
# - sync mirrors scripts/lib into every skill, removes stale files, and excludes bytecode caches
# - sync is idempotent: a second run leaves unchanged files untouched
# - sync creates no staging directory under .apm/ and removes leftovers of earlier versions
# - sync skips skills without a scripts directory
# - --check reports drift without changing the skill lib
# - an unknown argument is rejected

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    WS="${BATS_TEST_TMPDIR}/ws"
    SKILL_SCRIPTS="${WS}/.apm/packages/pkg/.apm/skills/skill/scripts"
    mkdir -p "${WS}/scripts/self/apm" "${WS}/scripts/lib/__pycache__" "${SKILL_SCRIPTS}/lib"
    cp "$(bats_workspace_root)/scripts/self/apm/sync_skill_lib.sh" "${WS}/scripts/self/apm/"
    : > "${WS}/scripts/lib/all.sh"
    echo "source" > "${WS}/scripts/lib/common.sh"
    : > "${WS}/scripts/lib/__pycache__/x.pyc"
    echo "stale" > "${SKILL_SCRIPTS}/lib/stale.sh"
    SYNC="${WS}/scripts/self/apm/sync_skill_lib.sh"
}

teardown() {
    rm -rf "${WS}"
}

@test "--check reports drift without changing the skill lib" {
    run bash "${SYNC}" --check
    [ "$status" -eq 1 ]
    [[ $output == *"DRIFT: skill"* ]]
    [ -f "${SKILL_SCRIPTS}/lib/stale.sh" ]
    [ ! -e "${SKILL_SCRIPTS}/lib/common.sh" ]
}

@test "sync is idempotent and keeps unchanged files untouched" {
    run bash "${SYNC}"
    [ "$status" -eq 0 ]
    local before after
    before="$(stat -c '%i %Y' "${SKILL_SCRIPTS}/lib/common.sh")"
    run bash "${SYNC}"
    [ "$status" -eq 0 ]
    after="$(stat -c '%i %Y' "${SKILL_SCRIPTS}/lib/common.sh")"
    [ "${before}" = "${after}" ]
    run bash "${SYNC}" --check
    [ "$status" -eq 0 ]
}

@test "sync leaves no staging directory and removes leftovers of earlier versions" {
    mkdir -p "${SKILL_SCRIPTS}/.lib.new.111" "${SKILL_SCRIPTS}/.lib.old.222"
    run bash "${SYNC}"
    [ "$status" -eq 0 ]
    [ ! -e "${SKILL_SCRIPTS}/.lib.new.111" ]
    [ ! -e "${SKILL_SCRIPTS}/.lib.old.222" ]
    run bash -c "find '${WS}/.apm' -name '.lib.*'"
    [ -z "$output" ]
}

@test "sync mirrors lib, removes stale files and bytecode caches" {
    mkdir -p "${SKILL_SCRIPTS}/lib/__pycache__"
    : > "${SKILL_SCRIPTS}/lib/__pycache__/old.pyc"
    run bash "${SYNC}"
    [ "$status" -eq 0 ]
    [[ $output == *"SYNCED: skill"* ]]
    [ "$(cat "${SKILL_SCRIPTS}/lib/common.sh")" = "source" ]
    [ ! -e "${SKILL_SCRIPTS}/lib/stale.sh" ]
    [ ! -e "${SKILL_SCRIPTS}/lib/__pycache__" ]
}

@test "sync skips skills without a scripts directory" {
    mkdir -p "${WS}/.apm/packages/pkg/.apm/skills/no_scripts"
    run bash "${SYNC}"
    [ "$status" -eq 0 ]
    [ ! -e "${WS}/.apm/packages/pkg/.apm/skills/no_scripts/scripts" ]
}

@test "unknown argument is rejected" {
    run bash "${SYNC}" --bogus
    [ "$status" -eq 1 ]
    [[ $output == *"ERROR"* ]]
}
