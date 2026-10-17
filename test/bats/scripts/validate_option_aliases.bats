#!/usr/bin/env bats
# shellcheck disable=SC2154

# Tests for scripts/shell-script/validate.sh and scripts/terraform/validate.sh option naming
#
# Use cases:
# - --help lists the canonical option names (-c / -g) and marks -d as deprecated
# - the deprecated -d alias warns and still selects the same behavior
# - unknown options are rejected

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

SHELL_VALIDATE="$(bats_workspace_root)/scripts/shell-script/validate.sh"
TERRAFORM_VALIDATE="$(bats_workspace_root)/scripts/terraform/validate.sh"

@test "shell-script validate --help lists -c and marks -d deprecated" {
    run bash "${SHELL_VALIDATE}" --help
    [ "$status" -eq 0 ]
    [[ $output == *"-c, --check-function-docs"* ]]
    [[ $output == *"-d is a deprecated alias"* ]]
}

@test "terraform validate --help lists -g and marks -d deprecated" {
    run bash "${TERRAFORM_VALIDATE}" --help
    [ "$status" -eq 0 ]
    [[ $output == *"-g, --generate-docs"* ]]
    [[ $output == *"-d is a deprecated alias"* ]]
}

@test "shell-script validate -d warns that it is deprecated" {
    local script="${BATS_TEST_TMPDIR}/ok.sh"
    printf '#!/bin/bash\nset -euo pipefail\n' > "${script}"
    chmod +x "${script}"
    run bash "${SHELL_VALIDATE}" -d --tests "${BATS_TEST_TMPDIR}/none" "${script}"
    [[ $output == *"-d is deprecated for --check-function-docs"* ]]
}

@test "validate scripts reject unknown options" {
    run bash "${SHELL_VALIDATE}" --no-such-option
    [ "$status" -ne 0 ]
    run bash "${TERRAFORM_VALIDATE}" --no-such-option
    [ "$status" -ne 0 ]
}
