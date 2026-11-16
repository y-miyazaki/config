#!/usr/bin/env bats

# Tests for the job `if` of .github/workflows/on-loop-*.yaml
#
# Use cases:
# - no on-loop workflow turns an intake check off by repository visibility
# - every on-loop workflow that admits comments or Issues by author association lists the same trusted roles

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    ROOT="$(bats_workspace_root)"
}

@test "no on-loop workflow turns an intake check off by repository visibility" {
    run grep -n 'repository.private' "${ROOT}"/.github/workflows/on-loop-*.yaml
    [ "$status" -eq 1 ]
}

@test "association checks list exactly MEMBER OWNER COLLABORATOR" {
    local file line
    for file in "${ROOT}"/.github/workflows/on-loop-*.yaml; do
        while IFS= read -r line; do
            [[ ${line} == *'["MEMBER","OWNER","COLLABORATOR"]'* ]]
        done < <(grep 'author_association' "${file}" | grep 'fromJSON' || true)
    done
}
