#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for scripts/go/clean_binaries.sh
#
# Use cases:
# - is_binary_executable identifies ELF binaries vs text files
# - parse_arguments refuses unsafe root directories (/ or $HOME)
# - remove_binary_files deletes binaries in real mode, previews in dry-run
# - remove_build_dirs removes known build directories, previews in dry-run
# - CLI entrypoint supports --dry-run and rejects unknown options

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

SCRIPT_UNDER_TEST="$(bats_workspace_root)/scripts/go/clean_binaries.sh"

setup() {
    WORK_DIR="${BATS_TEST_TMPDIR}/work"
    mkdir -p "${WORK_DIR}"
}

@test "clean_binaries.sh --dry-run leaves the binary and prints DRY-RUN" {
    cp /bin/true "${WORK_DIR}/tool"

    run bash "${SCRIPT_UNDER_TEST}" --dry-run "${WORK_DIR}"
    [ "$status" -eq 0 ]
    [[ $output == *"DRY-RUN"* ]]
    [ -e "${WORK_DIR}/tool" ]
}

@test "clean_binaries.sh rejects an unknown option" {
    run bash "${SCRIPT_UNDER_TEST}" --nope
    [ "$status" -ne 0 ]
    [[ $output == *"Unknown option"* ]]
}

@test "is_binary_executable detects an ELF binary and rejects a text file" {
    cp /bin/true "${WORK_DIR}/bin_copy"
    printf 'hello\n' > "${WORK_DIR}/text.txt"

    run bash -c "
        source '${SCRIPT_UNDER_TEST}'
        if is_binary_executable '${WORK_DIR}/bin_copy'; then echo 'binary=yes'; else echo 'binary=no'; fi
        if is_binary_executable '${WORK_DIR}/text.txt'; then echo 'text=yes'; else echo 'text=no'; fi
    "
    [ "$status" -eq 0 ]
    [[ $output == *"binary=yes"* ]]
    [[ $output == *"text=no"* ]]
}

@test "parse_arguments refuses to run against / or HOME" {
    run bash -c "source '${SCRIPT_UNDER_TEST}' && parse_arguments /"
    [ "$status" -ne 0 ]
    [[ $output == *"Refusing to clean unsafe root directory"* ]]

    run bash -c "export HOME='${WORK_DIR}'; source '${SCRIPT_UNDER_TEST}'; parse_arguments '${WORK_DIR}'"
    [ "$status" -ne 0 ]
    [[ $output == *"Refusing to clean unsafe root directory"* ]]
}

@test "remove_binary_files dry-run mode reports without deleting" {
    cp /bin/true "${WORK_DIR}/tool"

    run bash -c "source '${SCRIPT_UNDER_TEST}' && ROOT_DIR='${WORK_DIR}' && DRY_RUN=true && VERBOSE=false && remove_binary_files && echo \"count=\${BINARY_COUNT}\""
    [ "$status" -eq 0 ]
    [[ $output == *"count=1"* ]]
    [ -e "${WORK_DIR}/tool" ]
}

@test "remove_binary_files removes binary executables but preserves text files" {
    mkdir -p "${WORK_DIR}/sub"
    cp /bin/true "${WORK_DIR}/sub/tool"
    printf 'keep me\n' > "${WORK_DIR}/sub/notes.txt"

    run bash -c "source '${SCRIPT_UNDER_TEST}' && ROOT_DIR='${WORK_DIR}' && DRY_RUN=false && VERBOSE=false && remove_binary_files && echo \"count=\${BINARY_COUNT}\""
    [ "$status" -eq 0 ]
    [[ $output == *"count=1"* ]]
    [ ! -e "${WORK_DIR}/sub/tool" ]
    [ -e "${WORK_DIR}/sub/notes.txt" ]
}

@test "remove_build_dirs dry-run mode leaves directories intact" {
    mkdir -p "${WORK_DIR}/bin"
    touch "${WORK_DIR}/bin/x"

    run bash -c "source '${SCRIPT_UNDER_TEST}' && ROOT_DIR='${WORK_DIR}' && DRY_RUN=true && VERBOSE=false && remove_build_dirs && echo \"count=\${DIR_COUNT}\""
    [ "$status" -eq 0 ]
    [[ $output == *"count=1"* ]]
    [ -d "${WORK_DIR}/bin" ]
    [ -e "${WORK_DIR}/bin/x" ]
}

@test "remove_build_dirs removes known build directories but leaves others" {
    mkdir -p "${WORK_DIR}/bin" "${WORK_DIR}/dist" "${WORK_DIR}/builds" "${WORK_DIR}/keep"
    touch "${WORK_DIR}/bin/x" "${WORK_DIR}/keep/y"

    run bash -c "source '${SCRIPT_UNDER_TEST}' && ROOT_DIR='${WORK_DIR}' && DRY_RUN=false && VERBOSE=false && remove_build_dirs && echo \"count=\${DIR_COUNT}\""
    [ "$status" -eq 0 ]
    [[ $output == *"count=3"* ]]
    [ ! -d "${WORK_DIR}/bin" ]
    [ ! -d "${WORK_DIR}/dist" ]
    [ ! -d "${WORK_DIR}/builds" ]
    [ -d "${WORK_DIR}/keep" ]
}
