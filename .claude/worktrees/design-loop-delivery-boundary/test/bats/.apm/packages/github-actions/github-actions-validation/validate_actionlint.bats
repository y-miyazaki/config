#!/usr/bin/env bats

# validate.sh must run actionlint from the repository root so .github/actionlint.yaml applies.

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    ROOT="$(bats_workspace_root)"
    VALIDATE="${ROOT}/.apm/packages/github-actions/.apm/skills/github-actions-validation/scripts/validate.sh"
}

@test "validate.sh succeeds when run from skill directory" {
    cd "${ROOT}/.apm/packages/github-actions/.apm/skills/github-actions-validation"
    run bash "${VALIDATE}" -q
    [ "$status" -eq 0 ]
}
