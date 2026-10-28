#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/detect-sarif-upload-support/lib/detect.sh
#
# Use cases:
# - public repository sets supported=true
# - private repository with Code Security enabled sets supported=true
# - private repository without Code Security sets supported=false

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
    bats_source_rel ".github/actions/detect-sarif-upload-support/lib/detect.sh"
}

teardown() {
    rm -f "${GITHUB_OUTPUT}"
}

@test "public repository sets supported=true" {
    export MOCK_PRIVATE="false"
    run detect_sarif_upload_support
    [ "$status" -eq 0 ]
    grep -q '^supported=true$' "${GITHUB_OUTPUT}"
    [[ ${output} == *"public repository"* ]]
}

@test "private repository with Code Security enabled sets supported=true" {
    export MOCK_PRIVATE="true"
    export MOCK_CODE_SECURITY="enabled"
    run detect_sarif_upload_support
    [ "$status" -eq 0 ]
    grep -q '^supported=true$' "${GITHUB_OUTPUT}"
    [[ ${output} == *"SARIF upload will run"* ]]
}

@test "private repository without Code Security sets supported=false" {
    export MOCK_PRIVATE="true"
    export MOCK_CODE_SECURITY=""
    run detect_sarif_upload_support
    [ "$status" -eq 0 ]
    grep -q '^supported=false$' "${GITHUB_OUTPUT}"
    [[ ${output} == *"SARIF upload skipped"* ]]
}
