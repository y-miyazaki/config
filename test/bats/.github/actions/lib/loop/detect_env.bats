#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/lib/loop/detect_env.sh
#
# Use cases:
# - detect_env_build_args yields no entries for empty input and {}
# - detect_env_build_args builds KEY=VALUE entries and skips empty and null values
# - detect_env_build_args does not export entries or write GITHUB_ENV
# - detect_env_build_args rejects non-object JSON
# - detect_env_build_args rejects keys that do not match the allowed pattern
# - detect_env_build_args rejects reserved names
# - detect_env_build_args rejects proxy, CA bundle and interpreter-startup names
# - detect_env_build_args skips a null entry even when the variable is already set
# - detect_env_build_args rejects a key that is already set
# - detect_env_build_args rejects array and object values
# - detect_env_build_args rejects values containing a newline
# - the entries reach a child process through env

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/lib/loop/detect_env.sh"
    GITHUB_ENV="${BATS_TEST_TMPDIR}/github_env"
    : > "${GITHUB_ENV}"
    export GITHUB_ENV
}

@test "detect_env_build_args builds KEY=VALUE entries and skips empty and null values" {
    detect_env_build_args '{"DETECT_T_A":"one","DETECT_T_B":"","DETECT_T_C":3,"DETECT_T_D":null,"DETECT_T_E":true}'
    [ "${#LOOP_DETECT_ENV_ARGS[@]}" -eq 3 ]
    [ "${LOOP_DETECT_ENV_ARGS[0]}" = "DETECT_T_A=one" ]
    [ "${LOOP_DETECT_ENV_ARGS[1]}" = "DETECT_T_C=3" ]
    [ "${LOOP_DETECT_ENV_ARGS[2]}" = "DETECT_T_E=true" ]
}

@test "detect_env_build_args does not export entries or write GITHUB_ENV" {
    detect_env_build_args '{"DETECT_T_F":"x"}'
    [ -z "${DETECT_T_F+x}" ]
    [ ! -s "${GITHUB_ENV}" ]
}

@test "detect_env_build_args rejects a key that is already set" {
    export DETECT_T_G="existing"
    run detect_env_build_args '{"DETECT_T_G":"x"}'
    [ "$status" -eq 1 ]
    [[ $output == *"conflicts with an existing variable: DETECT_T_G"* ]]
}

@test "detect_env_build_args rejects array and object values" {
    run detect_env_build_args '{"DETECT_T_H":[1,2]}'
    [ "$status" -eq 1 ]
    [[ $output == *"must be scalars (key: DETECT_T_H)"* ]]
    run detect_env_build_args '{"DETECT_T_H":{"a":1}}'
    [ "$status" -eq 1 ]
}

@test "detect_env_build_args rejects keys that do not match the allowed pattern" {
    run detect_env_build_args '{"lower":"x"}'
    [ "$status" -eq 1 ]
    [[ $output == *"keys must match"* ]]
}

@test "detect_env_build_args rejects non-object JSON" {
    run detect_env_build_args '["A"]'
    [ "$status" -eq 1 ]
    [[ $output == *"must be a JSON object"* ]]
}

@test "detect_env_build_args rejects reserved names" {
    local key
    for key in BASH_ENV GH_TOKEN GIT_DIR GITHUB_TOKEN HTTPS_PROXY LD_PRELOAD NODE_OPTIONS PATH RUNNER_TEMP SSL_CERT_FILE TMPDIR; do
        run detect_env_build_args "{\"${key}\":\"x\"}"
        [ "$status" -eq 1 ]
        [[ $output == *"reserved: ${key}"* ]]
    done
}

@test "detect_env_build_args rejects proxy, CA bundle and interpreter-startup names" {
    local key
    for key in ALL_PROXY FTP_PROXY REQUESTS_CA_BUNDLE CURL_CA_BUNDLE NODE_EXTRA_CA_CERTS PYTHONPATH PERL5OPT RUBYOPT; do
        run detect_env_build_args "{\"${key}\":\"x\"}"
        [ "$status" -eq 1 ]
        [[ $output == *"reserved"* ]]
    done
}

@test "detect_env_build_args skips a null entry even when the variable is already set" {
    export DETECT_T_SET=1
    detect_env_build_args '{"DETECT_T_SET":null}'
    [ "${#LOOP_DETECT_ENV_ARGS[@]}" -eq 0 ]
}

@test "detect_env_build_args rejects values containing a newline" {
    run detect_env_build_args '{"DETECT_T_I":"a\nb"}'
    [ "$status" -eq 1 ]
    [[ $output == *"must not contain newlines (key: DETECT_T_I)"* ]]
}

@test "detect_env_build_args yields no entries for empty input and {}" {
    LOOP_DETECT_ENV_ARGS=(stale)
    detect_env_build_args ""
    [ "${#LOOP_DETECT_ENV_ARGS[@]}" -eq 0 ]
    detect_env_build_args "{}"
    [ "${#LOOP_DETECT_ENV_ARGS[@]}" -eq 0 ]
}

@test "the entries reach a child process through env" {
    detect_env_build_args '{"DETECT_T_J":"child value"}'
    # shellcheck disable=SC2016 # expansion must happen in the child shell
    run env "${LOOP_DETECT_ENV_ARGS[@]}" bash -c 'printf %s "${DETECT_T_J}"'
    [ "$status" -eq 0 ]
    [ "$output" = "child value" ]
    [ -z "${DETECT_T_J+x}" ]
}
