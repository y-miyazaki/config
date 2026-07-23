#!/usr/bin/env bats

# Tests for .github/actions/schemaspy-setup-parameters/lib/setup-parameters.sh
#
# Use cases:
# - rejects multiple credential sources enabled
# - direct credential mode writes DB and artifact outputs

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

SETUP_LIB="$(bats_workspace_root)/.github/actions/schemaspy-setup-parameters/lib/setup-parameters.sh"

setup() {
    export GITHUB_ENV="${BATS_TEST_TMPDIR}/github_env"
    export GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/github_output"
    : > "${GITHUB_ENV}"
    : > "${GITHUB_OUTPUT}"
    export USE_SSM="false"
    export USE_SECRETS_MANAGER="false" # pragma: allowlist secret
    export DB_HOST_INPUT="db.example"
    export DB_PORT_INPUT="5432"
    export DB_NAME_INPUT="appdb"
    export DB_USERNAME_INPUT="dbuser"
    export DB_PASSWORD_INPUT="dbpass" # pragma: allowlist secret
    export DB_TYPE="pgsql"
    export ENVIRONMENT="dev"
    export JSON_KEY_DATABASE_NAME="dbname"
    export JSON_KEY_HOST="host"
    export JSON_KEY_PASSWORD="password" # pragma: allowlist secret
    export JSON_KEY_PORT="port"
    export JSON_KEY_USERNAME="username"
    export PARAMETER_STORE_NAME=""
    export SECRETS_MANAGER_SECRET_ID=""
}

@test "setup_schemaspy_parameters rejects multiple credential sources" {
    # shellcheck disable=SC1090
    source "${SETUP_LIB}"
    run bash -c 'source "'"${SETUP_LIB}"'"; USE_SSM=true USE_SECRETS_MANAGER=true GITHUB_ENV="'"${GITHUB_ENV}"'" GITHUB_OUTPUT="'"${GITHUB_OUTPUT}"'" setup_schemaspy_parameters'
    [ "$status" -eq 1 ]
    [[ $output == *"Only one credential source can be enabled"* ]]
}

@test "setup_schemaspy_parameters writes direct credential outputs" {
    # shellcheck disable=SC1090
    source "${SETUP_LIB}"
    run bash -c 'source "'"${SETUP_LIB}"'"; USE_SSM=false USE_SECRETS_MANAGER=false DB_HOST_INPUT=db.example DB_PORT_INPUT=5432 DB_NAME_INPUT=appdb DB_USERNAME_INPUT=dbuser DB_PASSWORD_INPUT=dbpass DB_TYPE=pgsql ENVIRONMENT=dev JSON_KEY_DATABASE_NAME=dbname JSON_KEY_HOST=host JSON_KEY_PASSWORD=password JSON_KEY_PORT=port JSON_KEY_USERNAME=username PARAMETER_STORE_NAME= SECRETS_MANAGER_SECRET_ID= GITHUB_ENV="'"${GITHUB_ENV}"'" GITHUB_OUTPUT="'"${GITHUB_OUTPUT}"'" setup_schemaspy_parameters'
    [ "$status" -eq 0 ]
    grep -q '^DB_HOST=db.example$' "${GITHUB_ENV}"
    grep -q '^artifact_name=schemaspy-pgsql-appdb-dev.zip$' "${GITHUB_OUTPUT}"
}
