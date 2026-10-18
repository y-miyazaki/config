#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for scripts/self/apm/sync_skill_lib.sh

# Use cases:
# - --help exits successfully and documents --check
# - an unknown argument exits 1 with an error
# - --check passes when a skill's scripts/lib/ already matches scripts/lib/
# - --check reports drift (missing lib/ or differing contents) and exits 1
# - sync (no flag) copies scripts/lib/ into a skill's scripts/lib/ and makes a later --check pass
# - sync excludes __pycache__ from the copied lib/
# - missing scripts/lib/ at the workspace root fails the unconditional top-level source (exit 1)
# - missing .apm/packages/ at the workspace root exits 1 with an error

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

REPO_ROOT="$(bats_workspace_root)"

# fixture_tree: Build a fixture workspace with scripts/lib/ and one skill scripts/ dir
function fixture_tree {
    FIXTURE_ROOT="${BATS_TEST_TMPDIR}/skill-lib-root"
    rm -rf "${FIXTURE_ROOT}"
    mkdir -p \
        "${FIXTURE_ROOT}/scripts/lib" \
        "${FIXTURE_ROOT}/scripts/self/apm" \
        "${FIXTURE_ROOT}/.apm/packages/pkg1/.apm/skills/skill1/scripts"

    echo "echo source-lib" > "${FIXTURE_ROOT}/scripts/lib/all.sh"
    cp "${REPO_ROOT}/scripts/self/apm/sync_skill_lib.sh" "${FIXTURE_ROOT}/scripts/self/apm/sync_skill_lib.sh"

    SYNC_SCRIPT="${FIXTURE_ROOT}/scripts/self/apm/sync_skill_lib.sh"
    SKILL_SCRIPTS="${FIXTURE_ROOT}/.apm/packages/pkg1/.apm/skills/skill1/scripts"
    SKILL_LIB="${SKILL_SCRIPTS}/lib"
}

setup() {
    fixture_tree
}

@test "sync_skill_lib.sh --check passes when skill lib already matches source lib" {
    cp -a "${FIXTURE_ROOT}/scripts/lib" "${SKILL_LIB}"

    run bash "${SYNC_SCRIPT}" --check
    [ "$status" -eq 0 ]
    [[ $output == *"OK: All skill lib/ directories are in sync."* ]]
}

@test "sync_skill_lib.sh --check reports drift when skill lib/ contents differ" {
    cp -a "${FIXTURE_ROOT}/scripts/lib" "${SKILL_LIB}"
    echo "# drift-marker" >> "${SKILL_LIB}/all.sh"

    run bash "${SYNC_SCRIPT}" --check
    [ "$status" -eq 1 ]
    [[ $output == *"DRIFT: skill1"* ]]
}

@test "sync_skill_lib.sh --check reports drift when skill lib/ is missing" {
    run bash "${SYNC_SCRIPT}" --check
    [ "$status" -eq 1 ]
    [[ $output == *"DRIFT: skill1 (lib/ missing)"* ]]
}

@test "sync_skill_lib.sh --help exits successfully and documents --check" {
    run bash "${SYNC_SCRIPT}" --help
    [ "$status" -eq 0 ]
    [[ $output == *"--check"* ]]
}

@test "sync_skill_lib.sh exits 1 when .apm/packages/ is missing at the workspace root" {
    rm -rf "${FIXTURE_ROOT}/.apm"

    run bash "${SYNC_SCRIPT}" --check
    [ "$status" -eq 1 ]
    [[ $output == *"ERROR: Packages directory not found"* ]]
}

@test "sync_skill_lib.sh exits 1 when scripts/lib/ is missing at the workspace root" {
    # The unconditional top-level `source .../scripts/lib/all.sh` fails before main's
    # own "Source lib not found" check ever runs, so the observed error is bash's
    # generic sourcing failure rather than the script's custom message.
    rm -rf "${FIXTURE_ROOT}/scripts/lib"

    run bash "${SYNC_SCRIPT}" --check
    [ "$status" -eq 1 ]
    [[ $output == *"No such file or directory"* ]]
}

@test "sync_skill_lib.sh rejects an unknown argument" {
    run bash "${SYNC_SCRIPT}" --bogus
    [ "$status" -eq 1 ]
    [[ $output == *"Unknown argument"* ]]
}

@test "sync_skill_lib.sh sync copies source lib into a missing skill lib/" {
    run bash "${SYNC_SCRIPT}"
    [ "$status" -eq 0 ]
    [[ $output == *"SYNCED: skill1"* ]]
    [[ $output == *"Done: 1 skill(s) synced."* ]]

    run bash "${SYNC_SCRIPT}" --check
    [ "$status" -eq 0 ]
    [[ $output == *"OK: All skill lib/ directories are in sync."* ]]
}

@test "sync_skill_lib.sh sync excludes __pycache__ from the copied lib/" {
    mkdir -p "${FIXTURE_ROOT}/scripts/lib/__pycache__"
    echo "cached" > "${FIXTURE_ROOT}/scripts/lib/__pycache__/mod.pyc"

    run bash "${SYNC_SCRIPT}"
    [ "$status" -eq 0 ]
    [ ! -e "${SKILL_LIB}/__pycache__" ]
}

@test "sync_skill_lib.sh sync restores a drifted skill lib/ from source" {
    cp -a "${FIXTURE_ROOT}/scripts/lib" "${SKILL_LIB}"
    echo "# drift-marker" >> "${SKILL_LIB}/all.sh"

    run bash "${SYNC_SCRIPT}"
    [ "$status" -eq 0 ]
    [[ $output == *"SYNCED: skill1"* ]]

    run grep -Fq "drift-marker" "${SKILL_LIB}/all.sh"
    [ "$status" -eq 1 ]
}
