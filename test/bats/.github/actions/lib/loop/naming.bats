#!/usr/bin/env bats

# Tests for the function naming rule of .github/actions/lib/loop/ (.github/actions/CLAUDE.md)
#
# Use cases:
# - every function in a shared lib/loop/<stem>.sh starts with <stem>_ (main is the only exception)
# - no validate_*.sh remains in lib/loop: validators are check_*.sh

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

@test "every function in a shared lib/loop script starts with the file stem" {
    local lib file stem name bad=""
    lib="$(bats_workspace_root)/.github/actions/lib/loop"
    for file in "${lib}"/*.sh; do
        stem="$(basename "${file}" .sh)"
        stem="${stem#_}"
        while IFS= read -r name; do
            [[ ${name} == "main" || ${name} == "${stem}_"* ]] && continue
            bad+="${stem}.sh: ${name}"$'\n'
        done < <(sed -nE 's/^function ([A-Za-z0-9_]+).*/\1/p' "${file}")
    done
    [ -z "${bad}" ] || { printf '%s' "${bad}" >&2; return 1; }
}

@test "no validate_*.sh remains in lib/loop" {
    local lib
    lib="$(bats_workspace_root)/.github/actions/lib/loop"
    [ -z "$(find "${lib}" -maxdepth 1 -name 'validate_*.sh')" ]
}
