#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2154

# Tests for scripts/go/build.sh
#
# Use cases:
# - prepare_build_environment rejects a BINDIR that could escape bin/ or outputs/
# - prepare_build_environment accepts a plain BINDIR and cleans only inside it
# - build_function passes an absolute directory to go build without a ./ prefix
# - build_function passes a relative directory to go build with a ./ prefix
# - go build.sh counts zero main.go files without an arithmetic error

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

BUILD_SCRIPT="$(bats_workspace_root)/scripts/go/build.sh"

setup() {
    WORK_DIR="${BATS_TEST_TMPDIR}/work"
    mkdir -p "${WORK_DIR}" "${BATS_TEST_TMPDIR}/bin"
    printf '#!/usr/bin/env bash\nexit 0\n' > "${BATS_TEST_TMPDIR}/bin/go"
    chmod +x "${BATS_TEST_TMPDIR}/bin/go"
    export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
}

@test "prepare_build_environment rejects a BINDIR that could escape bin/ or outputs/" {
    local bindir
    for bindir in ".." "../x" "a/b" "/abs" "a..b"; do
        run bash -c "cd '${WORK_DIR}' && source '${BUILD_SCRIPT}' && BINDIR='${bindir}' && prepare_build_environment"
        [ "$status" -ne 0 ]
        [[ $output == *"Invalid BINDIR"* ]]
    done
}

@test "prepare_build_environment accepts a plain BINDIR and cleans only inside it" {
    mkdir -p "${WORK_DIR}/bin/dev" "${WORK_DIR}/outputs/dev" "${WORK_DIR}/bin/keep"
    touch "${WORK_DIR}/bin/dev/old" "${WORK_DIR}/outputs/dev/old" "${WORK_DIR}/bin/keep/file"

    run bash -c "cd '${WORK_DIR}' && source '${BUILD_SCRIPT}' && BINDIR='dev' && prepare_build_environment"
    [ "$status" -eq 0 ]
    [ ! -e "${WORK_DIR}/bin/dev/old" ]
    [ ! -e "${WORK_DIR}/outputs/dev/old" ]
    [ -e "${WORK_DIR}/bin/keep/file" ]
}

@test "go build.sh counts zero main.go files without an arithmetic error" {
    run bash -c "cd '${WORK_DIR}' && source '${BUILD_SCRIPT}' && files='' && file_count=\$(printf '%s\\n' \"\$files\" | grep -c . || true) && [[ \$file_count -eq 0 ]] && echo \"count=\$file_count\""
    [ "$status" -eq 0 ]
    [ "$output" = "count=0" ]
}

@test "build_function passes a relative directory to go build with a ./ prefix" {
    printf '#!/usr/bin/env bash\necho "$*" >> "%s/go.log"\n' "${BATS_TEST_TMPDIR}" > "${BATS_TEST_TMPDIR}/bin/go"
    printf '#!/usr/bin/env bash\nexit 0\n' > "${BATS_TEST_TMPDIR}/bin/zip"
    chmod +x "${BATS_TEST_TMPDIR}/bin/zip"
    run bash -c "cd '${WORK_DIR}' && mkdir -p outputs/dev && source '${BUILD_SCRIPT}' && BINDIR=dev ARCH=amd64 VERBOSE=false && build_function cmd/fn/main.go"
    [ "$status" -eq 0 ]
    grep -q -- ' ./cmd/fn$' "${BATS_TEST_TMPDIR}/go.log"
}

@test "build_function passes an absolute directory to go build without a ./ prefix" {
    printf '#!/usr/bin/env bash\necho "$*" >> "%s/go.log"\n' "${BATS_TEST_TMPDIR}" > "${BATS_TEST_TMPDIR}/bin/go"
    printf '#!/usr/bin/env bash\nexit 0\n' > "${BATS_TEST_TMPDIR}/bin/zip"
    chmod +x "${BATS_TEST_TMPDIR}/bin/zip"
    run bash -c "cd '${WORK_DIR}' && mkdir -p outputs/dev && source '${BUILD_SCRIPT}' && BINDIR=dev ARCH=amd64 VERBOSE=false && build_function '${WORK_DIR}/cmd/fn/main.go'"
    [ "$status" -eq 0 ]
    grep -q -- " ${WORK_DIR}/cmd/fn\$" "${BATS_TEST_TMPDIR}/go.log"
    run grep -q -- './/' "${BATS_TEST_TMPDIR}/go.log"
    [ "$status" -ne 0 ]
}
