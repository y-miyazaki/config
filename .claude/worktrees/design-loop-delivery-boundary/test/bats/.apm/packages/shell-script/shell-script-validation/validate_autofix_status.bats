#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for scripts/shell-script/validate.sh (auto-fix return status)
#
# Use cases:
# - validate_permissions returns 1 without --fix and 0 after making the script executable
# - validate_shebang returns 0 after adding a missing shebang with --fix and 1 without it

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel "scripts/shell-script/validate.sh"
    set +e
    FIXTURE_DIR="${BATS_TEST_TMPDIR}/autofix"
    mkdir -p "${FIXTURE_DIR}"
}

@test "validate_permissions returns 1 without --fix and 0 after making the script executable" {
    printf '#!/bin/bash\necho hi\n' > "${FIXTURE_DIR}/noexec.sh"
    chmod -x "${FIXTURE_DIR}/noexec.sh"

    AUTO_FIX=false
    run validate_permissions "${FIXTURE_DIR}/noexec.sh"
    [ "$status" -eq 1 ]
    [ ! -x "${FIXTURE_DIR}/noexec.sh" ]

    AUTO_FIX=true
    run validate_permissions "${FIXTURE_DIR}/noexec.sh"
    [ "$status" -eq 0 ]
    [ -x "${FIXTURE_DIR}/noexec.sh" ]
}

@test "validate_shebang returns 0 after adding a missing shebang with --fix and 1 without it" {
    printf 'echo hi\n' > "${FIXTURE_DIR}/noshebang.sh"

    AUTO_FIX=false
    run validate_shebang "${FIXTURE_DIR}/noshebang.sh"
    [ "$status" -eq 1 ]
    [ "$(head -1 "${FIXTURE_DIR}/noshebang.sh")" = "echo hi" ]

    AUTO_FIX=true
    run validate_shebang "${FIXTURE_DIR}/noshebang.sh"
    [ "$status" -eq 0 ]
    [ "$(head -1 "${FIXTURE_DIR}/noshebang.sh")" = "#!/bin/bash" ]
}
