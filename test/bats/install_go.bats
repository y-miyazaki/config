#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for install_go.sh

# Use cases:
# - every download URL carries a cache-busting query string (?cb=<epoch>)
# - the query string is appended after the source path, not the base URL
# - existing files are skipped without any download

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    REPO_ROOT="$(bats_workspace_root)"
    SCRIPT="${REPO_ROOT}/install_go.sh"
    MOCK_BIN="${BATS_TEST_TMPDIR}/bin"
    CURL_LOG="${BATS_TEST_TMPDIR}/curl.log"
    TARGET="${BATS_TEST_TMPDIR}/target"
    mkdir -p "${MOCK_BIN}" "${TARGET}"
    cat > "${MOCK_BIN}/curl" << 'EOF'
#!/usr/bin/env bash
url=""
out=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        http*) url="$1"; shift ;;
        *) shift ;;
    esac
done
echo "${url}" >> "${CURL_LOG}"
: > "${out}"
EOF
    chmod +x "${MOCK_BIN}/curl"
    export CURL_LOG
    export PATH="${MOCK_BIN}:${PATH}"
}

@test "install_go: every download URL has a cache-busting query" {
    run bash "${SCRIPT}" "${TARGET}"
    [ "${status}" -eq 0 ]
    [ -s "${CURL_LOG}" ]
    while IFS= read -r url; do
        [[ ${url} =~ ^https://raw\.githubusercontent\.com/y-miyazaki/config/main/[^?]+\?cb=[0-9]+$ ]]
    done < "${CURL_LOG}"
}

@test "install_go: pre-commit variant is fetched with the query after the path" {
    run bash "${SCRIPT}" "${TARGET}"
    [ "${status}" -eq 0 ]
    grep -Eq '/\.pre-commit-config-go\.yaml\?cb=[0-9]+$' "${CURL_LOG}"
}

@test "install_go: existing files are skipped without download" {
    run bash "${SCRIPT}" "${TARGET}"
    [ "${status}" -eq 0 ]
    : > "${CURL_LOG}"
    run bash "${SCRIPT}" "${TARGET}"
    [ "${status}" -eq 0 ]
    [ ! -s "${CURL_LOG}" ]
}
