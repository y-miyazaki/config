#!/usr/bin/env bats

# Tests for .github/actions/schemaspy-bastion-connect/lib/connect.sh
#
# Use cases:
# - uses explicit bastion instance ID and writes outputs
# - fails when auto-detect finds no running instance

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"
# shellcheck disable=SC1091
source "${_bats_support}/support/aws_mock.bash"

CONNECT_LIB="$(bats_workspace_root)/.github/actions/schemaspy-bastion-connect/lib/connect.sh"

setup() {
    mock_aws_setup
    export GITHUB_ENV="${BATS_TEST_TMPDIR}/github_env"
    export GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/github_output"
    : > "${GITHUB_ENV}"
    : > "${GITHUB_OUTPUT}"
    export BASTION_INSTANCE_ID=""
    export BASTION_TAG_NAME="*bastion*"

    cat > "${MOCK_DIR}/curl" << 'EOF'
#!/usr/bin/env bash
output=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o)
            output="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done
touch "${output:-/tmp/session-manager-plugin.deb}"
exit 0
EOF
    chmod +x "${MOCK_DIR}/curl"

    cat > "${MOCK_DIR}/sudo" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "${MOCK_DIR}/sudo"

    cat > "${MOCK_DIR}/dpkg" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "${MOCK_DIR}/dpkg"

    cat > "${MOCK_DIR}/rm" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "${MOCK_DIR}/rm"
}

teardown() {
    mock_aws_teardown
}

@test "setup_bastion_connection uses explicit bastion instance id" {
    mock_aws_write << 'EOF'
#!/usr/bin/env bash
if [[ "$1" == "ssm" && "$2" == "describe-instance-information" ]]; then
    exit 0
fi
exit 1
EOF

    # shellcheck disable=SC1090
    source "${CONNECT_LIB}"
    run bash -c 'source "'"${CONNECT_LIB}"'"; BASTION_INSTANCE_ID=i-0123456789abcdef BASTION_TAG_NAME="*bastion*" GITHUB_ENV="'"${GITHUB_ENV}"'" GITHUB_OUTPUT="'"${GITHUB_OUTPUT}"'" setup_bastion_connection'
    [ "$status" -eq 0 ]
    grep -q '^BASTION_ID=i-0123456789abcdef$' "${GITHUB_ENV}"
    grep -q '^bastion_id=i-0123456789abcdef$' "${GITHUB_OUTPUT}"
}

@test "setup_bastion_connection rejects invalid explicit bastion instance id" {
    # shellcheck disable=SC1090
    source "${CONNECT_LIB}"
    run bash -c 'source "'"${CONNECT_LIB}"'"; BASTION_INSTANCE_ID=invalid BASTION_TAG_NAME="*bastion*" GITHUB_ENV="'"${GITHUB_ENV}"'" GITHUB_OUTPUT="'"${GITHUB_OUTPUT}"'" setup_bastion_connection'
    [ "$status" -eq 1 ]
    [[ $output == *"invalid bastion_instance_id format"* ]]
}

@test "setup_bastion_connection fails when auto-detect finds no instance" {
    mock_aws_write << 'EOF'
#!/usr/bin/env bash
if [[ "$1" == "ec2" && "$2" == "describe-instances" ]]; then
    exit 0
fi
exit 1
EOF

    # shellcheck disable=SC1090
    source "${CONNECT_LIB}"
    run bash -c 'source "'"${CONNECT_LIB}"'"; BASTION_INSTANCE_ID= BASTION_TAG_NAME="*bastion*" GITHUB_ENV="'"${GITHUB_ENV}"'" GITHUB_OUTPUT="'"${GITHUB_OUTPUT}"'" setup_bastion_connection'
    [ "$status" -eq 1 ]
    [[ $output == *"expected exactly one running Bastion instance"* ]]
}
