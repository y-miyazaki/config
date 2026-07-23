#!/usr/bin/env bats

# Tests for .github/actions/schemaspy-ssm-port-forward/lib/port-forward.sh
#
# Use cases:
# - selects default local port by db type
# - honors explicit bastion local port
# - fails when ssm session process exits before ready
# - rejects invalid bastion id format

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"
# shellcheck disable=SC1091
source "${_bats_support}/support/aws_mock.bash"

PORT_FORWARD_LIB="$(bats_workspace_root)/.github/actions/schemaspy-ssm-port-forward/lib/port-forward.sh"

setup() {
    mock_aws_setup
    # Port-forward script waits on sleep; restore real sleep (mock_aws_setup stubs it to no-op).
    cat > "${MOCK_DIR}/sleep" << 'EOF'
#!/usr/bin/env bash
exec /bin/sleep "$@"
EOF
    chmod +x "${MOCK_DIR}/sleep"
    export GITHUB_ENV="${BATS_TEST_TMPDIR}/github_env"
    export GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/github_output"
    : > "${GITHUB_ENV}"
    : > "${GITHUB_OUTPUT}"
    export BASTION_ID="i-0123456789abcdef"
    export BASTION_LOCAL_PORT=""
    export DB_HOST="db.example"
    export DB_PORT="5432"
    export DB_TYPE="pgsql"
}

teardown() {
    local ssm_pid=""
    if [[ -f ${GITHUB_OUTPUT:-} ]]; then
        ssm_pid=$(grep '^ssm_pid=' "${GITHUB_OUTPUT}" | cut -d= -f2- || true)
        if [[ -n ${ssm_pid} ]]; then
            kill "${ssm_pid}" 2> /dev/null || true
        fi
    fi
    mock_aws_teardown
}

@test "setup_ssm_port_forward rejects invalid bastion id" {
    # shellcheck disable=SC1090
    source "${PORT_FORWARD_LIB}"
    run bash -c 'source "'"${PORT_FORWARD_LIB}"'"; BASTION_ID=invalid BASTION_LOCAL_PORT= DB_HOST=db.example DB_PORT=5432 DB_TYPE=pgsql GITHUB_ENV="'"${GITHUB_ENV}"'" GITHUB_OUTPUT="'"${GITHUB_OUTPUT}"'" setup_ssm_port_forward'
    [ "$status" -eq 1 ]
    [[ $output == *"invalid BASTION_ID format"* ]]
}

@test "setup_ssm_port_forward rejects invalid local port" {
    # shellcheck disable=SC1090
    source "${PORT_FORWARD_LIB}"
    run bash -c 'source "'"${PORT_FORWARD_LIB}"'"; BASTION_ID=i-0123456789abcdef BASTION_LOCAL_PORT=70000 DB_HOST=db.example DB_PORT=5432 DB_TYPE=pgsql GITHUB_ENV="'"${GITHUB_ENV}"'" GITHUB_OUTPUT="'"${GITHUB_OUTPUT}"'" setup_ssm_port_forward'
    [ "$status" -eq 1 ]
    [[ $output == *"invalid BASTION_LOCAL_PORT"* ]]
}

@test "setup_ssm_port_forward selects default pgsql local port" {
    mock_aws_write << 'EOF'
#!/usr/bin/env bash
if [[ "$1" == "ssm" && "$2" == "start-session" ]]; then
    echo "Port 15432 opened"
    echo "Waiting for connections"
    sleep 30
    exit 0
fi
exit 1
EOF

    # shellcheck disable=SC1090
    source "${PORT_FORWARD_LIB}"
    run bash -c 'source "'"${PORT_FORWARD_LIB}"'"; BASTION_ID=i-0123456789abcdef BASTION_LOCAL_PORT= DB_HOST=db.example DB_PORT=5432 DB_TYPE=pgsql GITHUB_ENV="'"${GITHUB_ENV}"'" GITHUB_OUTPUT="'"${GITHUB_OUTPUT}"'" setup_ssm_port_forward'
    [ "$status" -eq 0 ]
    grep -q '^LOCAL_PORT=15432$' "${GITHUB_ENV}"
    grep -q '^local_port=15432$' "${GITHUB_OUTPUT}"
}

@test "setup_ssm_port_forward honors explicit bastion local port" {
    mock_aws_write << 'EOF'
#!/usr/bin/env bash
if [[ "$1" == "ssm" && "$2" == "start-session" ]]; then
    echo "Port 19999 opened"
    echo "Waiting for connections"
    sleep 30
    exit 0
fi
exit 1
EOF

    # shellcheck disable=SC1090
    source "${PORT_FORWARD_LIB}"
    run bash -c 'source "'"${PORT_FORWARD_LIB}"'"; BASTION_ID=i-0123456789abcdef BASTION_LOCAL_PORT=19999 DB_HOST=db.example DB_PORT=5432 DB_TYPE=pgsql GITHUB_ENV="'"${GITHUB_ENV}"'" GITHUB_OUTPUT="'"${GITHUB_OUTPUT}"'" setup_ssm_port_forward'
    [ "$status" -eq 0 ]
    grep -q '^LOCAL_PORT=19999$' "${GITHUB_ENV}"
    grep -q '^local_port=19999$' "${GITHUB_OUTPUT}"
}

@test "setup_ssm_port_forward fails when session process exits early" {
    mock_aws_write << 'EOF'
#!/usr/bin/env bash
if [[ "$1" == "ssm" && "$2" == "start-session" ]]; then
    exit 1
fi
exit 1
EOF

    # shellcheck disable=SC1090
    source "${PORT_FORWARD_LIB}"
    run bash -c 'source "'"${PORT_FORWARD_LIB}"'"; BASTION_ID=i-0123456789abcdef BASTION_LOCAL_PORT=15432 DB_HOST=db.example DB_PORT=5432 DB_TYPE=pgsql GITHUB_ENV="'"${GITHUB_ENV}"'" GITHUB_OUTPUT="'"${GITHUB_OUTPUT}"'" setup_ssm_port_forward'
    [ "$status" -eq 1 ]
    [[ $output == *"SSM session process died unexpectedly"* ]]
}
