#!/bin/bash
#######################################
# Description:
#   Resolve SchemaSpy DB credentials and artifact naming outputs.
#
# Usage:
#   USE_SECRETS_MANAGER=true SECRETS_MANAGER_SECRET_ID=... bash lib/setup-parameters.sh
#
# Design Rules:
#   - Exactly one credential source: Secrets Manager, SSM, or direct inputs
#   - Shared JSON extraction for Secrets Manager and SSM branches
#
# Output:
#   DB_* values on GITHUB_ENV; artifact_* values on GITHUB_ENV and GITHUB_OUTPUT
#######################################

# Error handling: exit on error, unset variable, or failed pipeline
set -euo pipefail

# Secure defaults
umask 027
export LC_ALL=C.UTF-8

#######################################
# load_db_credentials_from_json: Extract DB fields from credential JSON
#
# Globals:
#   JSON_KEY_* - JSON key mapping
#   DB_NAME_INPUT - Optional db_name override
#   DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD - Set on success
#
# Arguments:
#   $1 - Credential JSON string
#
# Outputs:
#   None
#
# Returns:
#   Exits non-zero when database name cannot be resolved
#
#######################################
function load_db_credentials_from_json {
    # shellcheck disable=SC2129,SC2002
    local credential_json="$1"
    local -a json_keys=(HOST PORT DATABASE_NAME USERNAME PASSWORD)

    for key_name in "${json_keys[@]}"; do
        local key_var="JSON_KEY_${key_name}"
        local key_value="${!key_var:-}"
        if [[ -n ${key_value} && ! ${key_value} =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
            echo "Error: invalid JSON key name: ${key_value}" >&2
            return 1
        fi
    done

    DB_HOST=$(jq -r --arg key "${JSON_KEY_HOST}" '.[$key]' <<< "${credential_json}")
    DB_PORT=$(jq -r --arg key "${JSON_KEY_PORT}" '.[$key]' <<< "${credential_json}")
    DB_NAME_FROM_JSON=$(jq -r --arg key "${JSON_KEY_DATABASE_NAME}" '.[$key]' <<< "${credential_json}")
    DB_USER=$(jq -r --arg key "${JSON_KEY_USERNAME}" '.[$key]' <<< "${credential_json}")
    DB_PASSWORD=$(jq -r --arg key "${JSON_KEY_PASSWORD}" '.[$key]' <<< "${credential_json}")

    if [[ -n ${DB_NAME_INPUT} ]]; then
        DB_NAME="${DB_NAME_INPUT}"
    elif [[ ${DB_NAME_FROM_JSON} != "null" && -n ${DB_NAME_FROM_JSON} ]]; then
        DB_NAME="${DB_NAME_FROM_JSON}"
    else
        echo "Error: Database name not found in JSON and db_name input not provided" >&2
        return 1
    fi
}

#######################################
# setup_schemaspy_parameters: Resolve credentials and artifact naming
#
# Globals:
#   USE_SSM, USE_SECRETS_MANAGER, SECRETS_MANAGER_SECRET_ID, PARAMETER_STORE_NAME
#   DB_*_INPUT, DB_TYPE, ENVIRONMENT, GITHUB_ENV, GITHUB_OUTPUT
#
# Arguments:
#   None
#
# Outputs:
#   Writes DB and artifact variables to GITHUB_ENV and GITHUB_OUTPUT
#
# Returns:
#   Exits non-zero on invalid credential configuration
#
#######################################
function setup_schemaspy_parameters {
    local artifact_base=""
    local artifact_name=""
    local cred_source_count=0
    local db_json=""
    local outdir="output"
    local secret_json=""
    local title=""

    if [[ ${USE_SSM} == "true" ]]; then
        cred_source_count=$((cred_source_count + 1))
    fi
    if [[ ${USE_SECRETS_MANAGER} == "true" ]]; then
        cred_source_count=$((cred_source_count + 1))
    fi
    if [[ ${USE_SSM} == "false" && ${USE_SECRETS_MANAGER} == "false" ]]; then
        cred_source_count=$((cred_source_count + 1))
    fi

    if [[ ${cred_source_count} -gt 1 ]]; then
        echo "Error: Only one credential source can be enabled at a time" >&2
        echo "- use_ssm: ${USE_SSM}" >&2
        echo "- use_secrets_manager: ${USE_SECRETS_MANAGER}" >&2
        return 1
    fi

    if [[ ${USE_SECRETS_MANAGER} == "true" ]]; then
        if [[ -z ${SECRETS_MANAGER_SECRET_ID} ]]; then
            echo "Error: secrets_manager_secret_id is required when use_secrets_manager=true" >&2
            return 1
        fi
        secret_json=$(aws secretsmanager get-secret-value \
            --secret-id "${SECRETS_MANAGER_SECRET_ID}" \
            --query SecretString \
            --output text)
        load_db_credentials_from_json "${secret_json}"
    elif [[ ${USE_SSM} == "true" ]]; then
        if [[ -z ${PARAMETER_STORE_NAME} ]]; then
            echo "Error: parameter_store_name is required when use_ssm=true" >&2
            return 1
        fi
        db_json=$(aws ssm get-parameter --name "${PARAMETER_STORE_NAME}" --with-decryption --query "Parameter.Value" --output text)
        load_db_credentials_from_json "${db_json}"
    else
        if [[ -z ${DB_HOST_INPUT} || -z ${DB_PORT_INPUT} || -z ${DB_NAME_INPUT} || -z ${DB_USERNAME_INPUT} || -z ${DB_PASSWORD_INPUT} ]]; then
            echo "Error: When use_ssm=false and use_secrets_manager=false, DB_HOST, DB_PORT, DB_USERNAME, DB_PASSWORD secrets and db_name input must be provided" >&2
            return 1
        fi
        DB_HOST="${DB_HOST_INPUT}"
        DB_PORT="${DB_PORT_INPUT}"
        DB_NAME="${DB_NAME_INPUT}"
        DB_USER="${DB_USERNAME_INPUT}"
        DB_PASSWORD="${DB_PASSWORD_INPUT}"
    fi

    {
        echo "DB_HOST=${DB_HOST}"
        echo "DB_PORT=${DB_PORT}"
        echo "DB_NAME=${DB_NAME}"
        echo "DB_USER=${DB_USER}"
        echo "DB_PASSWORD=${DB_PASSWORD}"
    } >> "$GITHUB_ENV"
    echo "::add-mask::${DB_PASSWORD}"

    artifact_base="schemaspy-${DB_TYPE}-${DB_NAME}-${ENVIRONMENT}"
    artifact_name="${artifact_base}.zip"
    title="SchemaSpy(${ENVIRONMENT})"

    {
        echo "ARTIFACT_BASE=${artifact_base}"
        echo "ARTIFACT_NAME=${artifact_name}"
        echo "OUTDIR=${outdir}"
        echo "TITLE=${title}"
    } >> "$GITHUB_ENV"

    {
        echo "artifact_base=${artifact_base}"
        echo "artifact_name=${artifact_name}"
        echo "outdir=${outdir}"
        echo "title=${title}"
    } >> "$GITHUB_OUTPUT"
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    setup_schemaspy_parameters || exit $?
fi
