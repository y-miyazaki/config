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
# - remove_build_dirs keeps tracked files in a build directory and removes its untracked content
# - remove_binary_files refuses to delete when a .git directory cannot be read by git
# - remove_binary_files refuses to delete in a subdirectory of a repository git cannot read
# - remove_binary_files keeps a git-tracked binary and removes an untracked one
# - remove_binary_files removes binaries outside a git work tree
# - remove_binary_files keeps a tracked binary whose name contains a newline
# - remove_binary_files keeps a tracked binary with spaces in its path

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

@test 'parse_arguments refuses to run against "/" or $HOME' {
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

@test "remove_binary_files keeps a git-tracked binary and removes an untracked one" {
    git -C "${WORK_DIR}" init -q
    cp /bin/true "${WORK_DIR}/tracked_binary"
    cp /bin/true "${WORK_DIR}/untracked_binary"
    git -C "${WORK_DIR}" add tracked_binary

    run bash -c "source '${CLEAN_SCRIPT}' && ROOT_DIR='${WORK_DIR}' && DRY_RUN=false && VERBOSE=false && BINARY_COUNT=0 && remove_binary_files && echo \"binary_count=\${BINARY_COUNT}\""
    [ "$status" -eq 0 ]
    [[ $output == *"binary_count=1"* ]]
    [ -e "${WORK_DIR}/tracked_binary" ]
    [ ! -e "${WORK_DIR}/untracked_binary" ]
}

@test "remove_binary_files removes binaries outside a git work tree" {
    cp /bin/true "${WORK_DIR}/real_binary"

    run bash -c "source '${CLEAN_SCRIPT}' && ROOT_DIR='${WORK_DIR}' && DRY_RUN=false && VERBOSE=false && BINARY_COUNT=0 && remove_binary_files && echo \"binary_count=\${BINARY_COUNT}\""
    [ "$status" -eq 0 ]
    [[ $output == *"binary_count=1"* ]]
    [ ! -e "${WORK_DIR}/real_binary" ]
}

@test "remove_binary_files keeps a tracked binary with spaces in its path" {
    git -C "${WORK_DIR}" init -q
    mkdir -p "${WORK_DIR}/sub dir"
    cp /bin/true "${WORK_DIR}/sub dir/tracked binary"
    git -C "${WORK_DIR}" add "sub dir/tracked binary"

    run bash -c "source '${CLEAN_SCRIPT}' && ROOT_DIR='${WORK_DIR}' && DRY_RUN=false && VERBOSE=false && BINARY_COUNT=0 && remove_binary_files && echo \"binary_count=\${BINARY_COUNT}\""
    [ "$status" -eq 0 ]
    [[ $output == *"binary_count=0"* ]]
    [ -e "${WORK_DIR}/sub dir/tracked binary" ]
}

@test "remove_build_dirs keeps tracked files in a build directory and removes its untracked content" {
    git -C "${WORK_DIR}" init -q
    mkdir -p "${WORK_DIR}/bin" "${WORK_DIR}/dist"
    echo "tracked" > "${WORK_DIR}/bin/tool"
    echo "checksum" > "${WORK_DIR}/bin/tool.sha256"
    ln -s tool "${WORK_DIR}/bin/tool-link"
    echo "artifact" > "${WORK_DIR}/dist/artifact"
    git -C "${WORK_DIR}" add bin/tool

    run bash -c "source '${CLEAN_SCRIPT}' && ROOT_DIR='${WORK_DIR}' && DRY_RUN=false && VERBOSE=false && DIR_COUNT=0 && remove_build_dirs && echo \"dir_count=\${DIR_COUNT}\""
    [ "$status" -eq 0 ]
    [[ $output == *"dir_count=1"* ]]
    [ -e "${WORK_DIR}/bin/tool" ]
    [ ! -e "${WORK_DIR}/bin/tool.sha256" ]
    [ ! -L "${WORK_DIR}/bin/tool-link" ]
    [ ! -d "${WORK_DIR}/dist" ]
}

@test "remove_binary_files refuses to delete when a .git directory cannot be read by git" {
    mkdir -p "${WORK_DIR}/.git"
    cp /bin/true "${WORK_DIR}/real_binary"

    run bash -c "source '${CLEAN_SCRIPT}' && ROOT_DIR='${WORK_DIR}' && DRY_RUN=false && VERBOSE=false && BINARY_COUNT=0 && remove_binary_files"
    [ "$status" -ne 0 ]
    [[ $output == *"Cannot determine git-tracked files"* ]]
    [ -e "${WORK_DIR}/real_binary" ]
}

@test "remove_binary_files keeps a tracked binary whose name contains a newline" {
    git -C "${WORK_DIR}" init -q
    cp /bin/true "${WORK_DIR}/odd"$'\n'"name"
    git -C "${WORK_DIR}" add -A

    run bash -c "source '${CLEAN_SCRIPT}' && ROOT_DIR='${WORK_DIR}' && DRY_RUN=false && VERBOSE=false && BINARY_COUNT=0 && remove_binary_files && echo \"binary_count=\${BINARY_COUNT}\""
    [ "$status" -eq 0 ]
    [[ $output == *"binary_count=0"* ]]
    [ -e "${WORK_DIR}/odd"$'\n'"name" ]
}

@test "remove_binary_files refuses to delete in a subdirectory of a repository git cannot read" {
    mkdir -p "${WORK_DIR}/.git" "${WORK_DIR}/sub"
    cp /bin/true "${WORK_DIR}/sub/real_binary"

    run bash -c "source '${CLEAN_SCRIPT}' && ROOT_DIR='${WORK_DIR}/sub' && DRY_RUN=false && VERBOSE=false && BINARY_COUNT=0 && remove_binary_files"
    [ "$status" -ne 0 ]
    [[ $output == *"Cannot determine git-tracked files"* ]]
    [ -e "${WORK_DIR}/sub/real_binary" ]
}
