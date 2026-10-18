#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2154

# Tests for scripts/go/clean_binaries.sh
#
# Use cases:
# - is_binary_executable detects an ELF binary and rejects a plain text file
# - parse_arguments rejects an unknown option
# - parse_arguments refuses to run against "/" or $HOME
# - parse_arguments sets ROOT_DIR/VERBOSE/DRY_RUN from valid arguments
# - remove_build_dirs removes known build directories but leaves others alone
# - remove_build_dirs in dry-run mode reports directories without deleting them
# - remove_binary_files in dry-run mode counts a binary without deleting it

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

CLEAN_SCRIPT="$(bats_workspace_root)/scripts/go/clean_binaries.sh"

setup() {
    WORK_DIR="${BATS_TEST_TMPDIR}/work"
    mkdir -p "${WORK_DIR}"
}

@test "is_binary_executable detects an ELF binary and rejects a plain text file" {
    cp /bin/true "${WORK_DIR}/real_binary"
    echo "just some text" > "${WORK_DIR}/not_binary.txt"

    run bash -c "source '${CLEAN_SCRIPT}' && is_binary_executable '${WORK_DIR}/real_binary'"
    [ "$status" -eq 0 ]

    run bash -c "source '${CLEAN_SCRIPT}' && is_binary_executable '${WORK_DIR}/not_binary.txt'"
    [ "$status" -ne 0 ]
}

@test "parse_arguments rejects an unknown option" {
    run bash -c "source '${CLEAN_SCRIPT}' && parse_arguments --bogus"
    [ "$status" -ne 0 ]
    [[ $output == *"Unknown option: --bogus"* ]]
}

@test "parse_arguments refuses to run against \"/\" or \$HOME" {
    run bash -c "source '${CLEAN_SCRIPT}' && parse_arguments /"
    [ "$status" -ne 0 ]
    [[ $output == *"Refusing to clean unsafe root directory"* ]]

    run bash -c "export HOME='${WORK_DIR}' && source '${CLEAN_SCRIPT}' && parse_arguments '${WORK_DIR}'"
    [ "$status" -ne 0 ]
    [[ $output == *"Refusing to clean unsafe root directory"* ]]
}

@test "parse_arguments sets ROOT_DIR/VERBOSE/DRY_RUN from valid arguments" {
    run bash -c "source '${CLEAN_SCRIPT}' && parse_arguments --verbose --dry-run '${WORK_DIR}' && echo \"verbose=\${VERBOSE} dry_run=\${DRY_RUN} root=\${ROOT_DIR}\""
    [ "$status" -eq 0 ]
    [[ $output == *"verbose=true dry_run=true root=${WORK_DIR}"* ]]
}

@test "remove_build_dirs removes known build directories but leaves others alone" {
    mkdir -p "${WORK_DIR}/bin" "${WORK_DIR}/dist" "${WORK_DIR}/keep_me"
    touch "${WORK_DIR}/bin/artifact" "${WORK_DIR}/dist/artifact"

    run bash -c "source '${CLEAN_SCRIPT}' && ROOT_DIR='${WORK_DIR}' && DRY_RUN=false && VERBOSE=false && DIR_COUNT=0 && remove_build_dirs && echo \"dir_count=\${DIR_COUNT}\""
    [ "$status" -eq 0 ]
    [[ $output == *"dir_count=2"* ]]
    [ ! -d "${WORK_DIR}/bin" ]
    [ ! -d "${WORK_DIR}/dist" ]
    [ -d "${WORK_DIR}/keep_me" ]
}

@test "remove_build_dirs in dry-run mode reports directories without deleting them" {
    mkdir -p "${WORK_DIR}/builds"
    touch "${WORK_DIR}/builds/artifact"

    run bash -c "source '${CLEAN_SCRIPT}' && ROOT_DIR='${WORK_DIR}' && DRY_RUN=true && VERBOSE=false && DIR_COUNT=0 && remove_build_dirs && echo \"dir_count=\${DIR_COUNT}\""
    [ "$status" -eq 0 ]
    [[ $output == *"dir_count=1"* ]]
    [ -d "${WORK_DIR}/builds" ]
    [ -e "${WORK_DIR}/builds/artifact" ]
}

@test "remove_binary_files in dry-run mode counts a binary without deleting it" {
    cp /bin/true "${WORK_DIR}/real_binary"
    echo "text" > "${WORK_DIR}/plain.txt"

    run bash -c "source '${CLEAN_SCRIPT}' && ROOT_DIR='${WORK_DIR}' && DRY_RUN=true && VERBOSE=false && BINARY_COUNT=0 && remove_binary_files && echo \"binary_count=\${BINARY_COUNT}\""
    [ "$status" -eq 0 ]
    [[ $output == *"binary_count=1"* ]]
    [ -e "${WORK_DIR}/real_binary" ]
}
