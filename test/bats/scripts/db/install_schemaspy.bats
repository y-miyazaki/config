#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2154

# Tests for scripts/db/install_schemaspy.sh
#
# Use cases:
# - parse_arguments sets FORCE_INSTALL on -f/--force
# - parse_arguments sets DB_TYPE from -t/--db-type's value
# - parse_arguments rejects an unknown option
# - parse_arguments rejects an unexpected positional argument
# - parse_arguments requires a value for -t/--db-type
# - validate_parameters rejects an invalid database type
# - validate_parameters accepts every documented database type
# - validate_parameters creates the install directory when it is missing
# - validate_parameters fails when INSTALL_DIR exists as a non-directory file

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

INSTALL_SCHEMASPY="$(bats_workspace_root)/scripts/db/install_schemaspy.sh"

@test "parse_arguments sets FORCE_INSTALL on -f/--force" {
    run bash -c "source '${INSTALL_SCHEMASPY}'; parse_arguments -f; echo \"\${FORCE_INSTALL}\""
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "parse_arguments sets DB_TYPE from -t/--db-type's value" {
    run bash -c "source '${INSTALL_SCHEMASPY}'; parse_arguments -t redshift; echo \"\${DB_TYPE}\""
    [ "$status" -eq 0 ]
    [ "$output" = "redshift" ]
}

@test "parse_arguments rejects an unknown option" {
    run bash -c "source '${INSTALL_SCHEMASPY}'; parse_arguments --bogus"
    [ "$status" -ne 0 ]
    [[ $output == *"Unknown option: --bogus"* ]]
}

@test "parse_arguments rejects an unexpected positional argument" {
    run bash -c "source '${INSTALL_SCHEMASPY}'; parse_arguments bogus-arg"
    [ "$status" -ne 0 ]
    [[ $output == *"Unexpected argument: bogus-arg"* ]]
}

@test "parse_arguments requires a value for -t/--db-type" {
    run bash -c "source '${INSTALL_SCHEMASPY}'; parse_arguments -t"
    [ "$status" -ne 0 ]
    [[ $output == *"Option -t requires a value"* ]]
}

@test "validate_parameters accepts every documented database type" {
    run bash -c "
        source '${INSTALL_SCHEMASPY}'
        for t in pgsql mysql oracle redshift all; do
            DB_TYPE=\"\$t\"
            INSTALL_DIR='${BATS_TEST_TMPDIR}'/\"\$t\"
            validate_parameters
        done
        echo ok
    "
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "validate_parameters creates the install directory when it is missing" {
    local dir="${BATS_TEST_TMPDIR}/missing-install-dir"
    run bash -c "source '${INSTALL_SCHEMASPY}'; DB_TYPE=all; INSTALL_DIR='${dir}'; validate_parameters"
    [ "$status" -eq 0 ]
    [ -d "${dir}" ]
}

@test "validate_parameters fails when INSTALL_DIR exists as a non-directory file" {
    local file="${BATS_TEST_TMPDIR}/not-a-dir"
    : > "${file}"
    run bash -c "source '${INSTALL_SCHEMASPY}'; DB_TYPE=all; INSTALL_DIR='${file}'; validate_parameters"
    [ "$status" -ne 0 ]
}

@test "validate_parameters rejects an invalid database type" {
    run bash -c "source '${INSTALL_SCHEMASPY}'; DB_TYPE=bogus; INSTALL_DIR='${BATS_TEST_TMPDIR}/bogus-dir'; validate_parameters"
    [ "$status" -ne 0 ]
    [[ $output == *"Invalid database type: bogus"* ]]
}
