#!/bin/bash
#######################################
# Description:
#   Validate the caller-supplied detect_env_json object and build the KEY=VALUE arguments
#   that hand it to the detect script (a child process) and nothing else.
#
# Usage:
#   source detect_env.sh
#   detect_env_build_args "${DETECT_ENV_JSON}" || exit 1
#   env "${LOOP_DETECT_ENV_ARGS[@]}" bash "${DETECT_SCRIPT}"
#
# Output:
#   None (library file, sourced by other scripts)
#
# Design Rules:
#   - Entries reach only the detect script: they are never exported into the calling
#     process and never written to GITHUB_ENV
#   - Keys must match ^[A-Z_][A-Z0-9_]*$
#   - Reserved names (runner, loader, shell, git, gh, any *_PROXY or *_CA_BUNDLE, SSL_*, NODE_*, PYTHON*, PERL*, RUBY*,
#     and action-input variables) are rejected
#   - A key that is already set is rejected so a caller cannot override action inputs
#   - Values must be scalars without CR or LF; null and empty-string entries are skipped
#######################################

LOOP_DETECT_ENV_ARGS=()

#######################################
# detect_env_build_args: Validate detect_env_json and fill LOOP_DETECT_ENV_ARGS
#
# Globals:
#   LOOP_DETECT_ENV_ARGS - Reset, then filled with KEY=VALUE entries (write)
#
# Arguments:
#   $1 - JSON object text; empty or {} yields no entries
#
# Outputs:
#   Error lines on stderr when validation fails
#
# Returns:
#   0 on success; 1 on invalid JSON, key, value, or a reserved or already-set name
#
#######################################
function detect_env_build_args {
    local env_json="${1:-}"
    local key value_type value

    LOOP_DETECT_ENV_ARGS=()
    if [[ -z ${env_json} || ${env_json} == "{}" ]]; then
        return 0
    fi
    if ! jq -e 'type == "object"' > /dev/null 2>&1 <<< "${env_json}"; then
        echo "detect_env_json must be a JSON object" >&2
        return 1
    fi
    while IFS= read -r -d '' key && IFS= read -r -d '' value_type && IFS= read -r -d '' value; do
        if ! [[ ${key} =~ ^[A-Z_][A-Z0-9_]*$ ]]; then
            echo "detect_env_json keys must match ^[A-Z_][A-Z0-9_]*$ (invalid: ${key})" >&2
            return 1
        fi
        case "${key}" in
            BASH_* | BASHOPTS | CDPATH | CURL_* | DYLD_* | ENV | GH_* | GIT_* | GITHUB_* | GLOBIGNORE | HOME | IFS | INPUT_* | LD_* | NODE_* | PATH | PERL* | PS4 | PYTHON* | RUBY* | RUNNER_* | SHELL | SHELLOPTS | SSL_* | TMPDIR | *_CA_BUNDLE | *_PROXY | *_proxy)
                echo "detect_env_json key is reserved: ${key}" >&2
                return 1
                ;;
        esac
        # A null entry is never emitted, so it cannot conflict with an existing variable.
        [[ ${value_type} == "null" ]] && continue
        if [[ -v ${key} ]]; then
            echo "detect_env_json key conflicts with an existing variable: ${key}" >&2
            return 1
        fi
        case "${value_type}" in
            array | object)
                echo "detect_env_json values must be scalars (key: ${key})" >&2
                return 1
                ;;
        esac
        if [[ ${value} == *$'\n'* || ${value} == *$'\r'* ]]; then
            echo "detect_env_json values must not contain newlines (key: ${key})" >&2
            return 1
        fi
        if [[ -n ${value} ]]; then
            LOOP_DETECT_ENV_ARGS+=("${key}=${value}")
        fi
    done < <(jq -j 'to_entries[] | "\(.key)\u0000\(.value | type)\u0000\(.value | if type == "string" then . elif type == "null" or type == "array" or type == "object" then "" else tostring end)\u0000"' <<< "${env_json}")
}
