#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/detect-codeql-support/lib/detect.sh
#
# Use cases:
# - active default-setup workflow sets skip=true
# - default-setup workflows API failure emits warning and continues
# - public repository sets skip=false
# - private repository with Code Security enabled sets skip=false
# - private repository without Code Security sets skip=true

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    GITHUB_OUTPUT="$(mktemp)"
    export GITHUB_OUTPUT
    export GITHUB_REPOSITORY="owner/repo"
    mkdir -p "${BATS_TEST_TMPDIR}/bin"
    cat > "${BATS_TEST_TMPDIR}/bin/gh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *actions/workflows*)
    printf '%s' "${MOCK_DEFAULT_SETUP_STATE:-}"
    ;;
  *repos/owner/repo*private*)
    printf '%s' "${MOCK_PRIVATE:-true}"
    ;;
  *repos/owner/repo*)
    printf '%s' "${MOCK_CODE_SECURITY:-}"
    ;;
  *)
    echo "unexpected gh call: $*" >&2
    exit 1
    ;;
esac
EOF
    chmod +x "${BATS_TEST_TMPDIR}/bin/gh"
    export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
    bats_source_rel ".github/actions/detect-codeql-support/lib/detect.sh"
}

teardown() {
    rm -f "${GITHUB_OUTPUT}"
}

@test "active default-setup workflow sets skip=true" {
    export MOCK_DEFAULT_SETUP_STATE="configured"
    run detect_codeql_support
    [ "$status" -eq 0 ]
    grep -q '^skip=true$' "${GITHUB_OUTPUT}"
    [[ ${output} == *"default setup is enabled"* ]]
}

@test "default-setup workflows API failure emits warning and continues" {
    cat > "${BATS_TEST_TMPDIR}/bin/gh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *actions/workflows*)
    echo "HTTP 403: Resource not accessible by integration" >&2
    exit 1
    ;;
  *repos/owner/repo*private*)
    printf '%s' "${MOCK_PRIVATE:-true}"
    ;;
  *repos/owner/repo*)
    printf '%s' "${MOCK_CODE_SECURITY:-}"
    ;;
  *)
    echo "unexpected gh call: $*" >&2
    exit 1
    ;;
esac
EOF
    chmod +x "${BATS_TEST_TMPDIR}/bin/gh"
    export MOCK_PRIVATE="false"
    run detect_codeql_support
    [ "$status" -eq 0 ]
    grep -q '^skip=false$' "${GITHUB_OUTPUT}"
    [[ ${output} == *"default-setup check failed"* ]]
    [[ ${output} == *"actions: read"* ]]
}

@test "private repository with Code Security enabled sets skip=false" {
    export MOCK_DEFAULT_SETUP_STATE=""
    export MOCK_PRIVATE="true"
    export MOCK_CODE_SECURITY="enabled"
    run detect_codeql_support
    [ "$status" -eq 0 ]
    grep -q '^skip=false$' "${GITHUB_OUTPUT}"
}

@test "private repository without Code Security sets skip=true" {
    export MOCK_DEFAULT_SETUP_STATE=""
    export MOCK_PRIVATE="true"
    export MOCK_CODE_SECURITY=""
    run detect_codeql_support
    [ "$status" -eq 0 ]
    grep -q '^skip=true$' "${GITHUB_OUTPUT}"
    [[ ${output} == *"CodeQL skipped"* ]]
}

@test "public repository sets skip=false" {
    export MOCK_DEFAULT_SETUP_STATE=""
    export MOCK_PRIVATE="false"
    run detect_codeql_support
    [ "$status" -eq 0 ]
    grep -q '^skip=false$' "${GITHUB_OUTPUT}"
    [[ ${output} == *"CodeQL will run"* ]]
}
